import SwiftUI
import CoreData
import UserNotifications

// MARK: - Notification Models
struct NotificationPreferences: Equatable {
    var pushEnabled: Bool
    var emailEnabled: Bool
    var categories: [NotificationCategory]
    var quietHours: QuietHours?
    var history: [NotificationEvent]
    
    static let mock = NotificationPreferences(
        pushEnabled: true,
        emailEnabled: true,
        categories: [
            .init(id: "study_reminders", name: "Study Reminders", isEnabled: true),
            .init(id: "new_features", name: "New Features", isEnabled: true),
            .init(id: "account", name: "Account Updates", isEnabled: true),
            .init(id: "security", name: "Security Alerts", isEnabled: true)
        ],
        quietHours: QuietHours(start: Date.now, end: Date.now.addingTimeInterval(28800)),
        history: [
            .init(title: "New Feature Available", body: "Try our new flashcard system!", date: Date(), category: "new_features"),
            .init(title: "Security Alert", body: "New device sign-in detected", date: Date().addingTimeInterval(-3600), category: "security")
        ]
    )
}

struct NotificationCategory: Identifiable, Equatable {
    let id: String
    let name: String
    var isEnabled: Bool
}

struct QuietHours: Equatable {
    var start: Date
    var end: Date
    
    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

struct NotificationEvent: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let body: String
    let date: Date
    let category: String
}

// MARK: - Notification View Model
@MainActor
final class NotificationViewModel: ObservableObject {
    @Published private(set) var preferences: NotificationPreferences
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var showingQuietHoursSetup = false
    
    private let viewContext: NSManagedObjectContext
    private let notificationCenter = UNUserNotificationCenter.current()
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        self.preferences = .mock
        
        #if DEBUG
        print("🔔 NotificationVM: Initializing with context")
        #endif
    }
    
    func loadPreferences() async {
        loadingState = .loading(message: "Loading preferences...")
        
        do {
            // Check notification authorization status
            let settings = await notificationCenter.notificationSettings()
            let pushEnabled = settings.authorizationStatus == .authorized
            
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                preferences.pushEnabled = pushEnabled
                loadingState = .success(message: "Preferences loaded")
            }
            
            #if DEBUG
            print("🔔 NotificationVM: Preferences loaded - Push enabled: \(pushEnabled)")
            #endif
        } catch {
            await MainActor.run {
                loadingState = .error(message: error.localizedDescription)
            }
            
            #if DEBUG
            print("🔔 NotificationVM: Error loading preferences - \(error)")
            #endif
        }
    }
    
    func togglePushNotifications() async throws {
        #if DEBUG
        print("🔔 NotificationVM: Toggling push notifications")
        #endif
        
        if !preferences.pushEnabled {
            let settings = await notificationCenter.notificationSettings()
            if settings.authorizationStatus == .denied {
                throw NSError(
                    domain: "Notifications",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Please enable notifications in Settings"]
                )
            }
            
            try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
        }
        
        try await updatePreferences { preferences in
            preferences.pushEnabled.toggle()
        }
    }
    
    func toggleCategory(_ category: NotificationCategory) async throws {
        #if DEBUG
        print("🔔 NotificationVM: Toggling category: \(category.id)")
        #endif
        
        try await updatePreferences { preferences in
            if let index = preferences.categories.firstIndex(where: { $0.id == category.id }) {
                preferences.categories[index].isEnabled.toggle()
            }
        }
    }
    
    func updateQuietHours(_ hours: QuietHours?) async throws {
        #if DEBUG
        print("🔔 NotificationVM: Updating quiet hours: \(String(describing: hours))")
        #endif
        
        try await updatePreferences { preferences in
            preferences.quietHours = hours
        }
    }
    
    func toggleEmailNotifications() async throws {
        #if DEBUG
        print("🔔 NotificationVM: Toggling email notifications")
        #endif
        
        try await updatePreferences { preferences in
            preferences.emailEnabled.toggle()
        }
    }
    
    private func updatePreferences(_ update: (inout NotificationPreferences) -> Void) async throws {
        loadingState = .loading(message: "Saving changes...")
        
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                update(&preferences)
                loadingState = .success(message: "Changes saved")
            }
        } catch {
            await MainActor.run {
                loadingState = .error(message: error.localizedDescription)
            }
            
            throw error
        }
    }
}

// MARK: - Notification View
struct NotificationView: View {
    @StateObject private var viewModel: NotificationViewModel
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    
    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: NotificationViewModel(context: context))
        
        #if DEBUG
        print("🔔 NotificationView: Initializing with context")
        #endif
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                generalSettings
                categorySettings
                quietHours
                notificationHistory
            }
            .padding()
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    #if DEBUG
                    print("🔔 NotificationView: Done button tapped")
                    #endif
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $viewModel.showingQuietHoursSetup) {
            QuietHoursSetupView(
                quietHours: viewModel.preferences.quietHours,
                onSave: handleQuietHoursUpdate
            )
        }
        .task {
            await viewModel.loadPreferences()
        }
    }
    
    // MARK: - General Settings
    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "General Settings")
            
            VStack(spacing: Theme.Spacing.sm) {
                Toggle("Push Notifications", isOn: .init(
                    get: { viewModel.preferences.pushEnabled },
                    set: { _ in handlePushToggle() }
                ))
                
                Toggle("Email Notifications", isOn: .init(
                    get: { viewModel.preferences.emailEnabled },
                    set: { _ in handleEmailToggle() }
                ))
            }
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
    }
    
    // MARK: - Category Settings
    private var categorySettings: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Notification Categories")
            
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.preferences.categories) { category in
                    Toggle(category.name, isOn: .init(
                        get: { category.isEnabled },
                        set: { _ in handleCategoryToggle(category) }
                    ))
                }
            }
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
    }
    
    // MARK: - Quiet Hours
    private var quietHours: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Quiet Hours")
            
            Button(action: {
                #if DEBUG
                print("🔔 NotificationView: Quiet hours setup requested")
                #endif
                viewModel.showingQuietHoursSetup = true
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(viewModel.preferences.quietHours == nil ? "Set Up Quiet Hours" : "Quiet Hours")
                            .font(Theme.Typography.body)
                        
                        if let hours = viewModel.preferences.quietHours {
                            Text("\(hours.start.formatted(date: .omitted, time: .shortened)) - \(hours.end.formatted(date: .omitted, time: .shortened))")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .padding()
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
            }
        }
    }
    
    // MARK: - Notification History
    private var notificationHistory: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Recent Notifications")
            
            VStack(spacing: Theme.Spacing.sm) {
                if viewModel.preferences.history.isEmpty {
                    Text("No recent notifications")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(viewModel.preferences.history) { event in
                        NotificationEventRow(event: event)
                    }
                }
            }
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
    }
    
    // MARK: - Helper Methods
    private func handleEmailToggle() {
        Task {
            do {
                try await viewModel.toggleEmailNotifications()
                toastManager.show(
                    viewModel.preferences.emailEnabled ? "Email notifications enabled" : "Email notifications disabled",
                    type: .success
                )
            } catch {
                #if DEBUG
                print("🔔 NotificationView: Error toggling email notifications - \(error)")
                #endif
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
    
    private func handlePushToggle() {
        Task {
            do {
                try await viewModel.togglePushNotifications()
                toastManager.show(
                    viewModel.preferences.pushEnabled ? "Push notifications enabled" : "Push notifications disabled",
                    type: .success
                )
            } catch {
                #if DEBUG
                print("🔔 NotificationView: Error toggling push notifications - \(error)")
                #endif
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
    
    private func handleCategoryToggle(_ category: NotificationCategory) {
        Task {
            do {
                try await viewModel.toggleCategory(category)
                toastManager.show(
                    "\(category.name) notifications \(category.isEnabled ? "enabled" : "disabled")",
                    type: .success
                )
            } catch {
                #if DEBUG
                print("🔔 NotificationView: Error toggling category - \(error)")
                #endif
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
    
    private func handleQuietHoursUpdate(_ hours: QuietHours?) {
        Task {
            do {
                try await viewModel.updateQuietHours(hours)
                toastManager.show(
                    hours == nil ? "Quiet hours disabled" : "Quiet hours updated",
                    type: .success
                )
            } catch {
                #if DEBUG
                print("🔔 NotificationView: Error updating quiet hours - \(error)")
                #endif
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
}

// MARK: - Supporting Views
private struct NotificationEventRow: View {
    let event: NotificationEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(event.title)
                .font(Theme.Typography.body)
            
            Text(event.body)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            
            Text(event.date.formatted(.relative(presentation: .named)))
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - Quiet Hours Setup
private struct QuietHoursSetupView: View {
    let quietHours: QuietHours?
    let onSave: (QuietHours?) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isEnabled: Bool
    @State private var startTime: Date
    @State private var endTime: Date
    
    init(quietHours: QuietHours?, onSave: @escaping (QuietHours?) -> Void) {
        self.quietHours = quietHours
        self.onSave = onSave
        self._isEnabled = State(initialValue: quietHours != nil)
        self._startTime = State(initialValue: quietHours?.start ?? Date())
        self._endTime = State(initialValue: quietHours?.end ?? Date().addingTimeInterval(28800))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Enable Quiet Hours", isOn: $isEnabled)
                }
                
                if isEnabled {
                    Section {
                        DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }
            }
            .navigationTitle("Quiet Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(isEnabled ? QuietHours(start: startTime, end: endTime) : nil)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview Provider
#if DEBUG
struct NotificationView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NotificationView(context: PersistenceController.preview.container.viewContext)
                .environmentObject(ThemeManager())
        }
    }
}
#endif
