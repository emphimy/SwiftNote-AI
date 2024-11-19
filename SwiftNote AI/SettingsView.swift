import SwiftUI
import CoreData
import Combine

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
    @AppStorage("isDarkMode") var isDarkMode = false
    @AppStorage("useSystemTheme") var useSystemTheme = true
    @AppStorage("notificationsEnabled") var notificationsEnabled = true
    @AppStorage("autoBackupEnabled") var autoBackupEnabled = true
    @AppStorage("biometricLockEnabled") var biometricLockEnabled = false
    
    @Published var storageUsage: StorageUsage?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingPrivacyPolicy = false
    @Published var showingDeleteAccountAlert = false
    @Published var showingLogoutAlert = false
    @Published var failedRecordings: [FailedRecording] = []
    
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
    @Environment(\.toastManager) private var toastManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.lg) {
                ForEach(Theme.Settings.sections) { section in
                    sectionView(for: section)
                }
                
                versionFooter
            }
            .padding()
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    #if DEBUG
                    print("⚙️ SettingsView: Done button tapped")
                    #endif
                    dismiss()
                }
            }
        }
        .onAppear {
            #if DEBUG
            print("⚙️ SettingsView: View appeared")
            #endif
            viewModel.calculateStorageUsage()
            viewModel.fetchFailedRecordings()

        }
        .alert("Sign Out", isPresented: $viewModel.showingLogoutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                handleLogout()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }
    
    // MARK: - Section Views
    @ViewBuilder
    private func sectionView(for section: SettingsSection) -> some View {
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
            Group {
                switch section.id {
                case "account": accountSection
                case "appearance": appearanceSection
                case "notifications": notificationsSection
                case "storage": storageSection
                case "privacy": privacySection
                case "support": supportSection
                default: EmptyView()
                }
            }
            .padding(Theme.Settings.cardPadding)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Settings.cornerRadius)
        }
    }
    
    private var accountSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            NavigationLink {
                Text("Profile Settings")
            } label: {
                SettingsRow(
                    icon: "person.fill",
                    title: "Edit Profile",
                    color: Theme.Colors.primary
                )
            }
            
            NavigationLink {
                Text("Security Settings")
            } label: {
                SettingsRow(
                    icon: "key.fill",
                    title: "Security",
                    color: Theme.Colors.warning
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
            Toggle("Use System Theme", isOn: $viewModel.useSystemTheme)
                .onChange(of: viewModel.useSystemTheme) { newValue in
                    #if DEBUG
                    print("⚙️ SettingsView: System theme toggled: \(newValue)")
                    #endif
                }
            
            if !viewModel.useSystemTheme {
                Toggle("Dark Mode", isOn: $viewModel.isDarkMode)
                    .onChange(of: viewModel.isDarkMode) { newValue in
                        #if DEBUG
                        print("⚙️ SettingsView: Dark mode toggled: \(newValue)")
                        #endif
                    }
            }
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
                Text("Notification Preferences")
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
            Toggle("Biometric Lock", isOn: $viewModel.biometricLockEnabled)
                .onChange(of: viewModel.biometricLockEnabled) { newValue in
                    #if DEBUG
                    print("⚙️ SettingsView: Biometric lock toggled: \(newValue)")
                    #endif
                }
            
            NavigationLink {
                Text("Privacy Settings")
            } label: {
                SettingsRow(
                    icon: "hand.raised.fill",
                    title: "Privacy Settings",
                    color: Theme.Colors.error
                )
            }
            
            Button {
                viewModel.showingPrivacyPolicy = true
            } label: {
                SettingsRow(
                    icon: "doc.text.fill",
                    title: "Privacy Policy",
                    color: Theme.Colors.primary,
                    showDivider: false
                )
            }
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
    
    private var versionFooter: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            
            Text("© 2024 SwiftNote AI")
                .font(Theme.Typography.small)
                .foregroundColor(Theme.Colors.tertiaryText)
        }
        .padding(.top, Theme.Spacing.xl)
    }
    
    // MARK: - Helper Methods
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
}

// MARK: - Supporting Views
struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color
    var showDivider: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 24)
                
                Text(title)
                    .foregroundColor(Theme.Colors.text)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .padding(.vertical, Theme.Spacing.xs)
            
            if showDivider {
                Divider()
                    .padding(.leading, 32)
            }
        }
    }
}

struct StorageProgressBar: View {
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
    }
}

// MARK: - Preview Provider
#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingsView()
        }
        .previewDisplayName("Settings View")
        
        SettingsRow(
            icon: "person.fill",
            title: "Edit Profile",
            color: Theme.Colors.primary
        )
        .padding()
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Settings Row")
        
        StorageProgressBar(
            used: 0.7,
            usedText: "3.5 GB",
            totalText: "5 GB"
        )
        .padding()
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Storage Progress Bar")
    }
}
#endif
