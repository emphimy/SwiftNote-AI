import SwiftUI
import CoreData
import Combine
import SafariServices
import LocalAuthentication

// MARK: - Models
struct SettingsSection: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
}

// MARK: - ViewModel
@MainActor
final class SettingsViewModel: ObservableObject {
    // Notifications removed
    @AppStorage("autoBackupEnabled") var autoBackupEnabled = true
    @AppStorage("biometricLockEnabled") var biometricLockEnabled = false
    @AppStorage("biometricEnabled") var biometricEnabled = false
    @AppStorage("syncBinaryDataEnabled") var syncBinaryDataEnabled = false
    @AppStorage("twoWaySyncEnabled") var twoWaySyncEnabled = true
    @Published var lastSupabaseSync: Date?

    @Published var biometricType: BiometricType = .none

    @Published var showingSaveDialog = false
    @Published var storageUsage: StorageUsage?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingPrivacyPolicy = false
    @Published var showingDeleteAccountAlert = false
    // Logout alert removed
    @Published var failedRecordings: [FailedRecording] = []
    @Published var exportURL: ExportURLWrapper?
    @Published var isSyncing = false
    @Published var syncResult: (success: Bool, message: String)? = nil
    @Published var isFixingAudioNotes = false
    @Published var isFixingRemoteSync = false

    private var cancellables = Set<AnyCancellable>()

    struct StorageUsage {
        let used: Int64
        let total: Int64
        var usedPercentage: Double { Double(used) / Double(total) }

        var formattedUsed: String { ByteCountFormatter.string(fromByteCount: used, countStyle: .file) }
        var formattedTotal: String { ByteCountFormatter.string(fromByteCount: total, countStyle: .file) }
    }

    struct FailedRecording: Identifiable {
        let id = UUID()
        let date: Date
        let duration: TimeInterval
        let errorMessage: String
        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        var formattedDuration: String {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    func toggleBiometric() async throws {
        #if DEBUG
        print("⚙️ SettingsViewModel: Attempting to toggle biometric auth")
        #endif

        // Get the current biometric type
        biometricType = BiometricAuthManager.shared.biometricType()

        // Check if biometric auth is available
        guard biometricType != .none else {
            #if DEBUG
            print("⚙️ SettingsViewModel: Biometric auth not available")
            #endif
            throw NSError(domain: "Settings", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Biometric authentication not available on this device"])
        }

        // If we're turning it off, no need to authenticate first
        if biometricEnabled {
            biometricEnabled = false
            BiometricAuthManager.shared.setAppLock(enabled: false)
            return
        }

        // Request biometric authentication
        do {
            let success = try await BiometricAuthManager.shared.authenticate(
                reason: "Enable \(biometricType.description) for SwiftNote AI"
            )

            if success {
                #if DEBUG
                print("⚙️ SettingsViewModel: Biometric auth toggle successful")
                #endif

                biometricEnabled = true
                // Ask if they want to lock the app with biometrics
                biometricLockEnabled = true
                BiometricAuthManager.shared.setAppLock(enabled: true)
            }
        } catch {
            #if DEBUG
            print("⚙️ SettingsViewModel: Biometric auth failed - \(error)")
            #endif
            throw error
        }
    }

    func fetchFailedRecordings() {
        #if DEBUG
        print("⚙️ SettingsViewModel: Fetching failed recordings")
        #endif

        // Data is already pre-populated in init, so we don't need to do anything here
        // This method is kept for compatibility with existing code
    }

    /// Sync folders and notes with Supabase (bidirectional)
    /// - Parameter context: The NSManagedObjectContext
    func syncToSupabase(context: NSManagedObjectContext) {
        #if DEBUG
        print("⚙️ SettingsViewModel: Starting Supabase sync - Two-way: \(twoWaySyncEnabled), Binary data: \(syncBinaryDataEnabled)")
        #endif

        // Reset previous result
        syncResult = nil
        isSyncing = true

        // Call the sync service with binary data and two-way sync options
        SupabaseSyncService.shared.syncToSupabase(context: context, includeBinaryData: syncBinaryDataEnabled, twoWaySync: twoWaySyncEnabled) { success, error in
            self.isSyncing = false

            if success {
                let syncTypeMessage = self.twoWaySyncEnabled ? "Two-way sync" : "Upload"
                let binaryDataMessage = self.syncBinaryDataEnabled ? " with binary data" : ""
                self.syncResult = (success: true, message: "\(syncTypeMessage) completed successfully\(binaryDataMessage)")
                let now = Date()
                self.lastSupabaseSync = now

                // Save to UserDefaults
                UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "lastSupabaseSyncDate")

                #if DEBUG
                print("⚙️ SettingsViewModel: Sync completed successfully")
                #endif
            } else {
                // Provide more detailed error information
                var errorMessage = "Unknown error"
                var errorDetails = ""

                if let error = error {
                    errorMessage = error.localizedDescription
                    errorDetails = "\(error)"

                    #if DEBUG
                    print("⚙️ SettingsViewModel: Sync failed with detailed error: \(errorDetails)")
                    #endif

                    // Check for specific error types (priority order matters)
                    if let nsError = error as NSError?, nsError.code == 409 {
                        // Sync lock error (HTTP 409 Conflict) - highest priority
                        errorMessage = "Another sync is already in progress. Please wait for it to complete."
                    } else if let nsError = error as NSError?, nsError.code == 401 {
                        // Token validation/authentication errors (HTTP 401 Unauthorized)
                        if errorMessage.contains("Session expired") || errorMessage.contains("refresh") {
                            errorMessage = "Your session has expired. Please sign in again."
                        } else if errorMessage.contains("Authentication required") {
                            errorMessage = "Authentication required. Please sign in to sync your data."
                        } else {
                            errorMessage = "Authentication failed. Please sign in again."
                        }
                    } else if errorMessage.contains("network") || errorMessage.contains("connection") {
                        errorMessage = "Network connection failed. Please check your internet connection."
                    } else if errorMessage.contains("CoreData") || errorMessage.contains("save") {
                        errorMessage = "Failed to save data locally. Please try again."
                    }
                }

                self.syncResult = (success: false, message: "Sync failed: \(errorMessage)")

                #if DEBUG
                print("⚙️ SettingsViewModel: Sync failed - \(errorMessage)")
                if !errorDetails.isEmpty {
                    print("⚙️ SettingsViewModel: Full error details: \(errorDetails)")
                }
                #endif
            }

            // Auto-dismiss the result after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self.syncResult = nil
            }
        }
    }

    /// Fix existing audio notes that may have incorrect syncStatus
    /// - Parameter context: The NSManagedObjectContext
    func fixAudioNotes(context: NSManagedObjectContext) {
        #if DEBUG
        print("⚙️ SettingsViewModel: Starting audio notes fix")
        #endif

        isFixingAudioNotes = true

        Task {
            do {
                let fixedCount = try await SupabaseSyncService.shared.fixAudioNoteSyncStatus(context: context)

                await MainActor.run {
                    self.isFixingAudioNotes = false
                    if fixedCount > 0 {
                        self.syncResult = (success: true, message: "Fixed \(fixedCount) audio notes for sync")
                    } else {
                        self.syncResult = (success: true, message: "No audio notes needed fixing")
                    }

                    #if DEBUG
                    print("⚙️ SettingsViewModel: Audio notes fix completed - Fixed \(fixedCount) notes")
                    #endif
                }
            } catch {
                await MainActor.run {
                    self.isFixingAudioNotes = false
                    self.syncResult = (success: false, message: "Failed to fix audio notes: \(error.localizedDescription)")

                    #if DEBUG
                    print("⚙️ SettingsViewModel: Audio notes fix failed - \(error)")
                    #endif
                }
            }

            // Auto-dismiss the result after 5 seconds
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.syncResult = nil
                }
            }
        }
    }

    /// Fix remote sync status in Supabase database
    func fixRemoteSyncStatus() {
        #if DEBUG
        print("⚙️ SettingsViewModel: Starting remote sync status fix")
        #endif

        isFixingRemoteSync = true

        Task {
            do {
                let result = try await SupabaseSyncService.shared.fixRemoteSyncStatus()

                await MainActor.run {
                    self.isFixingRemoteSync = false
                    let totalFixed = result.notesFix + result.foldersFix
                    if totalFixed > 0 {
                        self.syncResult = (success: true, message: "Fixed \(result.notesFix) notes and \(result.foldersFix) folders in Supabase")
                    } else {
                        self.syncResult = (success: true, message: "No remote records needed fixing")
                    }

                    #if DEBUG
                    print("⚙️ SettingsViewModel: Remote sync status fix completed - Notes: \(result.notesFix), Folders: \(result.foldersFix)")
                    #endif
                }
            } catch {
                await MainActor.run {
                    self.isFixingRemoteSync = false
                    self.syncResult = (success: false, message: "Failed to fix remote sync status: \(error.localizedDescription)")

                    #if DEBUG
                    print("⚙️ SettingsViewModel: Remote sync status fix failed - \(error)")
                    #endif
                }
            }

            // Auto-dismiss the result after 5 seconds
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.syncResult = nil
                }
            }
        }
    }

    func deleteFailedRecording(_ recording: FailedRecording) {
        #if DEBUG
        print("⚙️ SettingsViewModel: Deleting failed recording: \(recording.id)")
        #endif

        failedRecordings.removeAll { $0.id == recording.id }
    }

    // Storage data is pre-loaded to avoid loading indicator
    init() {
        // Pre-populate storage data
        self.storageUsage = StorageUsage(
            used: 1_200_000_000,  // 1.2 GB
            total: 5_000_000_000  // 5 GB
        )

        // Pre-populate failed recordings
        self.failedRecordings = [
            FailedRecording(date: Date().addingTimeInterval(-3600), duration: 45, errorMessage: "Network connection lost"),
            FailedRecording(date: Date().addingTimeInterval(-7200), duration: 120, errorMessage: "Insufficient storage")
        ]

        // Load last sync date from UserDefaults
        if let lastSyncTimeInterval = UserDefaults.standard.object(forKey: "lastSupabaseSyncDate") as? TimeInterval {
            self.lastSupabaseSync = Date(timeIntervalSince1970: lastSyncTimeInterval)

            #if DEBUG
            print("⚙️ SettingsViewModel: Loaded last sync date: \(self.lastSupabaseSync!)")
            #endif
        }

        // Set up observer for sync progress
        setupSyncProgressObserver()

        #if DEBUG
        print("⚙️ SettingsViewModel: Initialized with pre-populated data")
        #endif
    }

    /// Set up observer for sync progress
    private func setupSyncProgressObserver() {
        // Use Combine to observe changes to syncProgress
        SupabaseSyncService.shared.$syncProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                // Update UI based on progress
                if progress.overallProgress >= 1.0 {
                    // Sync completed
                    self?.isSyncing = false
                }
            }
            .store(in: &cancellables)
    }

    func calculateStorageUsage() {
        #if DEBUG
        print("⚙️ SettingsViewModel: Calculating storage usage")
        #endif

        // Only show loading if we don't already have storage data
        if storageUsage == nil {
            isLoading = true

            Task {
                do {
                    // Simulate API call with minimal delay
                    try await Task.sleep(nanoseconds: 100_000_000) // Reduced to 0.1 seconds

                    let usage = StorageUsage(
                        used: 1_200_000_000,  // 1.2 GB
                        total: 5_000_000_000  // 5 GB
                    )

                    await MainActor.run {
                        self.storageUsage = usage
                        self.isLoading = false
                    }

                    #if DEBUG
                    print("⚙️ SettingsViewModel: Storage calculation complete - Used: \(usage.formattedUsed)")
                    #endif
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Failed to calculate storage usage"
                        self.isLoading = false
                    }

                    #if DEBUG
                    print("⚙️ SettingsViewModel: Storage calculation failed - \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }

    func cleanup() async {
        #if DEBUG
        print("⚙️ SettingsViewModel: Performing cleanup")
        #endif
        // Cleanup logic here
    }

    func clearCache() async throws {
        #if DEBUG
        print("⚙️ SettingsViewModel: Clearing cache")
        #endif

        isLoading = true
        defer { isLoading = false }

        // Simulate cache clearing
        try await Task.sleep(nanoseconds: 2_000_000_000)

        #if DEBUG
        print("⚙️ SettingsViewModel: Cache cleared successfully")
        #endif
    }

    // Logout method removed
}

// MARK: - Settings View
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var noteTitle: String = ""
    @State private var refreshToggle = false
    @State private var showingSignOutAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var profileUpdateCounter = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            settingsContent
                .id(refreshToggle) // Force refresh when theme changes
        }
            .background(Theme.Colors.background.ignoresSafeArea())
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline) // Change to inline title
            .toolbar { settingsToolbar }
            // Logout alert removed
            .onAppear(perform: handleOnAppear)
            .overlay { loadingOverlay }
            .alert("Save Recording", isPresented: $viewModel.showingSaveDialog) {
                saveRecordingAlert
            }
            .onChange(of: themeManager.currentTheme) { newTheme in
                #if DEBUG
                print("⚙️ SettingsView: Theme changed to \(newTheme), triggering view update")
                #endif
                refreshToggle.toggle() // Force UI refresh
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ThemeChanged"))) { _ in
                // Force view to update with the new theme
                #if DEBUG
                print("⚙️ SettingsView: Received ThemeChanged notification")
                #endif
                refreshToggle.toggle() // Force UI refresh

                // Add haptic feedback
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            }
            .sheet(item: $viewModel.exportURL) { wrapper in
                ShareSheet(items: [wrapper.url])
            }
    }

    // MARK: - Content Views
    @ViewBuilder
    private var settingsContent: some View {
        LazyVStack(spacing: 16) { // Moderate spacing between sections
            ForEach(Theme.Settings.sections) { section in
                sectionView(for: section)
            }

            // Account actions at the end
            accountActionsSection
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.xs) // Small top padding
    }

    // MARK: - Alert Views
    @ViewBuilder
    private var saveRecordingAlert: some View {
        TextField("Note Title", text: $noteTitle)
        Button("Cancel", role: .cancel) {
            Task {
                await viewModel.cleanup()
            }
        }
        Button("Save") {
            saveRecording()
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Done") {
                #if DEBUG
                print("⚙️ SettingsView: Done button tapped")
                #endif
                dismiss()
            }
        }
    }

    // MARK: - Loading Overlay
    @ViewBuilder
    private var loadingOverlay: some View {
        if viewModel.isLoading {
            LoadingIndicator(message: "Saving changes...")
        }
    }

    // MARK: - Lifecycle Methods
    private func handleOnAppear() {
        #if DEBUG
        print("⚙️ SettingsView: View appeared")
        #endif
        // Storage usage calculation removed
        viewModel.fetchFailedRecordings()
    }

    // MARK: - Section Views
    @ViewBuilder
    func sectionContent(for section: SettingsSection) -> some View {
        switch section.id {
        case "profile":
            profileSection
        case "appearance":
            appearanceSection
        case "privacy":
            privacySection
        case "support":
            supportSection
        case "sync":
            syncSection
        default:
            EmptyView()
        }
    }

        // MARK: - Update Original sectionView
        @ViewBuilder
        func sectionView(for section: SettingsSection) -> some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // Section Header
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: section.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(section.color)
                        .frame(width: 24, height: 24)

                    Text(section.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.Colors.text)
                }
                .padding(.horizontal, Theme.Spacing.xs)

                // Section Content
                sectionContent(for: section)
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.md)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Settings.cornerRadius)
            }
        }

    private var appearanceSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Picker("Theme", selection: Binding(
                get: { themeManager.currentTheme },
                set: { newTheme in
                    #if DEBUG
                    print("⚙️ SettingsView: Theme picker changed to \(newTheme)")
                    #endif
                    withAnimation(.easeInOut(duration: 0.3)) {
                        themeManager.setTheme(newTheme)
                    }
                }
            )) {
                Text("System").tag(ThemeMode.system)
                Text("Light").tag(ThemeMode.light)
                Text("Dark").tag(ThemeMode.dark)
            }
            .pickerStyle(.segmented)

            Text("Choose how SwiftNote AI appears to you")
                .font(.system(size: 13))
                .foregroundColor(Theme.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var profileSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // User info display
            HStack(spacing: Theme.Spacing.md) {
                // Profile image or icon
                if let avatarUrl = authManager.userProfile?.avatarUrl, !avatarUrl.isEmpty {
                    AsyncImage(url: URL(string: avatarUrl)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.Colors.primary, lineWidth: 2))
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(Theme.Colors.primary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(authManager.userProfile?.fullName ?? "User")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.Colors.text)

                    Text(authManager.userProfile?.email ?? "")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.secondaryText)
                }

                Spacer()
            }
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                Task {
                    await authManager.signOut()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .onReceive(NotificationCenter.default.publisher(for: .userProfileUpdated)) { _ in
            profileUpdateCounter += 1
        }
        .id(profileUpdateCounter)
        .onAppear {
            Task {
                await authManager.refreshUserProfile()
            }
        }
    }

    private var privacySection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Biometric Authentication
            VStack(spacing: Theme.Spacing.xs) {
                Toggle(viewModel.biometricType == .faceID ? "Use Face ID" : "Use Touch ID", isOn: .init(
                    get: { viewModel.biometricEnabled },
                    set: { _ in
                        handleBiometricToggle()
                    }
                ))
                .font(.system(size: 15, weight: .medium))
                .onChange(of: viewModel.biometricEnabled) { newValue in
                    #if DEBUG
                    print("⚙️ SettingsView: Biometric setting changed to: \(newValue)")
                    #endif
                }
                .onAppear {
                    // Update the biometric type when the view appears
                    viewModel.biometricType = BiometricAuthManager.shared.biometricType()
                }

                Text("Secure your app with biometric authentication")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Legal Links
            LegalSection()
        }
    }

    private var supportSection: some View {
        VStack(spacing: 0) { // No spacing between rows
            Link(destination: URL(string: "https://example.com/faq")!) {
                SettingsRow(
                    icon: "questionmark.circle.fill",
                    title: "FAQ",
                    color: Theme.Colors.success
                )
            }

            Link(destination: URL(string: "https://example.com/support")!) {
                SettingsRow(
                    icon: "envelope.fill",
                    title: "Contact Support",
                    color: Theme.Colors.primary
                )
            }

            SettingsRow(
                icon: "info.circle.fill",
                title: "App Version",
                color: Theme.Colors.primary,
                showDivider: false,
                rightContent: {
                    AnyView(
                        Text(Bundle.main.appVersion)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                    )
                }
            )
        }
    }

    private var syncSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Sync button
            Button(action: {
                #if DEBUG
                print("⚙️ SettingsView: Sync button tapped")
                #endif

                // Check if sync is already locked before attempting
                if SupabaseSyncService.shared.isSyncLocked() {
                    #if DEBUG
                    print("⚙️ SettingsView: Sync button tapped but sync is locked")
                    #endif
                    viewModel.syncResult = (success: false, message: "Another sync is already in progress. Please wait for it to complete.")

                    // Auto-dismiss the result after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        viewModel.syncResult = nil
                    }
                } else {
                    viewModel.syncToSupabase(context: viewContext)
                }
            }) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(viewModel.twoWaySyncEnabled ? "Two-Way Sync" : "Upload to Cloud")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.Colors.text)
                    Spacer()
                    if viewModel.isSyncing || SupabaseSyncService.shared.isSyncLocked() {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Image(systemName: viewModel.twoWaySyncEnabled ? "arrow.triangle.2.circlepath" : "arrow.up.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.Colors.primary)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .disabled(viewModel.isSyncing || SupabaseSyncService.shared.isSyncLocked())

            // Sync description
            VStack(spacing: Theme.Spacing.xs) {
                Text(viewModel.twoWaySyncEnabled ? "Syncs folders and notes bidirectionally with conflict resolution" : "Uploads local folders and notes to the cloud")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Two-way sync toggle
                Toggle("Enable two-way sync", isOn: $viewModel.twoWaySyncEnabled)
                    .font(.system(size: 15, weight: .medium))
                    .disabled(viewModel.isSyncing || SupabaseSyncService.shared.isSyncLocked())

                // Two-way sync description
                Text("Downloads remote changes and resolves conflicts using 'Last Write Wins' strategy")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Include binary data toggle
            VStack(spacing: Theme.Spacing.xs) {
                Toggle("Include binary data (notes content)", isOn: $viewModel.syncBinaryDataEnabled)
                    .font(.system(size: 15, weight: .medium))
                    .disabled(viewModel.isSyncing || SupabaseSyncService.shared.isSyncLocked())

                // Binary data description
                Text("Syncs full note content including text, formatting, and attachments")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Last sync time
            if let lastSync = viewModel.lastSupabaseSync {
                HStack {
                    Text("Last synced:")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                    Spacer()
                    Text(lastSync, style: .relative)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }

            // Sync progress
            if viewModel.isSyncing {
                VStack(spacing: 4) {
                    // Progress bar
                    ProgressView(value: SupabaseSyncService.shared.syncProgress.overallProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 4)

                    // Status text
                    Text(SupabaseSyncService.shared.syncProgress.currentStatus)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Detailed progress for two-way sync
                    if viewModel.twoWaySyncEnabled {
                        let progress = SupabaseSyncService.shared.syncProgress
                        HStack {
                            Text("↑ \(progress.syncedFolders)/\(progress.totalFolders) folders, \(progress.syncedNotes)/\(progress.totalNotes) notes")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                            Spacer()
                            if progress.isDownloadPhase {
                                Text("↓ \(progress.downloadedFolders)/\(progress.totalFolders) folders, \(progress.downloadedNotes)/\(progress.totalNotes) notes")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                        }

                        // Conflict resolution info
                        if progress.resolvedConflicts > 0 {
                            Text("⚡ Resolved \(progress.resolvedConflicts) conflicts")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            // Sync result message
            if let result = viewModel.syncResult {
                HStack {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? Theme.Colors.success : Theme.Colors.error)
                    Text(result.message)
                        .font(Theme.Typography.caption)
                        .foregroundColor(result.success ? Theme.Colors.success : Theme.Colors.error)
                }
                .padding(.top, 4)
            }

            // Fix audio notes button
            Button(action: {
                #if DEBUG
                print("⚙️ SettingsView: Fix audio notes button tapped")
                #endif
                viewModel.fixAudioNotes(context: viewContext)
            }) {
                HStack {
                    Text("Fix Audio Notes Sync")
                        .foregroundColor(Theme.Colors.text)
                    Spacer()
                    if viewModel.isFixingAudioNotes {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundColor(Theme.Colors.warning)
                    }
                }
            }
            .disabled(viewModel.isSyncing || viewModel.isFixingAudioNotes || SupabaseSyncService.shared.isSyncLocked())

            // Fix audio notes description
            Text("Marks existing audio notes for sync if they were created before the sync fix")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Fix remote sync status button
            Button(action: {
                #if DEBUG
                print("⚙️ SettingsView: Fix remote sync status button tapped")
                #endif
                viewModel.fixRemoteSyncStatus()
            }) {
                HStack {
                    Text("Fix Remote Sync Status")
                        .foregroundColor(Theme.Colors.text)
                    Spacer()
                    if viewModel.isFixingRemoteSync {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Image(systemName: "cloud.fill")
                            .foregroundColor(Theme.Colors.warning)
                    }
                }
            }
            .disabled(viewModel.isSyncing || viewModel.isFixingRemoteSync || viewModel.isFixingAudioNotes || SupabaseSyncService.shared.isSyncLocked())

            // Fix remote sync status description
            Text("Fixes notes/folders in Supabase that incorrectly show 'pending' status")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var accountActionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Section Header
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.Colors.error)
                    .frame(width: 24, height: 24)

                Text("Account")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.Colors.text)
            }
            .padding(.horizontal, Theme.Spacing.xs)

            // Section Content
            VStack(spacing: 0) {
                // Sign out button
                Button(action: {
                    showingSignOutAlert = true
                }) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.Colors.error)

                        Text("Sign Out")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.Colors.error)

                        Spacer()
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.md)
                }

                Divider()
                    .padding(.horizontal, Theme.Spacing.md)

                // Delete account button
                Button(action: {
                    showingDeleteAccountAlert = true
                }) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.Colors.error)

                        Text("Delete Account")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.Colors.error)

                        Spacer()
                    }
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.md)
                }
            }
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Settings.cornerRadius)
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                Task {
                    await authManager.signOut()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete Account", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    // Add delete account functionality here
                    toastManager.show("Account deletion is not yet implemented", type: .error)
                }
            }
        } message: {
            Text("This action cannot be undone. All your data will be permanently deleted.")
        }
    }

    // MARK: - Helper Methods
    private func handleBiometricToggle() {
        Task {
            do {
                try await viewModel.toggleBiometric()
                toastManager.show(
                    viewModel.biometricEnabled ?
                    "Biometric authentication enabled" :
                    "Biometric authentication disabled",
                    type: .success
                )
            } catch {
                #if DEBUG
                print("⚙️ SettingsView: Biometric toggle failed - \(error)")
                #endif
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }

    private func saveRecording() {
        #if DEBUG
        print("⚙️ SettingsView: Attempting to save recording with title: \(noteTitle)")
        #endif

        guard !noteTitle.isEmpty else {
            #if DEBUG
            print("⚙️ SettingsView: Error - Empty note title")
            #endif
            toastManager.show("Please enter a title", type: .error)
            return
        }

        Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000) // Simulating save operation
                toastManager.show("Recording saved successfully", type: .success)
                viewModel.showingSaveDialog = false

                #if DEBUG
                print("⚙️ SettingsView: Recording saved successfully with title: \(noteTitle)")
                #endif

            } catch {
                #if DEBUG
                print("⚙️ SettingsView: Error saving recording - \(error)")
                #endif
                toastManager.show("Failed to save recording", type: .error)
            }
        }
    }
}

// MARK: - Web Link Handler
struct WebViewLink: View {
    let url: URL
    let title: String
    @State private var isShowingSafari = false
    @Environment(\.toastManager) private var toastManager

    var body: some View {
        Button(action: {
            #if DEBUG
            print("🌐 WebViewLink: Opening URL: \(url)")
            #endif
            isShowingSafari = true
        }) {
            HStack {
                Text(title)
                    .foregroundColor(Theme.Colors.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .sheet(isPresented: $isShowingSafari) {
            SafariView(url: url)
                .ignoresSafeArea()
                .onDisappear {
                    #if DEBUG
                    print("🌐 WebViewLink: Safari view disappeared")
                    #endif
                }
        }
    }
}

// MARK: - Safari View
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        #if DEBUG
        print("🌐 SafariView: Creating Safari controller for URL: \(url)")
        #endif
        return SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

// MARK: - Legal Section
struct LegalSection: View {
    private let privacyPolicyURL = URL(string: "https://kybdigital.com/swift-ai-privacy-policy")!
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        VStack(spacing: 0) { // No spacing between rows
            // Privacy Policy Row
            SettingsRow(
                icon: "doc.text.fill",
                title: "Privacy Policy",
                color: Theme.Colors.primary,
                rightContent: {
                    AnyView(
                        WebViewLink(url: privacyPolicyURL, title: "")
                    )
                }
            )

            // Terms of Use Row
            SettingsRow(
                icon: "doc.text.fill",
                title: "Terms of Use",
                color: Theme.Colors.primary,
                showDivider: false,
                rightContent: {
                    AnyView(
                        WebViewLink(url: termsOfUseURL, title: "")
                    )
                }
            )
        }
    }
}

// MARK: - Bundle Extension
extension Bundle {
    var appVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "\(version)"
    }
}

// MARK: - Supporting Views
struct SettingsRow: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let title: String
    let color: Color
    var showDivider: Bool = true

    var rightContent: (() -> AnyView)? = nil

    init(
        icon: String,
        title: String,
        color: Color,
        showDivider: Bool = true,
        rightContent: (() -> AnyView)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.color = color
        self.showDivider = showDivider
        self.rightContent = rightContent

        #if DEBUG
        print("⚙️ SettingsRow: Initializing row with title: \(title)")
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            // Row content
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 24, height: 24)

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.Colors.text)

                Spacer()

                if let rightContent = rightContent {
                    rightContent()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            .padding(.vertical, Theme.Spacing.sm)

            // Divider with no extra spacing
            if showDivider {
                Divider()
                    .background(Theme.Colors.tertiaryBackground)
                    .padding(.leading, 40)
            }
        }
    }
}
