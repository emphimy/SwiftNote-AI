import Foundation
import CoreData
import Combine
import UIKit

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
    case syncRetry

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
        case .syncRetry:
            return "Sync retry"
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

    // MARK: - Initialization

    private init() {
        self.syncService = SupabaseSyncService.shared

        #if DEBUG
        print("🔄 AutoSyncManager: Initializing")
        #endif

        loadConfiguration()
        setupNotificationObservers()
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

        // Clear pending events
        pendingSyncEvents.removeAll()
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

    /// Setup notification observers for app lifecycle events
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

        #if DEBUG
        print("🔄 AutoSyncManager: Notification observers setup complete")
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

        // Stop timers to save battery
        stopPeriodicSync()
        stopDebounceTimer()
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

    /// Schedule a sync operation with debouncing
    private func scheduleSync(for event: AutoSyncEvent) {
        // Add event to pending list
        pendingSyncEvents.append(event)

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
        // Always sync immediately for certain events
        switch event {
        case .appDidBecomeActive, .userInitiated, .syncRetry:
            return true
        default:
            break
        }

        // Check minimum interval
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

    /// Handle successful sync
    private func handleSyncSuccess() {
        isSyncInProgress = false
        lastAutoSyncDate = Date()
        autoSyncStatus = "Synced"

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

    /// Handle sync failure
    private func handleSyncFailure(error: Error) {
        isSyncInProgress = false
        autoSyncStatus = "Error"

        #if DEBUG
        print("🔄 AutoSyncManager: Sync failed - \(error.localizedDescription)")
        #endif

        // Schedule retry after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            if self.autoSyncStatus == "Error" {
                self.triggerSync(event: .syncRetry)
                self.autoSyncStatus = "Active"
            }
        }
    }
}


