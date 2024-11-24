import SwiftUI
import PhotosUI
import CoreData

// MARK: - Profile Models
struct UserProfile: Equatable {
    var name: String
    var email: String
    var phone: String?
    var profileImage: Data?
    var emailVerified: Bool
    var phoneVerified: Bool
    var accountCreated: Date
    
    static let mock = UserProfile(
        name: "Test User",
        email: "test@example.com",
        phone: "+1234567890",
        profileImage: nil,
        emailVerified: true,
        phoneVerified: false,
        accountCreated: Date()
    )
}

// MARK: - Profile View Model
@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: UserProfile
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var isEditingName = false
    @Published var isEditingPhone = false
    @Published var showingImagePicker = false
    @Published var showingVerificationAlert = false
    @Published var verificationMessage: String?
    
    private let viewContext: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        self.profile = .mock
        
        #if DEBUG
        print("👤 ProfileVM: Initializing with context")
        #endif
    }
    
    func loadProfile() async {
        loadingState = .loading(message: "Loading profile...")
        
        do {
            // Simulate API call
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                loadingState = .success(message: "Profile loaded")
            }
            
            #if DEBUG
            print("👤 ProfileVM: Profile loaded successfully")
            #endif
        } catch {
            await MainActor.run {
                loadingState = .error(message: error.localizedDescription)
            }
            
            #if DEBUG
            print("👤 ProfileVM: Error loading profile - \(error)")
            #endif
        }
    }
    
    func updateName(_ name: String) async throws {
        guard !name.isEmpty else {
            throw NSError(domain: "Profile", code: -1, userInfo: [NSLocalizedDescriptionKey: "Name cannot be empty"])
        }
        
        #if DEBUG
        print("👤 ProfileVM: Updating name to: \(name)")
        #endif
        
        try await performUpdate {
            profile.name = name
            isEditingName = false
        }
    }
    
    func updatePhone(_ phone: String) async throws {
        guard !phone.isEmpty else {
            throw NSError(domain: "Profile", code: -1, userInfo: [NSLocalizedDescriptionKey: "Phone cannot be empty"])
        }
        
        #if DEBUG
        print("👤 ProfileVM: Updating phone to: \(phone)")
        #endif
        
        try await performUpdate {
            profile.phone = phone
            isEditingPhone = false
        }
    }
    
    func updateProfileImage(_ imageData: Data?) async throws {
        #if DEBUG
        print("👤 ProfileVM: Updating profile image")
        #endif
        
        try await performUpdate {
            profile.profileImage = imageData
        }
    }
    
    func sendVerificationCode(for type: VerificationType) async throws {
        #if DEBUG
        print("👤 ProfileVM: Sending verification code for: \(type)")
        #endif
        
        loadingState = .loading(message: "Sending verification code...")
        
        do {
            // Simulate API call
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                verificationMessage = "Verification code sent"
                showingVerificationAlert = true
                loadingState = .success(message: "Code sent")
            }
        } catch {
            await MainActor.run {
                loadingState = .error(message: error.localizedDescription)
            }
            
            throw error
        }
    }
    
    private func performUpdate(_ update: () -> Void) async throws {
        loadingState = .loading(message: "Saving changes...")
        
        do {
            // Simulate API call
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                update()
                loadingState = .success(message: "Changes saved")
            }
        } catch {
            await MainActor.run {
                loadingState = .error(message: error.localizedDescription)
            }
            
            throw error
        }
    }
    
    enum VerificationType {
        case email
        case phone
    }
}

// MARK: - Profile View
struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    
    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: ProfileViewModel(context: context))
        
        #if DEBUG
        print("👤 ProfileView: Initializing with context")
        #endif
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                profileHeader
                profileDetails
                verificationSection
                accountInfo
            }
            .padding()
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    #if DEBUG
                    print("👤 ProfileView: Done button tapped")
                    #endif
                    dismiss()
                }
            }
        }
        .photosPicker(
            isPresented: $viewModel.showingImagePicker,
            selection: Binding(
                get: { [PhotosPickerItem]() },
                set: { items in
                    handleImageSelection(items)
                }
            ),
            matching: .images
        )
        .alert("Verification", isPresented: $viewModel.showingVerificationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let message = viewModel.verificationMessage {
                Text(message)
            }
        }
        .task {
            await viewModel.loadProfile()
        }
    }
    
    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProfileImageView(
                imageData: viewModel.profile.profileImage,
                size: 120
            ) {
                #if DEBUG
                print("👤 ProfileView: Profile image tapped")
                #endif
                viewModel.showingImagePicker = true
            }
            
            if viewModel.isEditingName {
                CustomTextField(
                    placeholder: "Your Name",
                    text: .init(
                        get: { viewModel.profile.name },
                        set: { handleNameUpdate($0) }
                    )
                )
            } else {
                Text(viewModel.profile.name)
                    .font(Theme.Typography.h2)
                    .onTapGesture {
                        #if DEBUG
                        print("👤 ProfileView: Name text tapped")
                        #endif
                        viewModel.isEditingName = true
                    }
            }
        }
    }
    
    // MARK: - Profile Details
    private var profileDetails: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Contact Information")
            
            VStack(spacing: Theme.Spacing.md) {
                DetailRow(
                    title: "Email",
                    value: viewModel.profile.email,
                    isVerified: viewModel.profile.emailVerified
                )
                
                if viewModel.isEditingPhone {
                    CustomTextField(
                        placeholder: "Phone Number",
                        text: .init(
                            get: { viewModel.profile.phone ?? "" },
                            set: { handlePhoneUpdate($0) }
                        ),
                        keyboardType: .phonePad
                    )
                } else {
                    DetailRow(
                        title: "Phone",
                        value: viewModel.profile.phone ?? "Add phone number",
                        isVerified: viewModel.profile.phoneVerified,
                        isPlaceholder: viewModel.profile.phone == nil
                    ) {
                        #if DEBUG
                        print("👤 ProfileView: Phone row tapped")
                        #endif
                        viewModel.isEditingPhone = true
                    }
                }
            }
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
    }
    
    // MARK: - Verification Section
    private var verificationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Verification")
            
            VStack(spacing: Theme.Spacing.sm) {
                if !viewModel.profile.emailVerified {
                    Button(action: {
                        #if DEBUG
                        print("👤 ProfileView: Verify email button tapped")
                        #endif
                        handleVerification(.email)
                    }) {
                        Text("Verify Email")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                
                if viewModel.profile.phone != nil && !viewModel.profile.phoneVerified {
                    Button(action: {
                        #if DEBUG
                        print("👤 ProfileView: Verify phone button tapped")
                        #endif
                        handleVerification(.phone)
                    }) {
                        Text("Verify Phone")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }
    
    // MARK: - Account Info
    private var accountInfo: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Account Information")
            
            Text("Member since \(viewModel.profile.accountCreated.formatted(date: .long, time: .omitted))")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }
    }
    
    // MARK: - Helper Methods
    private func handleNameUpdate(_ name: String) {
        Task {
            do {
                try await viewModel.updateName(name)
                toastManager.show("Name updated successfully", type: .success)
            } catch {
                #if DEBUG
                print("👤 ProfileView: Error updating name - \(error)")
                #endif
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
    
    private func handlePhoneUpdate(_ phone: String) {
        Task {
            do {
                try await viewModel.updatePhone(phone)
                toastManager.show("Phone updated successfully", type: .success)
            } catch {
                #if DEBUG
                print("👤 ProfileView: Error updating phone - \(error)")
                #endif
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
    
    private func handleImageSelection(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }
        
        Task {
            do {
                let data = try await item.loadTransferable(type: Data.self)
                try await viewModel.updateProfileImage(data)
                toastManager.show("Profile picture updated", type: .success)
            } catch {
                #if DEBUG
                print("👤 ProfileView: Error updating profile image - \(error)")
                #endif
                toastManager.show("Failed to update profile picture", type: .error)
            }
        }
    }
    
    private func handleVerification(_ type: ProfileViewModel.VerificationType) {
        Task {
            do {
                try await viewModel.sendVerificationCode(for: type)
            } catch {
                #if DEBUG
                print("👤 ProfileView: Error sending verification code - \(error)")
                #endif
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
}

// MARK: - Supporting Views
private struct ProfileImageView: View {
    let imageData: Data?
    let size: CGFloat
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            if let imageData = imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .standardShadow()
            } else {
                Circle()
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size/2))
                            .foregroundColor(Theme.Colors.secondaryText)
                    )
                    .standardShadow()
            }
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    let isVerified: Bool
    var isPlaceholder: Bool = false
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                
                Text(value)
                    .font(Theme.Typography.body)
                    .foregroundColor(isPlaceholder ? Theme.Colors.secondaryText : Theme.Colors.text)
            }
            
            Spacer()
            
            if isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(Theme.Colors.success)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let action = action {
                action()
            }
        }
    }
}

// MARK: - Preview Provider
#if DEBUG
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ProfileView(context: PersistenceController.preview.container.viewContext)
                .environmentObject(ThemeManager())
        }
    }
}
#endif
