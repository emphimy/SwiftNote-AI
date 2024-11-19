// ContentView.swift

import CoreData
import SwiftUI
import Combine

// MARK: - Navigation Bar
private struct CustomNavigationBar: View {
   var body: some View {
       HStack {
           VStack(alignment: .leading) {
               Text("My Notes")
                   .font(Theme.Typography.h2)
               Text("Good \(timeOfDay)")
                   .font(Theme.Typography.caption)
                   .foregroundColor(Theme.Colors.secondaryText)
           }
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

// MARK: - Home Header View
private struct HomeHeaderView: View {
   @Binding var searchText: String
   @Binding var viewMode: ListGridContainer<AnyView>.ViewMode
   
   var body: some View {
       VStack(spacing: Theme.Spacing.sm) {
           SearchBar(
               text: $searchText,
               placeholder: "Search notes"
           )
           HStack {
               Spacer()
               
               Button(action: {
                   #if DEBUG
                   print("🏠 HomeHeader: Toggle view mode to: \(viewMode == .list ? "grid" : "list")")
                   #endif
                   withAnimation {
                       viewMode = viewMode == .list ? .grid : .list
                   }
               }) {
                   Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                       .foregroundColor(Theme.Colors.primary)
               }
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
   
   private var gridColumns: [GridItem] {
       let count = sizeClass == .compact ? 2 : 3
       return Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: count)
   }

   var body: some View {
       RefreshableScrollView {
           #if DEBUG
           print("🏠 NotesContent: Refreshing content")
           #endif
           viewModel.fetchNotes()
       } content: {
           if viewModel.isLoading {
               LoadingIndicator(message: "Loading notes...")
                   .padding(.top, Theme.Spacing.xl)
           } else if viewModel.notes.isEmpty {
               EmptyStateView(
                   icon: "note.text",
                   title: "No Notes Yet",
                   message: "Start by creating your first note",
                   actionTitle: nil
               ) {
                   #if DEBUG
                   print("🏠 NotesContent: Empty state create note tapped")
                   #endif
                   viewModel.isShowingAddNote = true
               }
           } else {
               ListGridContainer(viewMode: $viewModel.viewMode) {
                   AnyView(
                       ForEach(viewModel.notes, id: \.title) { note in
                           Group {
                               if viewModel.viewMode == .list {
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
                           .transition(.scale.combined(with: .opacity))
                       }
                   )
               }
               .padding(.horizontal, Theme.Spacing.md)
           }
       }
       .sheet(item: $selectedNote) { note in
           NoteDetailsView(note: note, context: viewContext)
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
           },
           ActionCardItem(title: "Scan Text", icon: "doc.text.viewfinder", color: .green) {
               #if DEBUG
               print("🏠 AddNoteSheet: Scan text selected")
               #endif
           },
           ActionCardItem(title: "Upload Text", icon: "doc.badge.arrow.up", color: .blue) {
               #if DEBUG
               print("🏠 AddNoteSheet: Upload text selected")
               #endif
           },
           ActionCardItem(title: "YouTube Video", icon: "video.fill", color: .red) {
               #if DEBUG
               print("🏠 AddNoteSheet: YouTube video selected")
               #endif
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
    
    var body: some View {
        Button(action: {
            #if DEBUG
            print("🏠 AddNoteButton: Button pressed with haptic feedback")
            #endif
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                }
            }
            action()
        }) {
            ZStack {
                // Main button background
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Theme.Colors.primary,
                                Theme.Colors.primary.opacity(0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: Theme.Colors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 2)
                    )
                
                // Plus icon
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)
            }
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .padding(.bottom, Theme.Spacing.xl)
    }
}

// MARK: - Content View
struct ContentView: View {
   @Environment(\.managedObjectContext) private var viewContext
   @StateObject private var viewModel: HomeViewModel
   @Environment(\.toastManager) private var toastManager
   @State private var selectedNote: NoteCardConfiguration?

   
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
               
               // Add Note Button
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
               ToolbarItem(placement: .navigationBarTrailing) {
                   Button(action: {
                       #if DEBUG
                       print("🏠 ContentView: Settings button tapped")
                       #endif
                       viewModel.isShowingSettings = true
                   }) {
                       Image(systemName: "gear")
                           .foregroundColor(Theme.Colors.primary)
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
