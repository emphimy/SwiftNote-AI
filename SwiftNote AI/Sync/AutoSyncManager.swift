import Foundation
import CoreData
import Combine
import UIKit
import Network
import BackgroundTasks

// MARK: - Auto Sync Configuration

/// Configuration for automatic sync behavior
struct AutoSyncConfiguration {
    /// Whether auto-sync is enabled
    let isEnabled: Bool

    /// Minimum interval between sync operations (in seconds)
    let minimumSyncInterval: TimeInterval

    /// Maximum time to wait before forcing a sync (in seconds)
    let maximumSyncDelay: TimeInterval

    /// Whether to sync on app foreground
    let syncOnAppForeground: Bool

    /// Whether to sync on data changes
    let syncOnDataChanges: Bool

    /// Default configuration
    static let `default` = AutoSyncConfiguration(
        isEnabled: true,
        minimumSyncInterval: 30.0,      // 30 seconds minimum between syncs
        maximumSyncDelay: 300.0,        // 5 minutes maximum delay
        syncOnAppForeground: true,
        syncOnDataChanges: true
    )

    /// Conservative configuration for slower networks
    static let conservative = AutoSyncConfiguration(
        isEnabled: true,
        minimumSyncInterval: 60.0,      // 1 minute minimum
        maximumSyncDelay: 600.0,        // 10 minutes maximum
        syncOnAppForeground: true,
        syncOnDataChanges: true
    )
}

// MARK: - Auto Sync Events

/// Events that can trigger automatic sync
enum AutoSyncEvent {
    case appDidBecomeActive
    case dataChanged(entityName: String)
    case periodicSync
    case userInitiated
    case networkReconnected
    case syncRetry(attempt: Int)
    case conflictDetected(entityName: String)
    case emergencySync
    case batchSync(eventCount: Int)

    var description: String {
        switch self {
        case .appDidBecomeActive:
            return "App became active"
        case .dataChanged(let entityName):
            return "Data changed: \(entityName)"
        case .periodicSync:
            return "Periodic sync"
        case .userInitiated:
            return "User initiated"
        case .networkReconnected:
            return "Network reconnected"
        case .syncRetry(let attempt):
            return "Sync retry (attempt \(attempt))"
        case .conflictDetected(let entityName):
            return "Conflict detected: \(entityName)"
        case .emergencySync:
            return "Emergency sync"
        case .batchSync(let eventCount):
            return "Batch sync (\(eventCount) events)"
        }
    }

    var priority: Int {
        switch self {
        case .emergencySync:
            return 100
        case .userInitiated:
            return 90
        case .conflictDetected:
            return 80
        case .appDidBecomeActive:
            return 70
        case .networkReconnected:
            return 60
        case .syncRetry:
            return 50
        case .dataChanged:
            return 40
        case .batchSync:
            return 30
        case .periodicSync:
            return 10
        }
    }
}

// MARK: - Auto Sync Manager

/// Manages automatic synchronization between local CoreData and Supabase
@MainActor
class AutoSyncManager: ObservableObject {

    // MARK: - Singleton
    static let shared = AutoSyncManager()

    // MARK: - Published Properties
    @Published var isAutoSyncEnabled: Bool = true
    @Published var lastAutoSyncDate: Date?
    @Published var autoSyncStatus: String = "Ready"
    @Published var pendingSyncEvents: [AutoSyncEvent] = []

    // MARK: - Private Properties
    private var configuration: AutoSyncConfiguration = .default
    private var syncService: SupabaseSyncService
    private var cancellables = Set<AnyCancellable>()

    /// Timer for periodic sync operations
    private var periodicSyncTimer: Timer?

    /// Timer for debouncing rapid changes
    private var debounceTimer: Timer?

    /// Queue for managing sync operations
    private let syncQueue = DispatchQueue(label: "com.swiftnote.autosync", qos: .utility)

    /// Last sync attempt timestamp
    private var lastSyncAttempt: Date?

    /// Whether a sync operation is currently in progress
    private var isSyncInProgress: Bool = false

    /// Network monitoring
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "AutoSyncNetworkMonitor")
    private var isNetworkAvailable = true
    private var networkType: NWInterface.InterfaceType?

    /// Background task management
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundSyncTimer: Timer?

    /// Enhanced error tracking and retry logic
    private var consecutiveFailures: Int = 0
    private var lastSyncError: Error?
    private var retryAttempts: Int = 0
    private var maxRetryAttempts: Int = 5
    private var retryDelayMultiplier: Double = 2.0
    private var baseRetryDelay: TimeInterval = 5.0

    /// Conflict resolution tracking
    private var detectedConflicts: Set<String> = []
    private var conflictResolutionInProgress: Bool = false

    /// Real-time sync optimization
    private var batchedEvents: [AutoSyncEvent] = []
    private var lastBatchTime: Date?
    private let batchWindow: TimeInterval = 3.0

    // MARK: - Initialization

    private init() {
        self.syncService = SupabaseSyncService.shared

        #if DEBUG
        print("🔄 AutoSyncManager: Initializing")
        #endif

        loadConfiguration()
        setupNotificationObservers()
        setupNetworkMonitoring()
    }

    // MARK: - Public Methods

    /// Start automatic sync monitoring
    func startAutoSync() {
        guard configuration.isEnabled else {
            #if DEBUG
            print("🔄 AutoSyncManager: Auto-sync is disabled")
            #endif
            return
        }

        #if DEBUG
        print("🔄 AutoSyncManager: Starting auto-sync")
        #endif

        isAutoSyncEnabled = true
        autoSyncStatus = "Active"

        // Start periodic sync timer
        startPeriodicSync()

        // Trigger initial sync if needed
        scheduleSync(for: .appDidBecomeActive)
    }

    /// Stop automatic sync monitoring
    func stopAutoSync() {
        #if DEBUG
        print("🔄 AutoSyncManager: Stopping auto-sync")
        #endif

        isAutoSyncEnabled = false
        autoSyncStatus = "Stopped"

        // Stop timers
        stopPeriodicSync()
        stopDebounceTimer()

        // End any background tasks
        endBackgroundTask()

        // Clear pending events
        pendingSyncEvents.removeAll()
    }

    /// Cleanup resources (called when app terminates)
    func cleanup() {
        #if DEBUG
        print("🔄 AutoSyncManager: Cleaning up resources")
        #endif

        stopAutoSync()
        networkMonitor.cancel()
        cancellables.removeAll()

        // Clear all state
        batchedEvents.removeAll()
        detectedConflicts.removeAll()
        pendingSyncEvents.removeAll()

        // Reset tracking variables
        consecutiveFailures = 0
        retryAttempts = 0
        conflictResolutionInProgress = false
    }

    /// Update auto-sync configuration
    func updateConfiguration(_ newConfiguration: AutoSyncConfiguration) {
        #if DEBUG
        print("🔄 AutoSyncManager: Updating configuration")
        #endif

        configuration = newConfiguration
        saveConfiguration()

        // Restart with new configuration if currently active
        if isAutoSyncEnabled {
            stopAutoSync()
            startAutoSync()
        }
    }

    /// Manually trigger a sync event
    func triggerSync(event: AutoSyncEvent) {
        guard isAutoSyncEnabled else { return }

        #if DEBUG
        print("🔄 AutoSyncManager: Triggering sync for event: \(event.description)")
        #endif

        scheduleSync(for: event)
    }

    // MARK: - Private Methods

    /// Load configuration from UserDefaults
    private func loadConfiguration() {
        // For now, use default configuration
        // TODO: Load from UserDefaults in future iterations
        configuration = .default

        #if DEBUG
        print("🔄 AutoSyncManager: Loaded configuration - enabled: \(configuration.isEnabled)")
        #endif
    }

    /// Save configuration to UserDefaults
    private func saveConfiguration() {
        // TODO: Save to UserDefaults in future iterations
        #if DEBUG
        print("🔄 AutoSyncManager: Configuration saved")
        #endif
    }

    /// Setup notification observers for app lifecycle events and data changes
    private func setupNotificationObservers() {
        // App lifecycle notifications
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleAppDidBecomeActive()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleAppDidEnterBackground()
                }
            }
            .store(in: &cancellables)

        // Core Data change notifications
        setupCoreDataObservers()

        #if DEBUG
        print("🔄 AutoSyncManager: Notification observers setup complete")
        #endif
    }

    /// Setup Core Data observers to detect data changes
    private func setupCoreDataObservers() {
        guard let context = PersistenceController.shared.container.viewContext as NSManagedObjectContext? else {
            #if DEBUG
            print("🔄 AutoSyncManager: Warning - Could not get managed object context for observers")
            #endif
            return
        }

        // Observe context save notifications
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .compactMap { notification in
                // Only process notifications from our main context
                guard let notificationContext = notification.object as? NSManagedObjectContext,
                      notificationContext == context else {
                    return nil
                }
                return notification
            }
            .sink { [weak self] notification in
                Task { @MainActor in
                    self?.handleCoreDataChanges(notification)
                }
            }
            .store(in: &cancellables)

        #if DEBUG
        print("🔄 AutoSyncManager: Core Data observers setup complete")
        #endif
    }

    /// Handle app becoming active
    private func handleAppDidBecomeActive() {
        guard configuration.syncOnAppForeground else { return }

        #if DEBUG
        print("🔄 AutoSyncManager: App became active")
        #endif

        triggerSync(event: .appDidBecomeActive)
    }

    /// Handle app entering background
    private func handleAppDidEnterBackground() {
        #if DEBUG
        print("🔄 AutoSyncManager: App entered background")
        #endif

        // Stop foreground timers to save battery
        stopPeriodicSync()
        stopDebounceTimer()

        // Schedule background sync if there are pending changes
        scheduleBackgroundSync()
    }

    /// Handle Core Data context save notifications
    private func handleCoreDataChanges(_ notification: Notification) {
        guard configuration.syncOnDataChanges else { return }

        // Don't trigger sync if we're currently syncing (prevents infinite loops)
        guard !isSyncInProgress else {
            #if DEBUG
            print("🔄 AutoSyncManager: Ignoring data changes during sync operation")
            #endif
            return
        }

        let userInfo = notification.userInfo ?? [:]
        var hasRelevantChanges = false
        var changedEntities: Set<String> = []

        // Check for inserted objects
        if let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            for object in insertedObjects {
                if let entityName = object.entity.name,
                   isRelevantEntity(entityName),
                   isUserInitiatedChange(object) {
                    hasRelevantChanges = true
                    changedEntities.insert(entityName)

                    #if DEBUG
                    print("🔄 AutoSyncManager: Detected inserted \(entityName)")
                    #endif
                }
            }
        }

        // Check for updated objects
        if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
            for object in updatedObjects {
                if let entityName = object.entity.name,
                   isRelevantEntity(entityName),
                   isUserInitiatedChange(object) {
                    hasRelevantChanges = true
                    changedEntities.insert(entityName)

                    #if DEBUG
                    print("🔄 AutoSyncManager: Detected updated \(entityName)")
                    #endif
                }
            }
        }

        // Check for deleted objects
        if let deletedObjects = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> {
            for object in deletedObjects {
                if let entityName = object.entity.name,
                   isRelevantEntity(entityName),
                   isUserInitiatedChange(object) {
                    hasRelevantChanges = true
                    changedEntities.insert(entityName)

                    #if DEBUG
                    print("🔄 AutoSyncManager: Detected deleted \(entityName)")
                    #endif
                }
            }
        }

        // Trigger sync if we have relevant changes
        if hasRelevantChanges {
            for entityName in changedEntities {
                let event = AutoSyncEvent.dataChanged(entityName: entityName)
                triggerSync(event: event)
            }
        }
    }

    /// Check if an entity is relevant for auto-sync
    private func isRelevantEntity(_ entityName: String) -> Bool {
        return entityName == "Note" || entityName == "Folder"
    }

    /// Check if a change is user-initiated (not from sync operations)
    private func isUserInitiatedChange(_ object: NSManagedObject) -> Bool {
        // Check if the object has syncStatus = "pending" which indicates user changes
        if let note = object as? Note {
            return note.syncStatus == "pending"
        } else if let folder = object as? Folder {
            return folder.syncStatus == "pending"
        }

        // For new objects without syncStatus set, consider them user-initiated
        return true
    }

    /// Setup network monitoring
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handleNetworkChange(path)
            }
        }

        networkMonitor.start(queue: networkQueue)

        #if DEBUG
        print("🔄 AutoSyncManager: Network monitoring started")
        #endif
    }

    /// Handle network connectivity changes
    private func handleNetworkChange(_ path: NWPath) {
        let wasNetworkAvailable = isNetworkAvailable
        isNetworkAvailable = path.status == .satisfied

        // Determine network type
        if path.usesInterfaceType(.wifi) {
            networkType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            networkType = .cellular
        } else {
            networkType = nil
        }

        #if DEBUG
        let networkTypeString: String
        if let type = networkType {
            switch type {
            case .wifi: networkTypeString = "wifi"
            case .cellular: networkTypeString = "cellular"
            case .wiredEthernet: networkTypeString = "ethernet"
            case .loopback: networkTypeString = "loopback"
            case .other: networkTypeString = "other"
            @unknown default: networkTypeString = "unknown"
            }
        } else {
            networkTypeString = "none"
        }
        print("🔄 AutoSyncManager: Network status changed - Available: \(isNetworkAvailable), Type: \(networkTypeString)")
        #endif

        // If network became available and we have pending changes, trigger sync
        if !wasNetworkAvailable && isNetworkAvailable && !pendingSyncEvents.isEmpty {
            #if DEBUG
            print("🔄 AutoSyncManager: Network reconnected, triggering sync")
            #endif
            triggerSync(event: .networkReconnected)
        }
    }

    /// Schedule background sync for pending changes
    private func scheduleBackgroundSync() {
        guard !pendingSyncEvents.isEmpty else {
            #if DEBUG
            print("🔄 AutoSyncManager: No pending changes for background sync")
            #endif
            return
        }

        guard isNetworkAvailable else {
            #if DEBUG
            print("🔄 AutoSyncManager: Network unavailable, skipping background sync")
            #endif
            return
        }

        // Start background task
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "AutoSync") { [weak self] in
            #if DEBUG
            print("🔄 AutoSyncManager: Background task expired")
            #endif
            self?.endBackgroundTask()
        }

        guard backgroundTaskID != .invalid else {
            #if DEBUG
            print("🔄 AutoSyncManager: Failed to start background task")
            #endif
            return
        }

        #if DEBUG
        print("🔄 AutoSyncManager: Started background sync task")
        #endif

        // Schedule background sync with a short delay
        backgroundSyncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performBackgroundSync()
            }
        }
    }

    /// Perform sync in background
    private func performBackgroundSync() {
        guard backgroundTaskID != .invalid else { return }

        #if DEBUG
        print("🔄 AutoSyncManager: Performing background sync")
        #endif

        // Use the existing performSync method but with background context
        performSync()

        // End background task after a delay to allow sync to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            self?.endBackgroundTask()
        }
    }

    /// End background task
    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }

        #if DEBUG
        print("🔄 AutoSyncManager: Ending background task")
        #endif

        backgroundSyncTimer?.invalidate()
        backgroundSyncTimer = nil

        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    /// Start periodic sync timer
    private func startPeriodicSync() {
        stopPeriodicSync() // Stop existing timer

        let interval = configuration.maximumSyncDelay

        periodicSyncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.triggerSync(event: .periodicSync)
            }
        }

        #if DEBUG
        print("🔄 AutoSyncManager: Started periodic sync timer (interval: \(interval)s)")
        #endif
    }

    /// Stop periodic sync timer
    private func stopPeriodicSync() {
        periodicSyncTimer?.invalidate()
        periodicSyncTimer = nil

        #if DEBUG
        print("🔄 AutoSyncManager: Stopped periodic sync timer")
        #endif
    }

    /// Stop debounce timer
    private func stopDebounceTimer() {
        debounceTimer?.invalidate()
        debounceTimer = nil
    }

    /// Schedule a sync operation with priority-based handling and batching
    private func scheduleSync(for event: AutoSyncEvent) {
        #if DEBUG
        print("🔄 AutoSyncManager: Scheduling sync for event: \(event.description) (priority: \(event.priority))")
        #endif

        // Handle high-priority events immediately
        if event.priority >= 80 {
            // Clear any batched events and process immediately
            if !batchedEvents.isEmpty {
                let batchEvent = AutoSyncEvent.batchSync(eventCount: batchedEvents.count)
                pendingSyncEvents.append(batchEvent)
                batchedEvents.removeAll()
            }

            pendingSyncEvents.append(event)
            performSync()
            return
        }

        // Handle conflict detection
        if case .conflictDetected(let entityName) = event {
            detectedConflicts.insert(entityName)
            if !conflictResolutionInProgress {
                conflictResolutionInProgress = true
                pendingSyncEvents.append(event)
                performSync()
                return
            }
        }

        // Batch low-priority events for efficiency
        if event.priority <= 40 {
            batchedEvents.append(event)
            lastBatchTime = Date()

            // Start batch timer if not already running
            startBatchTimer()
            return
        }

        // Add event to pending list with priority sorting
        pendingSyncEvents.append(event)
        pendingSyncEvents.sort { $0.priority > $1.priority }

        // Check if we should sync immediately or wait
        if shouldSyncImmediately(for: event) {
            performSync()
        } else {
            // Start/restart debounce timer
            startDebounceTimer()
        }
    }

    /// Check if sync should happen immediately
    private func shouldSyncImmediately(for event: AutoSyncEvent) -> Bool {
        // Don't sync if network is unavailable (except for emergency sync)
        guard isNetworkAvailable || event.priority >= 100 else {
            #if DEBUG
            print("🔄 AutoSyncManager: Network unavailable, deferring sync")
            #endif
            return false
        }

        // Always sync immediately for high-priority events
        switch event {
        case .emergencySync, .userInitiated, .conflictDetected:
            return true
        case .appDidBecomeActive, .networkReconnected:
            return true
        case .syncRetry(let attempt):
            // Immediate retry for first few attempts, then use exponential backoff
            return attempt <= 2
        default:
            break
        }

        // Check minimum interval for regular events
        if let lastSync = lastSyncAttempt {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            return timeSinceLastSync >= configuration.minimumSyncInterval
        }

        return true
    }

    /// Start debounce timer for batching rapid changes
    private func startDebounceTimer() {
        stopDebounceTimer()

        debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performSync()
            }
        }
    }

    /// Start batch timer for collecting low-priority events
    private func startBatchTimer() {
        // Don't start a new timer if one is already running
        guard backgroundSyncTimer == nil else { return }

        backgroundSyncTimer = Timer.scheduledTimer(withTimeInterval: batchWindow, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.processBatchedEvents()
            }
        }
    }

    /// Process batched events as a single sync operation
    private func processBatchedEvents() {
        guard !batchedEvents.isEmpty else { return }

        #if DEBUG
        print("🔄 AutoSyncManager: Processing \(batchedEvents.count) batched events")
        #endif

        let batchEvent = AutoSyncEvent.batchSync(eventCount: batchedEvents.count)
        batchedEvents.removeAll()
        lastBatchTime = nil

        // Stop the batch timer
        backgroundSyncTimer?.invalidate()
        backgroundSyncTimer = nil

        // Schedule the batch sync
        pendingSyncEvents.append(batchEvent)
        performSync()
    }

    /// Perform the actual sync operation
    private func performSync() {
        guard !isSyncInProgress else {
            #if DEBUG
            print("🔄 AutoSyncManager: Sync already in progress, skipping")
            #endif
            return
        }

        guard !pendingSyncEvents.isEmpty else {
            #if DEBUG
            print("🔄 AutoSyncManager: No pending sync events")
            #endif
            return
        }

        isSyncInProgress = true
        lastSyncAttempt = Date()
        autoSyncStatus = "Syncing..."

        let eventsToProcess = pendingSyncEvents
        pendingSyncEvents.removeAll()

        #if DEBUG
        print("🔄 AutoSyncManager: Starting sync for \(eventsToProcess.count) events")
        #endif

        // Perform sync on background queue
        Task {
            do {
                let context = PersistenceController.shared.container.viewContext

                // Use existing sync service with binary data included
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    syncService.syncToSupabase(
                        context: context,
                        includeBinaryData: true,  // Always include binary data in auto-sync
                        twoWaySync: true
                    ) { success, error in
                        if success {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: error ?? NSError(domain: "AutoSyncManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sync failed"]))
                        }
                    }
                }

                await MainActor.run {
                    self.handleSyncSuccess()
                }

            } catch {
                await MainActor.run {
                    self.handleSyncFailure(error: error)
                }
            }
        }
    }

    /// Handle successful sync with enhanced tracking
    private func handleSyncSuccess() {
        isSyncInProgress = false
        lastAutoSyncDate = Date()
        autoSyncStatus = "Synced"

        // Reset error tracking
        consecutiveFailures = 0
        retryAttempts = 0
        lastSyncError = nil

        // Clear conflict resolution state
        conflictResolutionInProgress = false
        detectedConflicts.removeAll()

        #if DEBUG
        print("🔄 AutoSyncManager: Sync completed successfully")
        #endif

        // Auto-clear status after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.autoSyncStatus == "Synced" {
                self.autoSyncStatus = "Active"
            }
        }
    }

    /// Handle sync failure with intelligent retry logic
    private func handleSyncFailure(error: Error) {
        isSyncInProgress = false
        consecutiveFailures += 1
        lastSyncError = error

        let errorMessage = error.localizedDescription
        autoSyncStatus = "Error: \(errorMessage)"

        #if DEBUG
        print("🔄 AutoSyncManager: Sync failed (failure #\(consecutiveFailures)): \(error)")
        #endif

        // Analyze error type for appropriate response
        let shouldRetry = shouldRetryAfterError(error)

        if shouldRetry && retryAttempts < maxRetryAttempts {
            retryAttempts += 1

            // Schedule intelligent retry with exponential backoff
            scheduleIntelligentRetry()
        } else {
            // Max retries reached or non-retryable error
            #if DEBUG
            print("🔄 AutoSyncManager: Max retries reached or non-retryable error")
            #endif

            // Reset retry state
            retryAttempts = 0

            // For critical errors, trigger emergency sync after a longer delay
            if isCriticalError(error) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 300) { // 5 minutes
                    self.triggerSync(event: .emergencySync)
                }
            } else {
                // Regular retry after extended delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) {
                    if self.autoSyncStatus.hasPrefix("Error") {
                        self.triggerSync(event: .syncRetry(attempt: 1))
                        self.autoSyncStatus = "Active"
                    }
                }
            }
        }
    }

    // MARK: - Advanced Error Handling & Conflict Resolution

    /// Determine if an error should trigger a retry
    private func shouldRetryAfterError(_ error: Error) -> Bool {
        // Network-related errors are usually retryable
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut:
                return true
            case .badServerResponse, .cannotFindHost, .cannotConnectToHost:
                return true
            default:
                return false
            }
        }

        // Supabase-specific errors
        if error.localizedDescription.contains("network") ||
           error.localizedDescription.contains("timeout") ||
           error.localizedDescription.contains("connection") {
            return true
        }

        // Authentication errors might be retryable after token refresh
        if error.localizedDescription.contains("unauthorized") ||
           error.localizedDescription.contains("authentication") {
            return true
        }

        return false
    }

    /// Determine if an error is critical and requires emergency handling
    private func isCriticalError(_ error: Error) -> Bool {
        // Data corruption or integrity errors
        if error.localizedDescription.contains("corruption") ||
           error.localizedDescription.contains("integrity") ||
           error.localizedDescription.contains("constraint") {
            return true
        }

        // Multiple consecutive failures indicate a critical issue
        return consecutiveFailures >= 3
    }

    /// Schedule intelligent retry with exponential backoff
    private func scheduleIntelligentRetry() {
        let delay = baseRetryDelay * pow(retryDelayMultiplier, Double(retryAttempts - 1))
        let maxDelay: TimeInterval = 300 // 5 minutes max
        let actualDelay = min(delay, maxDelay)

        #if DEBUG
        print("🔄 AutoSyncManager: Scheduling retry #\(retryAttempts) in \(actualDelay) seconds")
        #endif

        DispatchQueue.main.asyncAfter(deadline: .now() + actualDelay) {
            self.triggerSync(event: .syncRetry(attempt: self.retryAttempts))
        }
    }

    /// Perform conflict resolution before sync
    private func performConflictResolution() async throws {
        #if DEBUG
        print("🔄 AutoSyncManager: Performing conflict resolution for entities: \(detectedConflicts)")
        #endif

        // For now, use "Last Write Wins" strategy as mentioned in user preferences
        // This could be enhanced with more sophisticated conflict resolution

        for entityName in detectedConflicts {
            try await resolveConflictsForEntity(entityName)
        }

        #if DEBUG
        print("🔄 AutoSyncManager: Conflict resolution completed")
        #endif
    }

    /// Resolve conflicts for a specific entity using Last Write Wins
    private func resolveConflictsForEntity(_ entityName: String) async throws {
        let context = PersistenceController.shared.container.viewContext

        #if DEBUG
        print("🔄 AutoSyncManager: Resolving conflicts for \(entityName) using Last Write Wins")
        #endif

        switch entityName {
        case "Note":
            try await resolveNoteConflicts(context: context)
        case "Folder":
            try await resolveFolderConflicts(context: context)
        default:
            #if DEBUG
            print("🔄 AutoSyncManager: Unknown entity type for conflict resolution: \(entityName)")
            #endif
        }
    }

    /// Resolve Note conflicts using Last Write Wins strategy
    private func resolveNoteConflicts(context: NSManagedObjectContext) async throws {
        // Fetch all notes with pending sync status (potential conflicts)
        let fetchRequest: NSFetchRequest<Note> = Note.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "syncStatus == %@", "pending")

        let pendingNotes = try context.fetch(fetchRequest)

        #if DEBUG
        print("🔄 AutoSyncManager: Found \(pendingNotes.count) notes with potential conflicts")
        #endif

        for note in pendingNotes {
            guard let noteId = note.id else { continue }

            // Fetch the corresponding remote note to compare timestamps
            if let remoteNote = try await fetchRemoteNote(id: noteId) {
                let localModified = note.lastModified ?? note.timestamp ?? Date.distantPast
                let remoteModified = remoteNote.lastModified

                #if DEBUG
                print("🔄 AutoSyncManager: Note \(noteId) - Local: \(localModified), Remote: \(remoteModified)")
                #endif

                // Last Write Wins: Compare timestamps
                if remoteModified > localModified {
                    // Remote is newer - update local with remote data
                    #if DEBUG
                    print("🔄 AutoSyncManager: Remote note is newer, updating local")
                    #endif
                    try await updateLocalNote(note: note, with: remoteNote, context: context)
                } else {
                    // Local is newer or same - keep local, mark as resolved
                    #if DEBUG
                    print("🔄 AutoSyncManager: Local note is newer or same, keeping local")
                    #endif
                    note.syncStatus = "synced"
                }
            }
        }

        try context.save()
    }

    /// Resolve Folder conflicts using Last Write Wins strategy
    private func resolveFolderConflicts(context: NSManagedObjectContext) async throws {
        // Fetch all folders with pending sync status (potential conflicts)
        let fetchRequest: NSFetchRequest<Folder> = Folder.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "syncStatus == %@", "pending")

        let pendingFolders = try context.fetch(fetchRequest)

        #if DEBUG
        print("🔄 AutoSyncManager: Found \(pendingFolders.count) folders with potential conflicts")
        #endif

        for folder in pendingFolders {
            guard let folderId = folder.id else { continue }

            // Fetch the corresponding remote folder to compare timestamps
            if let remoteFolder = try await fetchRemoteFolder(id: folderId) {
                let localModified = folder.updatedAt ?? folder.timestamp ?? Date.distantPast
                let remoteModified = remoteFolder.updatedAt ?? remoteFolder.timestamp

                #if DEBUG
                print("🔄 AutoSyncManager: Folder \(folderId) - Local: \(localModified), Remote: \(remoteModified)")
                #endif

                // Last Write Wins: Compare timestamps
                if remoteModified > localModified {
                    // Remote is newer - update local with remote data
                    #if DEBUG
                    print("🔄 AutoSyncManager: Remote folder is newer, updating local")
                    #endif
                    try await updateLocalFolder(folder: folder, with: remoteFolder, context: context)
                } else {
                    // Local is newer or same - keep local, mark as resolved
                    #if DEBUG
                    print("🔄 AutoSyncManager: Local folder is newer or same, keeping local")
                    #endif
                    folder.syncStatus = "synced"
                }
            }
        }

        try context.save()
    }

    // MARK: - Remote Data Fetching

    /// Fetch a remote note by ID from Supabase
    private func fetchRemoteNote(id: UUID) async throws -> SimpleSupabaseNote? {
        // Get current user session
        let session = try await SupabaseService.shared.getSession()
        let userId = session.user.id

        do {
            let response: [SimpleSupabaseNote] = try await SupabaseService.shared.fetch(
                from: "notes",
                filters: { query in
                    query.eq("id", value: id.uuidString)
                        .eq("user_id", value: userId.uuidString)
                }
            )

            return response.first
        } catch {
            #if DEBUG
            print("🔄 AutoSyncManager: Failed to fetch remote note \(id): \(error)")
            #endif
            return nil
        }
    }

    /// Fetch a remote folder by ID from Supabase
    private func fetchRemoteFolder(id: UUID) async throws -> SimpleSupabaseFolder? {
        // Get current user session
        let session = try await SupabaseService.shared.getSession()
        let userId = session.user.id

        do {
            let response: [SimpleSupabaseFolder] = try await SupabaseService.shared.fetch(
                from: "folders",
                filters: { query in
                    query.eq("id", value: id.uuidString)
                        .eq("user_id", value: userId.uuidString)
                }
            )

            return response.first
        } catch {
            #if DEBUG
            print("🔄 AutoSyncManager: Failed to fetch remote folder \(id): \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Local Data Updates

    /// Update local note with remote data (remote wins)
    private func updateLocalNote(note: Note, with remoteNote: SimpleSupabaseNote, context: NSManagedObjectContext) async throws {
        #if DEBUG
        print("🔄 AutoSyncManager: Updating local note \(note.id?.uuidString ?? "unknown") with remote data")
        #endif

        // Update basic fields
        note.title = remoteNote.title
        note.sourceType = remoteNote.sourceType
        note.timestamp = remoteNote.timestamp
        note.lastModified = remoteNote.lastModified
        note.isFavorite = remoteNote.isFavorite
        note.processingStatus = remoteNote.processingStatus

        // Update optional fields
        note.keyPoints = remoteNote.keyPoints
        note.citations = remoteNote.citations
        note.duration = remoteNote.duration ?? 0.0
        if let sourceURLString = remoteNote.sourceURL {
            note.sourceURL = URL(string: sourceURLString)
        } else {
            note.sourceURL = nil
        }
        note.tags = remoteNote.tags
        note.transcript = remoteNote.transcript
        note.videoId = remoteNote.videoId

        // Update folder relationship if needed
        if let remoteFolderId = remoteNote.folderId {
            let folderFetch: NSFetchRequest<Folder> = Folder.fetchRequest()
            folderFetch.predicate = NSPredicate(format: "id == %@", remoteFolderId as CVarArg)
            if let folder = try context.fetch(folderFetch).first {
                note.folder = folder
            }
        } else {
            note.folder = nil
        }

        // Mark as synced
        note.syncStatus = "synced"

        #if DEBUG
        print("🔄 AutoSyncManager: Successfully updated local note with remote data")
        #endif
    }

    /// Update local folder with remote data (remote wins)
    private func updateLocalFolder(folder: Folder, with remoteFolder: SimpleSupabaseFolder, context: NSManagedObjectContext) async throws {
        #if DEBUG
        print("🔄 AutoSyncManager: Updating local folder \(folder.id?.uuidString ?? "unknown") with remote data")
        #endif

        // Update basic fields
        folder.name = remoteFolder.name
        folder.color = remoteFolder.color
        folder.timestamp = remoteFolder.timestamp
        folder.sortOrder = remoteFolder.sortOrder
        folder.updatedAt = remoteFolder.updatedAt ?? remoteFolder.timestamp

        // Mark as synced
        folder.syncStatus = "synced"

        #if DEBUG
        print("🔄 AutoSyncManager: Successfully updated local folder with remote data")
        #endif
    }

    /// Detect potential conflicts during data changes
    func detectConflict(for entityName: String, objectID: NSManagedObjectID) {
        guard !conflictResolutionInProgress else { return }

        #if DEBUG
        print("🔄 AutoSyncManager: Potential conflict detected for \(entityName)")
        #endif

        detectedConflicts.insert(entityName)
        triggerSync(event: .conflictDetected(entityName: entityName))
    }

    /// Public method to trigger emergency sync
    func triggerEmergencySync() {
        #if DEBUG
        print("🔄 AutoSyncManager: Emergency sync triggered")
        #endif

        triggerSync(event: .emergencySync)
    }
}


