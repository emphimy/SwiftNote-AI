import SwiftUI
import CoreData


// MARK: - Privacy Models
struct PrivacySettings: Equatable {
    var dataCollection: Bool
    var analytics: Bool
    var marketingEmails: Bool
    var downloadRequested: Date?
    
    static let mock = PrivacySettings(
        dataCollection: true,
        analytics: true,
        marketingEmails: false
    )
}

// MARK: - Privacy Settings View Model
@MainActor
final class PrivacySettingsViewModel: ObservableObject {
    @Published private(set) var settings: PrivacySettings
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var showingDataExport = false
    @Published var showingDeleteConfirmation = false
    
    private let viewContext: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        self.settings = .mock
        
        #if DEBUG
        print("🔒 PrivacyVM: Initializing with context")
        #endif
    }
    
    func loadSettings() async {
        loadingState = .loading(message: "Loading privacy settings...")
        
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                loadingState = .success(message: "Settings loaded")
            }
            
            #if DEBUG
            print("🔒 PrivacyVM: Settings loaded successfully")
            #endif
        } catch {
            await MainActor.run {
                loadingState = .error(message: error.localizedDescription)
            }
            
            #if DEBUG
            print("🔒 PrivacyVM: Error loading settings - \(error)")
            #endif
        }
    }
    
    func updateSettings(_ update: (inout PrivacySettings) -> Void) async throws {
        loadingState = .loading(message: "Saving changes...")
        
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                update(&settings)
                loadingState = .success(message: "Changes saved")
            }
            
            #if DEBUG
            print("🔒 PrivacyVM: Settings updated successfully")
            #endif
        } catch {
            await MainActor.run {
                loadingState = .error(message: error.localizedDescription)
            }
            throw error
        }
    }
    
    func requestDataExport() async throws {
        loadingState = .loading(message: "Requesting data export...")
        
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                settings.downloadRequested = Date()
                loadingState = .success(message: "Export requested")
            }
            
            #if DEBUG
            print("🔒 PrivacyVM: Data export requested successfully")
            #endif
        } catch {
            await MainActor.run {
                loadingState = .error(message: error.localizedDescription)
            }
            throw error
        }
    }
    
    func deleteAccount() async throws {
        loadingState = .loading(message: "Deleting account...")
        
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            #if DEBUG
            print("🔒 PrivacyVM: Account deletion initiated")
            #endif
            
            // Actually delete the account here
            throw NSError(domain: "Privacy", code: -1, userInfo: [NSLocalizedDescriptionKey: "Account deletion not implemented"])
        } catch {
            await MainActor.run {
                loadingState = .error(message: error.localizedDescription)
            }
            throw error
        }
    }
}

// MARK: - Privacy Settings View
struct PrivacySettingsView: View {
    @StateObject private var viewModel: PrivacySettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    
    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: PrivacySettingsViewModel(context: context))
        
        #if DEBUG
        print("🔒 PrivacySettingsView: Initializing with context")
        #endif
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                dataCollectionSection
                exportSection
                dangerZone
            }
            .padding()
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - Data Collection Section
    private var dataCollectionSection: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Data Collection")
                
                VStack(spacing: Theme.Spacing.sm) {
                    Toggle("Usage Analytics", isOn: binding(for: \.analytics))
                        .onChange(of: viewModel.settings.analytics) { newValue in
                            #if DEBUG
                            print("🔒 PrivacyView: Analytics toggled to \(newValue)")
                            #endif
                        }
                    
                    Toggle("App Improvement Data", isOn: binding(for: \.dataCollection))
                        .onChange(of: viewModel.settings.dataCollection) { newValue in
                            #if DEBUG
                            print("🔒 PrivacyView: Data collection toggled to \(newValue)")
                            #endif
                        }
                    
                    Toggle("Marketing Emails", isOn: binding(for: \.marketingEmails))
                        .onChange(of: viewModel.settings.marketingEmails) { newValue in
                            #if DEBUG
                            print("🔒 PrivacyView: Marketing emails toggled to \(newValue)")
                            #endif
                        }
                }
                .padding()
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
            }
        }
    
    // MARK: - Export Section
    private var exportSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Data Export")
            
            VStack(spacing: Theme.Spacing.sm) {
                Button(action: handleDataExport) {
                    Text("Request Data Export")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                
                if let requestDate = viewModel.settings.downloadRequested {
                    Text("Last requested: \(requestDate.formatted())")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
    }
    
    // MARK: - Danger Zone
    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Danger Zone")
            
            Button(action: {
                #if DEBUG
                print("🔒 PrivacySettingsView: Delete account button tapped")
                #endif
                viewModel.showingDeleteConfirmation = true
            }) {
                Text("Delete Account")
                    .foregroundColor(Theme.Colors.error)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
    }
    
    // MARK: - Helper Methods
    private func binding<T>(for keyPath: WritableKeyPath<PrivacySettings, T>) -> Binding<T> {
        Binding(
            get: { viewModel.settings[keyPath: keyPath] },
            set: { newValue in
                Task {
                    do {
                        try await viewModel.updateSettings { settings in
                            settings[keyPath: keyPath] = newValue
                        }
                    } catch {
                        #if DEBUG
                        print("🔒 PrivacySettingsView: Error updating setting - \(error)")
                        #endif
                        toastManager.show(error.localizedDescription, type: .error)
                    }
                }
            }
        )
    }
    
    private func handleDataExport() {
        Task {
            do {
                try await viewModel.requestDataExport()
                toastManager.show("Data export requested. You'll receive an email when it's ready.", type: .success)
            } catch {
                #if DEBUG
                print("🔒 PrivacySettingsView: Error requesting data export - \(error)")
                #endif
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
    
    private func handleAccountDeletion() {
        Task {
            do {
                try await viewModel.deleteAccount()
                dismiss()
            } catch {
                #if DEBUG
                print("🔒 PrivacySettingsView: Error deleting account - \(error)")
                #endif
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
}

// MARK: - Preview Provider
#if DEBUG
struct PrivacySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PrivacySettingsView(context: PersistenceController.preview.container.viewContext)
        }
    }
}
#endif
