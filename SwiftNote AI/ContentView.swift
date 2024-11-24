// ContentView.swift

import CoreData
import SwiftUI
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
                .font(.title2)
                .foregroundColor(Theme.Colors.primary)
                .frame(width: 44, height: 44)
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
        }
    }
}

// MARK: - Home Header View
private struct HomeHeaderView: View {
    @Binding var searchText: String
    @Binding var viewMode: ListGridContainer<AnyView>.ViewMode
    @State private var isSearchFocused = false
    
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            SearchBar(
                text: $searchText,
                placeholder: "Search notes"
            ) {
                #if DEBUG
                print("🏠 HomeHeader: Search cancelled")
                #endif
                isSearchFocused = false
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                    .stroke(Theme.Colors.primary.opacity(isSearchFocused ? 0.3 : 0), lineWidth: 2)
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isSearchFocused = true
                }
            }
            
            HStack {
                Spacer()
                
                Button(action: {
                    #if DEBUG
                    print("🏠 HomeHeader: Toggle view mode to: \(viewMode == .list ? "grid" : "list")")
                    #endif
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewMode = viewMode == .list ? .grid : .list
                    }
                }) {
                    Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                        .foregroundColor(Theme.Colors.primary)
                        .padding(Theme.Spacing.xs)
                        .background(
                            Circle()
                                .fill(Theme.Colors.primary.opacity(0.1))
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .padding(.top, Theme.Spacing.md)
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
        .sheet(item: $selectedNote) { note in
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

// MARK: - Note Card View
private struct NoteCardView: View {
    let note: NoteCardConfiguration
    let viewMode: ListGridContainer<AnyView>.ViewMode
    let cardActions: (NoteCardConfiguration) -> CardActions
    @Binding var selectedNote: NoteCardConfiguration?
    
    var body: some View {
        Group {
            if viewMode == .list {
                NoteListCard(
                    configuration: note,
                    actions: cardActions(note),
                    onTap: { selectedNote = note }
                )
            } else {
                NoteGridCard(
                    configuration: note,
                    actions: cardActions(note),
                    onTap: { selectedNote = note }
                )
            }
        }
        .transition(.asymmetric(
            insertion: .scale.combined(with: .opacity),
            removal: .opacity
        ))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewMode)
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

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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
    
    init(viewModel: HomeViewModel) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        
        #if DEBUG
        print("🏠 AddNoteSheet: Initializing with viewModel")
        #endif
    }

    var body: some View {
        ActionCard(items: [
            ActionCardItem(title: "Record Audio", icon: "mic.fill", color: .blue) {
                #if DEBUG
                print("🏠 AddNoteSheet: Record audio selected")
                #endif
                viewModel.isShowingAddNote = false
                viewModel.isShowingRecording = true
            },
        
            ActionCardItem(title: "Upload Audio", icon: "waveform", color: .orange) {
                #if DEBUG
                print("🏠 AddNoteSheet: Upload audio selected")
                #endif
                viewModel.isShowingAddNote = false
                viewModel.isShowingAudioUpload = true
            },
            ActionCardItem(title: "Scan Text", icon: "doc.text.viewfinder", color: .green) {
                #if DEBUG
                print("🏠 AddNoteSheet: Scan text selected")
                #endif
                viewModel.isShowingAddNote = false
                viewModel.isShowingTextScan = true
            },
            ActionCardItem(title: "Upload Text", icon: "doc.badge.arrow.up", color: .blue) {
                #if DEBUG
                print("🏠 AddNoteSheet: Upload text selected")
                #endif
                viewModel.isShowingAddNote = false
                viewModel.isShowingTextUpload = true
            },
            ActionCardItem(title: "YouTube Video", icon: "video.fill", color: .red) {
                #if DEBUG
                print("🏠 AddNoteSheet: YouTube video selected")
                #endif
                viewModel.isShowingAddNote = false
                viewModel.isShowingYouTubeInput = true
            },
           ActionCardItem(title: "Google Drive", icon: "externaldrive.fill", color: .blue) {
               #if DEBUG
               print("🏠 AddNoteSheet: Google Drive selected")
               #endif
           },
           ActionCardItem(title: "Dropbox", icon: "archivebox.fill", color: .blue) {
               #if DEBUG
               print("🏠 AddNoteSheet: Dropbox selected")
               #endif
           }
       ])
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
    @State private var selectedFolder: Folder?
    
    init(context: NSManagedObjectContext? = nil) {
        let ctx = context ?? PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: HomeViewModel(context: ctx))
        
        #if DEBUG
        print("🏠 ContentView: Initializing with context")
        #endif
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
            .sheet(isPresented: $viewModel.isShowingSettings) {
                NavigationView {
                    SettingsView()
                }
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
                    Button(action: {
                        #if DEBUG
                        print("⚙️ ContentView: Settings button tapped")
                        #endif
                        viewModel.isShowingSettings = true
                    }) {
                        Image(systemName: "gear")
                            .foregroundColor(Theme.Colors.primary)
                            .scaleEffect(viewModel.isShowingSettings ? 1.1 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isShowingSettings)
                    }
                }
            }
            .sheet(isPresented: $viewModel.isShowingAddNote) {
                AddNoteActionSheet(viewModel: viewModel)
                    .presentationDetents([.height(470)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $viewModel.isShowingRecording) {
                AudioRecordingView(context: viewContext)
            }
            .sheet(isPresented: $viewModel.isShowingYouTubeInput) {
                YouTubeInputView(context: viewContext)
            }
            .sheet(isPresented: $viewModel.isShowingTextUpload) {
                TextUploadView(context: viewContext)
            }
            .sheet(isPresented: $viewModel.isShowingAudioUpload) {
                AudioUploadView(context: viewContext)
            }
            .sheet(isPresented: $isShowingFolders) {
                FolderListView(selectedFolder: $selectedFolder)
            }
            .sheet(isPresented: $viewModel.isShowingTextScan) {
                ScanTextView(context: viewContext)
            }
        }
        .onAppear {
            #if DEBUG
            print("🏠 ContentView: View appeared")
            #endif
            viewModel.fetchNotes()
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

// MARK: - Card Actions Implementation
private struct CardActionsImplementation: CardActions {
   let note: NoteCardConfiguration
   let viewModel: HomeViewModel
   let toastManager: ToastManager
   
    func onFavorite() {
        Task {
            do {
                try await viewModel.toggleFavorite(note)
                await MainActor.run {
                    toastManager.show("Favorite updated", type: .success)
                }
            } catch {
                #if DEBUG
                print("🏠 CardActions: Error toggling favorite: \(error.localizedDescription)")
                #endif
                await MainActor.run {
                    toastManager.show("Failed to update favorite status", type: .error)
                }
            }
        }
    }
   
   func onShare() {
       #if DEBUG
       print("🏠 CardActions: Share triggered for note: \(note.title)")
       #endif
       // TODO: Implement share functionality
   }
   
    func onDelete() {
        Task {
            do {
                try await viewModel.deleteNote(note)
                await MainActor.run {
                    toastManager.show("Note deleted", type: .success)
                }
            } catch {
                #if DEBUG
                print("🏠 CardActions: Error deleting note: \(error.localizedDescription)")
                #endif
                await MainActor.run {
                    toastManager.show("Failed to delete note", type: .error)
                }
            }
        }
    }
   
   func onTagSelected(_ tag: String) {
       #if DEBUG
       print("🏠 CardActions: Tag selected: \(tag) for note: \(note.title)")
       #endif
       // TODO: Implement tag selection handling
   }
}

#Preview {
   ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
