// MARK: - Shared View Components
import SwiftUI

// MARK: - Home Header View
struct HomeHeaderView: View {
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
            .padding(.horizontal, Theme.Spacing.lg)
            
            HStack {
                Spacer()
                
                // View toggle button removed as per user request
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(.top, Theme.Spacing.md)
    }
}

// MARK: - Note Card View
struct NoteCardView: View {
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

// MARK: - Card Actions Implementation
struct CardActionsImplementation: CardActions {
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
