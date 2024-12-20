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
    @AppStorage("notificationsEnabled") var notificationsEnabled = true
    @AppStorage("autoBackupEnabled") var autoBackupEnabled = true
    @AppStorage("biometricLockEnabled") var biometricLockEnabled = false
    @AppStorage("biometricEnabled") var biometricEnabled = false
    
    @Published var showingSaveDialog = false
    @Published var storageUsage: StorageUsage?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingPrivacyPolicy = false
    @Published var showingDeleteAccountAlert = false
    @Published var showingLogoutAlert = false
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
        
        let context = LAContext()
        var error: NSError?
        
        // First check if biometric auth is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            #if DEBUG
            print("⚙️ SettingsViewModel: Biometric auth not available - \(String(describing: error))")
            #endif
            throw error ?? NSError(domain: "Settings", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Biometric authentication not available"])
        }
        
        // Request biometric authentication
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Enable biometric authentication for SwiftNote AI"
            )
            
            #if DEBUG
            print("⚙️ SettingsViewModel: Biometric auth toggle successful")
            #endif
            
            biometricEnabled.toggle()
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
        
        // Simulate fetching failed recordings
        failedRecordings = [
            FailedRecording(date: Date().addingTimeInterval(-3600), duration: 45, errorMessage: "Network connection lost"),
            FailedRecording(date: Date().addingTimeInterval(-7200), duration: 120, errorMessage: "Insufficient storage")
        ]
    }

    func deleteFailedRecording(_ recording: FailedRecording) {
        #if DEBUG
        print("⚙️ SettingsViewModel: Deleting failed recording: \(recording.id)")
        #endif
        
        failedRecordings.removeAll { $0.id == recording.id }
    }

    func calculateStorageUsage() {
        #if DEBUG
        print("⚙️ SettingsViewModel: Calculating storage usage")
        #endif
        
        isLoading = true
        
        Task {
            do {
                // Simulate API call
                try await Task.sleep(nanoseconds: 1_000_000_000)
                
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
    
    func logout() async throws {
        #if DEBUG
        print("⚙️ SettingsViewModel: Processing logout")
        #endif
        
        isLoading = true
        defer { isLoading = false }
        
        // Simulate logout process
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        #if DEBUG
        print("⚙️ SettingsViewModel: Logout successful")
        #endif
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var noteTitle: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                settingsContent
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { settingsToolbar }
            .alert("Sign Out", isPresented: $viewModel.showingLogoutAlert) {
                logoutAlert
            }
            .onAppear(perform: handleOnAppear)
            .overlay { loadingOverlay }
            .alert("Save Recording", isPresented: $viewModel.showingSaveDialog) {
                saveRecordingAlert
            }
            .onChange(of: themeManager.currentTheme) { newTheme in
                #if DEBUG
                print("⚙️ SettingsView: Theme changed to \(newTheme), triggering view update")
                #endif
            }
            .sheet(item: $viewModel.exportURL) { wrapper in
                ShareSheet(items: [wrapper.url])
            }
        }
    }
    
    // MARK: - Content Views
    @ViewBuilder
    private var settingsContent: some View {
        VStack {
            LazyVStack(spacing: Theme.Spacing.lg) {
                ForEach(Theme.Settings.sections) { section in
                    sectionView(for: section)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Alert Views
    @ViewBuilder
    private var logoutAlert: some View {
        Button("Cancel", role: .cancel) {}
        Button("Sign Out", role: .destructive) {
            handleLogout()
        }
    }
    
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
        viewModel.calculateStorageUsage()
        viewModel.fetchFailedRecordings()
    }
    
    // MARK: - Section Views
    @ViewBuilder
    func sectionContent(for section: SettingsSection) -> some View {
        switch section.id {
        case "account":
            accountSection
        case "appearance":
            appearanceSection
        case "notifications":
            notificationsSection
        case "storage":
            storageSection
        case "privacy":
            privacySection
        case "support":
            supportSection
        case "about":
            AboutSection()
        default:
            EmptyView()
        }
    }

        // MARK: - Update Original sectionView
        @ViewBuilder
        func sectionView(for section: SettingsSection) -> some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                // Section Header
                HStack {
                    Image(systemName: section.icon)
                        .font(.system(size: Theme.Settings.iconSize))
                        .foregroundColor(section.color)
                    
                    Text(section.title)
                        .font(Theme.Typography.h3)
                }
                .padding(.bottom, Theme.Spacing.xs)
                
                // Section Content
                sectionContent(for: section)
                    .padding(Theme.Settings.cardPadding)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Settings.cornerRadius)
            }
        }
    
    private var accountSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            NavigationLink {
                ProfileView(context: viewContext)
            } label: {
                SettingsRow(
                    icon: "person.fill",
                    title: "Edit Profile",
                    color: Theme.Colors.primary
                )
            }
            
            Button {
                #if DEBUG
                print("⚙️ SettingsView: Logout initiated")
                #endif
                viewModel.showingLogoutAlert = true
            } label: {
                SettingsRow(
                    icon: "arrow.right.square.fill",
                    title: "Sign Out",
                    color: Theme.Colors.error,
                    showDivider: false
                )
            }
        }
    }
    
    private var appearanceSection: some View {
        VStack(spacing: Theme.Spacing.md) {
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
                Text("Light").tag(ThemeMode.light)
                Text("Dark").tag(ThemeMode.dark)
            }
            .pickerStyle(.segmented)
            
            Text("Choose how SwiftNote AI appears to you")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }
    }
    
    private var notificationsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Toggle("Push Notifications", isOn: $viewModel.notificationsEnabled)
                .onChange(of: viewModel.notificationsEnabled) { newValue in
                    #if DEBUG
                    print("⚙️ SettingsView: Notifications toggled: \(newValue)")
                    #endif
                }
            
            NavigationLink {
                NotificationView(context: viewContext)
            } label: {
                SettingsRow(
                    icon: "bell.badge.fill",
                    title: "Notification Preferences",
                    color: Theme.Colors.warning,
                    showDivider: false
                )
            }
        }
    }
    
    private var storageSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let usage = viewModel.storageUsage {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Storage Used")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                    
                    StorageProgressBar(
                        used: usage.usedPercentage,
                        usedText: usage.formattedUsed,
                        totalText: usage.formattedTotal
                    )
                }
            } else if viewModel.isLoading {
                ProgressView()
            }
            
            Toggle("Auto Backup", isOn: $viewModel.autoBackupEnabled)
                .onChange(of: viewModel.autoBackupEnabled) { newValue in
                    #if DEBUG
                    print("⚙️ SettingsView: Auto backup toggled: \(newValue)")
                    #endif
                }
            
            if !viewModel.failedRecordings.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Failed Recordings")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                    
                    ForEach(viewModel.failedRecordings) { recording in
                        HStack {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(recording.formattedDate)
                                    .font(Theme.Typography.caption)
                                Text(recording.errorMessage)
                                    .font(Theme.Typography.small)
                                    .foregroundColor(Theme.Colors.error)
                            }
                            
                            Spacer()
                            
                            Text(recording.formattedDuration)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                            
                            Button {
                                #if DEBUG
                                print("⚙️ SettingsView: Delete recording button tapped for ID: \(recording.id)")
                                #endif
                                withAnimation {
                                    viewModel.deleteFailedRecording(recording)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(Theme.Colors.error)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.xxs)
                        
                        if recording.id != viewModel.failedRecordings.last?.id {
                            Divider()
                        }
                    }
                }
            }
            
            Button {
                Task {
                    do {
                        try await viewModel.clearCache()
                        toastManager.show("Cache cleared successfully", type: .success)
                    } catch {
                        #if DEBUG
                        print("⚙️ SettingsView: Cache clear failed - \(error)")
                        #endif
                        toastManager.show("Failed to clear cache", type: .error)
                    }
                }
            } label: {
                SettingsRow(
                    icon: "trash.fill",
                    title: "Clear Cache",
                    color: Theme.Colors.error,
                    showDivider: false
                )
            }
        }
    }
    
    private var privacySection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Biometric Authentication
            Toggle("Use Face ID / Touch ID", isOn: .init(
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
            
            // Data Collection & Privacy Settings
            NavigationLink {
                PrivacySettingsView(context: viewContext)
            } label: {
                SettingsRow(
                    icon: "hand.raised.fill",
                    title: "Privacy Settings",
                    color: Theme.Colors.error
                )
            }
            
            // Legal Links
            LegalSection()
        }
    }
    
    private var supportSection: some View {
        VStack(spacing: Theme.Spacing.md) {
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
                    color: Theme.Colors.primary,
                    showDivider: false
                )
            }
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
    
    private func handleLogout() {
        Task {
            do {
                try await viewModel.logout()
                dismiss()
                toastManager.show("Successfully signed out", type: .success)
            } catch {
                #if DEBUG
                print("⚙️ SettingsView: Logout failed - \(error)")
                #endif
                toastManager.show("Failed to sign out", type: .error)
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
    private let privacyPolicyURL = URL(string: "https://example.com/privacy")!
    private let termsOfUseURL = URL(string: "https://example.com/terms")!
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Privacy Policy Row
            SettingsRow(
                icon: "doc.text.fill",
                title: "Privacy Policy",
                color: Theme.Colors.primary,
                rightContent: {
                    AnyView(
                        Link(destination: privacyPolicyURL) {
                            HStack {
                                Text("View")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                        }
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
                        Link(destination: termsOfUseURL) {
                            HStack {
                                Text("View")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                        }
                    )
                }
            )
        }
    }
}

// MARK: - About Section
struct AboutSection: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            SettingsRow(
                icon: "info.circle.fill",
                title: "App Version",
                color: Theme.Colors.primary,
                rightContent: {
                    AnyView(
                        Text(Bundle.main.appVersion)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                    )
                }
            )
            
            SettingsRow(
                icon: "doc.text.fill",
                title: "Acknowledgments",
                color: Theme.Colors.primary
            )
        }
    }
}

// MARK: - Bundle Extension
extension Bundle {
    var appVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
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
            .padding(.vertical, Theme.Spacing.xs)
            
            if showDivider {
                Divider()
                    .background(Theme.Colors.tertiaryBackground)
                    .padding(.leading, 32)
            }
        }
        .onChange(of: themeManager.currentTheme) { newTheme in
            #if DEBUG
            print("⚙️ SettingsRow: Theme changed to \(newTheme) for row: \(title)")
            #endif
        }
    }
}

struct StorageProgressBar: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    let used: Double
    let usedText: String
    let totalText: String
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.Colors.tertiaryBackground)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.Colors.primary,
                                    Theme.Colors.primary.opacity(0.8)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * used)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text(usedText)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.primary)
                
                Spacer()
                
                Text(totalText)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .onChange(of: themeManager.currentTheme) { newTheme in
            #if DEBUG
            print("⚙️ StorageProgressBar: Theme changed to \(newTheme)")
            #endif
        }
    }
}

// MARK: - Preview Provider
#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingsView()
                .environmentObject(ThemeManager())
                .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        }
        .previewDisplayName("Settings View")
        
        // Individual component previews
        Group {
            SettingsRow(
                icon: "person.fill",
                title: "Edit Profile",
                color: Theme.Colors.primary
            )
            .environmentObject(ThemeManager())
            .padding()
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Settings Row")
            
            StorageProgressBar(
                used: 0.7,
                usedText: "3.5 GB",
                totalText: "5 GB"
            )
            .environmentObject(ThemeManager())
            .padding()
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Storage Progress Bar")
        }
    }
}
#endif
