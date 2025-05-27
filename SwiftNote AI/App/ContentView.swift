import SwiftUI
import CoreData
import AVFoundation
import Speech
import Combine

// MARK: - Navigation Bar
private struct CustomNavigationBar: View {

    private let gradientColors = [
        Theme.Colors.primary.opacity(0.8),
        Theme.Colors.primary
    ]

    var currentFolder: Folder? = nil


   var body: some View {
       HStack {
           VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
               if let folder = currentFolder {
                   HStack(spacing: Theme.Spacing.xs) {
                       Circle()
                           .fill(Color(folder.color ?? "blue"))
                           .frame(width: 8, height: 8)
                       Text(folder.name ?? "Untitled")
                   }
                   .font(Theme.Typography.caption)
                   .foregroundColor(Theme.Colors.secondaryText)
               }
               Text("Good \(timeOfDay)")
                   .font(Theme.Typography.caption)
                   .foregroundColor(Theme.Colors.secondaryText)
           }
           .animation(.easeInOut, value: timeOfDay)

           Spacer()


           Menu {
               Button(action: {
                   #if DEBUG
                   print("🏠 NavBar: Settings tapped")
                   #endif
               }) {
                   Label("Settings", systemImage: "gear")
               }
               Button(action: {
                   #if DEBUG
                   print("🏠 NavBar: Help tapped")
                   #endif
               }) {
                   Label("Help", systemImage: "questionmark.circle")
               }
           } label: {
               Image(systemName: "ellipsis.circle")
                   .font(.title2)
                   .foregroundColor(Theme.Colors.primary)
                   .scaleEffect(1.0)
                   .animation(.spring(response: 0.3, dampingFraction: 0.7), value: true)
           }
       }
       .padding(.horizontal, Theme.Spacing.md)
   }

   private var timeOfDay: String {
       let hour = Calendar.current.component(.hour, from: Date())
       switch hour {
       case 0..<12: return "morning"
       case 12..<17: return "afternoon"
       default: return "evening"
       }
   }
}

// MARK: - Folder Navigation Button
private struct FolderNavigationButton: View {
    @Binding var isShowingFolders: Bool

    var body: some View {
        Button(action: {
            #if DEBUG
            print("📁 ContentView: Folder navigation button tapped")
            #endif
            isShowingFolders = true
        }) {
            Image(systemName: "folder.fill")
                .font(.system(size: 24))
                .foregroundColor(Theme.Colors.primary)
                .frame(width: 44, height: 44)
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
        }
    }
}

// MARK: - Notes Content View
private struct NotesContentView: View {
    @ObservedObject var viewModel: HomeViewModel
    let cardActions: (NoteCardConfiguration) -> CardActions
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedNote: NoteCardConfiguration?
    @State private var isRefreshing = false

    var body: some View {
        NotesScrollContent(
            viewModel: viewModel,
            isRefreshing: $isRefreshing,
            selectedNote: $selectedNote,
            cardActions: cardActions
        )
        .fullScreenCover(item: $selectedNote) { note in
            NoteDetailsView(note: note, context: viewContext)
        }
    }
}

// MARK: - Notes Scroll Content
private struct NotesScrollContent: View {
    @ObservedObject var viewModel: HomeViewModel
    @Binding var isRefreshing: Bool
    @Binding var selectedNote: NoteCardConfiguration?
    let cardActions: (NoteCardConfiguration) -> CardActions
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        RefreshableScrollView {
            #if DEBUG
            print("🏠 NotesContent: Refreshing content")
            #endif
            withAnimation {
                isRefreshing = true
            }
            viewModel.fetchNotes()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation {
                    isRefreshing = false
                }
            }
        } content: {
            NotesContentContainer(
                viewModel: viewModel,
                isRefreshing: $isRefreshing,
                selectedNote: $selectedNote,
                cardActions: cardActions
            )
        }
    }
}

// MARK: - Notes Content Container
private struct NotesContentContainer: View {
    @ObservedObject var viewModel: HomeViewModel
    @Binding var isRefreshing: Bool
    @Binding var selectedNote: NoteCardConfiguration?
    let cardActions: (NoteCardConfiguration) -> CardActions

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingIndicator(message: "Loading notes...")
                    .padding(.top, Theme.Spacing.xl)
            } else if viewModel.notes.isEmpty {
                EmptyStateView(
                    icon: "note.text",
                    title: "No Notes Yet",
                    message: "Start by creating your first note.\nTap the + button below to begin!",
                    actionTitle: nil
                ) {
                    #if DEBUG
                    print("🏠 NotesContent: Empty state create note tapped")
                    #endif
                    viewModel.isShowingAddNote = true
                }
                .transition(.opacity)
            } else {
                NotesGridListView(
                    viewModel: viewModel,
                    selectedNote: $selectedNote,
                    cardActions: cardActions
                )
            }
        }
        .overlay(RefreshingOverlay(isRefreshing: isRefreshing))
    }
}

// MARK: - Notes Grid/List View
private struct NotesGridListView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Binding var selectedNote: NoteCardConfiguration?
    let cardActions: (NoteCardConfiguration) -> CardActions

    var body: some View {
        ListGridContainer(viewMode: $viewModel.viewMode) {
            AnyView(
                ForEach(viewModel.notes, id: \.title) { note in
                    NoteCardView(
                        note: note,
                        viewMode: viewModel.viewMode,
                        cardActions: cardActions,
                        selectedNote: $selectedNote
                    )
                }
            )
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
}

// MARK: - Refreshing Overlay
private struct RefreshingOverlay: View {
    let isRefreshing: Bool

    var body: some View {
        Group {
            if isRefreshing {
                VStack {
                    ProgressView()
                        .tint(Theme.Colors.primary)
                    Text("Refreshing...")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.1))
            }
        }
    }
}

private struct RefreshableScrollView<Content: View>: View {
   let onRefresh: () -> Void
   let content: Content

   init(
       onRefresh: @escaping () -> Void,
       @ViewBuilder content: () -> Content
   ) {
       self.onRefresh = onRefresh
       self.content = content()
   }

   var body: some View {
       ScrollView {
           content
               .refreshable {
                   onRefresh()
               }
       }
   }
}

// MARK: - Add Note Action Sheet
private struct AddNoteActionSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: HomeViewModel) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)

        #if DEBUG
        print("🏠 AddNoteSheet: Initializing with viewModel")
        #endif
    }

    var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            ActionCard(items: [
                ActionCardItem(title: "Record Audio", icon: "mic", color: .blue) {
                    #if DEBUG
                    print("🏠 AddNoteSheet: Record audio selected")
                    #endif
                    viewModel.isShowingAddNote = false
                    viewModel.isShowingRecording = true
                },

                ActionCardItem(title: "Import Audio", icon: "waveform", color: .orange) {
                    #if DEBUG
                    print("🏠 AddNoteSheet: Upload audio selected")
                    #endif
                    viewModel.isShowingAddNote = false
                    viewModel.isShowingAudioUpload = true
                },

                ActionCardItem(title: "Scan Text", icon: "viewfinder.circle", color: .blue) {
                    #if DEBUG
                    print("🏠 AddNoteSheet: Scan text selected")
                    #endif
                    viewModel.isShowingAddNote = false
                    viewModel.isShowingTextScan = true
                },

                ActionCardItem(title: "Import PDF", icon: "doc", color: .blue) {
                    #if DEBUG
                    print("🏠 AddNoteSheet: Upload text selected")
                    #endif
                    viewModel.isShowingAddNote = false
                    viewModel.isShowingTextUpload = true
                },

                ActionCardItem(title: "YouTube Video", icon: "play.circle.fill", color: .red) {
                    #if DEBUG
                    print("🏠 AddNoteSheet: YouTube video selected")
                    #endif
                    viewModel.isShowingAddNote = false
                    viewModel.isShowingYouTubeInput = true
                },

                ActionCardItem(title: "Web Link", icon: "link", color: .blue) {
                    #if DEBUG
                    print("🏠 AddNoteSheet: Web link selected")
                    #endif
                    viewModel.isShowingAddNote = false
                    viewModel.isShowingWebLinkInput = true
                }
            ])
            .padding(.top, Theme.Spacing.lg)
        }
    }
}

// MARK: - Custom Add Button
private struct AddNoteButton: View {
    let action: () -> Void
    @State private var isPressed = false
    @State private var isHovered = false
    @State private var isAnimating = false

    var body: some View {
            Button(action: {
                #if DEBUG
                print("🏠 AddNoteButton: Button pressed with haptic feedback")
                #endif
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = true
                    // Add subtle bounce animation for iOS 16
                    isAnimating = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isPressed = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isAnimating = false
                        }
                    }
                }
                action()
            }) {
                ZStack {
                // Animated background gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.Colors.primary,
                                Theme.Colors.primary.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(
                        color: Theme.Colors.primary.opacity(isHovered ? 0.4 : 0.3),
                        radius: isHovered ? 12 : 8,
                        x: 0,
                        y: isHovered ? 6 : 4
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 2)
                    )

                // Animated plus icon
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(.white)
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAnimating)
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
        }
        .padding(.bottom, Theme.Spacing.xl)
    }
}

// MARK: - Content View
struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel: HomeViewModel
    @Environment(\.toastManager) private var toastManager
    @State private var selectedNote: NoteCardConfiguration?
    @State private var isShowingFolders = false
    @State private var selectedFolder: Folder? {
        didSet {
            if let folderId = selectedFolder?.id {
                viewModel.currentFolderId = folderId
                #if DEBUG
                print("""
                📁 ContentView: Folder selection updated
                - ID: \(folderId)
                - Name: \(selectedFolder?.name ?? "nil")
                """)
                #endif
            } else {
                viewModel.currentFolderId = nil
            }
        }
    }

    init(context: NSManagedObjectContext? = nil) {
        let ctx = context ?? PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: HomeViewModel(context: ctx))

        #if DEBUG
        print("🏠 ContentView: Initializing with context")
        #endif

        // Initialize Supabase when ContentView is created
        Task {
            await SupabaseService.shared.initialize()

            #if DEBUG
            print("🏠 ContentView: Supabase initialized")
            #endif
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HomeHeaderView(
                        searchText: $viewModel.searchText,
                        viewMode: $viewModel.viewMode
                    )

                    NotesContentView(
                        viewModel: viewModel,
                        cardActions: makeCardActions
                    )
                }

                // Note Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        AddNoteButton(action: {
                            viewModel.isShowingAddNote = true
                        })
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $viewModel.isShowingSettings) {
                NavigationView {
                    SettingsView()
                }
                .navigationViewStyle(StackNavigationViewStyle()) // Use stack style to prevent split view on iPad
            }
            .fullScreenCover(isPresented: $viewModel.isShowingProfile) {
                AuthProfileView()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    FolderNavigationButton(isShowingFolders: $isShowingFolders)
                        .onChange(of: isShowingFolders) { newValue in
                            #if DEBUG
                            print("📁 ContentView: Folder visibility changed to: \(newValue)")
                            #endif
                        }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: Theme.Spacing.md) {
                        // Profile button
                        Button(action: {
                            #if DEBUG
                            print("👤 ContentView: Profile button tapped")
                            #endif
                            viewModel.isShowingProfile = true
                        }) {
                            Image(systemName: "person.circle")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.Colors.primary)
                                .scaleEffect(viewModel.isShowingProfile ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isShowingProfile)
                        }

                        // Settings button
                        Button(action: {
                            #if DEBUG
                            print("⚙️ ContentView: Settings button tapped")
                            #endif
                            viewModel.isShowingSettings = true
                        }) {
                            Image(systemName: "gear")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.Colors.primary)
                                .scaleEffect(viewModel.isShowingSettings ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isShowingSettings)
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.isShowingAddNote) {
                AddNoteActionSheet(viewModel: viewModel)
                    .presentationDetents([.height(390)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
                    .presentationCornerRadius(24)
                    .interactiveDismissDisabled(false)
            }
            .fullScreenCover(isPresented: $viewModel.isShowingRecording) {
                AudioRecordingView(context: viewContext)
            }
            .fullScreenCover(isPresented: $viewModel.isShowingYouTubeInput) {
                YouTubeView()
            }
            .fullScreenCover(isPresented: $viewModel.isShowingTextUpload) {
                TextUploadView(context: viewContext)
            }
            .fullScreenCover(isPresented: $viewModel.isShowingAudioUpload) {
                AudioUploadView(context: viewContext)
            }
            .fullScreenCover(isPresented: $viewModel.isShowingTextScan) {
                ScanTextView(context: viewContext)
            }
            .fullScreenCover(isPresented: $viewModel.isShowingWebLinkInput) {
                WebLinkImportView(context: viewContext)
            }
            .fullScreenCover(isPresented: $isShowingFolders) {
                FolderListView(selectedFolder: $selectedFolder)
            }

        }
        .onAppear {
            #if DEBUG
            print("📱 ContentView appeared - Starting fetch")
            #endif
            viewModel.fetchNotes()
        }
        .onChange(of: viewModel.isShowingYouTubeInput) { isShowing in
            if !isShowing {
                #if DEBUG
                print("📱 YouTube input dismissed - Refreshing notes")
                #endif
                viewModel.fetchNotes()
            }
        }
    }

    private func makeCardActions(for note: NoteCardConfiguration) -> CardActions {
        return CardActionsImplementation(
            note: note,
            viewModel: viewModel,
            toastManager: toastManager
        )
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Main Content View Preview
            ContentView(context: PersistenceController.preview.container.viewContext)
                .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
                .environmentObject(ThemeManager())
                .previewDisplayName("Main View")

            // Empty State Preview
            ContentView(context: {
                let context = PersistenceController.preview.container.viewContext
                // Clear any existing notes for empty state
                let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Note.fetchRequest()
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                do {
                    try context.execute(deleteRequest)
                } catch {
                    print("Preview Error: Failed to clear notes - \(error)")
                }
                return context
            }())
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .environmentObject(ThemeManager())
            .previewDisplayName("Empty State")

            // Component Previews
            CustomNavigationBar()
                .previewLayout(.sizeThatFits)
                .padding()
                .previewDisplayName("Navigation Bar")

            AddNoteButton(action: {})
                .previewLayout(.sizeThatFits)
                .padding()
                .previewDisplayName("Add Note Button")

            HomeHeaderView(
                searchText: .constant(""),
                viewMode: .constant(.list)
            )
            .previewLayout(.sizeThatFits)
            .padding()
            .previewDisplayName("Header View")
        }
    }
}
#endif
