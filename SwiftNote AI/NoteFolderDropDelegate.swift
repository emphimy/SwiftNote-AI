import SwiftUI
import CoreData

struct NoteFolderDropDelegate: DropDelegate {
    let folder: Folder
    let viewModel: FolderListViewModel
    
    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.text]).first else {
            #if DEBUG
            print("📁 DropDelegate: No valid item found")
            #endif
            return false
        }
        
        item.loadObject(ofClass: NSString.self) { (id, error) in
            if let error = error {
                #if DEBUG
                print("📁 DropDelegate: Error loading dragged item - \(error)")
                #endif
                return
            }
            
            guard let noteId = id as? String,
                  let noteUUID = UUID(uuidString: noteId) else {
                #if DEBUG
                print("📁 DropDelegate: Invalid note ID")
                #endif
                return
            }
            
            DispatchQueue.main.async {
                moveNote(withId: noteUUID, to: folder)
            }
        }
        return true
    }
    
    private func moveNote(withId id: UUID, to folder: Folder) {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Note>(entityName: "Note")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let notes = try context.fetch(request)
            if let note = notes.first {
                viewModel.moveNote(note, to: folder)
                #if DEBUG
                print("📁 DropDelegate: Successfully moved note to folder '\(folder.name ?? "")'")
                #endif
            }
        } catch {
            #if DEBUG
            print("📁 DropDelegate: Error fetching note - \(error)")
            #endif
        }
    }
}
