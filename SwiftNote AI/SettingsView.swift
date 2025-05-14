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

        #if DEBUG
        print("⚙️ SettingsViewModel: Initialized with pre-populated data")
        #endif
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var noteTitle: String = ""
    @State private var refreshToggle = false

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
        case "appearance":
            appearanceSection
        case "privacy":
            privacySection
        case "support":
            supportSection
        default:
            EmptyView()
        }
    }

        // MARK: - Update Original sectionView
        @ViewBuilder
        func sectionView(for section: SettingsSection) -> some View {
            VStack(alignment: .leading, spacing: 8) { // Reduced spacing between header and content
                // Section Header
                HStack {
                    Image(systemName: section.icon)
                        .font(.system(size: Theme.Settings.iconSize))
                        .foregroundColor(section.color)

                    Text(section.title)
                        .font(.system(size: 18, weight: .semibold)) // Custom smaller size
                }

                // Section Content - reduced padding for more compact look
                sectionContent(for: section)
                    .padding(.vertical, 8) // Reduced vertical padding
                    .padding(.horizontal, 12) // Reduced horizontal padding
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Settings.cornerRadius)
            }
        }

    private var appearanceSection: some View {
        VStack(spacing: 6) { // Minimal spacing for appearance controls
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
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }
    }

    private var privacySection: some View {
        VStack(spacing: 8) { // Consistent spacing
            // Biometric Authentication
            Toggle(viewModel.biometricType == .faceID ? "Use Face ID" : "Use Touch ID", isOn: .init(
                get: { viewModel.biometricEnabled },
                set: { _ in
                    handleBiometricToggle()
                }
            ))
            .onChange(of: viewModel.biometricEnabled) { newValue in
                #if DEBUG
                print("⚙️ SettingsView: Biometric setting changed to: \(newValue)")
                #endif
            }
            .onAppear {
                // Update the biometric type when the view appears
                viewModel.biometricType = BiometricAuthManager.shared.biometricType()
            }

            // Privacy Settings section removed

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
    private let termsOfUseURL = URL(string: "https://kybdigital.com/terms-of-use")!

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
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color.opacity(colorScheme == .dark ? 0.9 : 1.0))
                    .frame(width: 24)

                Text(title)
                    .foregroundColor(Theme.Colors.text)

                Spacer()

                if let rightContent = rightContent {
                    rightContent()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            .padding(.vertical, 8) // Fixed vertical padding

            // Divider with no extra spacing
            if showDivider {
                Divider()
                    .background(Theme.Colors.tertiaryBackground)
                    .padding(.leading, 32)
            }
        }
    }
}
