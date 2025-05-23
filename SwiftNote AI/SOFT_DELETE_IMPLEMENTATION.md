# Soft Delete Implementation for Note Sync

## Problem Summary
When notes were deleted locally in the app, they were being hard deleted from CoreData. During sync, these deleted notes would be re-downloaded from Supabase because:
1. The local deletion removed the note completely from CoreData
2. The sync process had no record of the deletion
3. Supabase still contained the note, so it was downloaded again

## Solution Overview
Implemented a soft delete mechanism that:
1. Sets a `deletedAt` timestamp instead of hard deleting notes
2. Marks deleted notes for sync to propagate deletions to Supabase
3. Filters out deleted notes during normal operations and downloads
4. Includes deleted notes in upload sync to ensure deletions are propagated

## Changes Made

### 1. Persistence.swift
- **Modified `deleteNote()`**: Now performs soft delete by setting `deletedAt` timestamp and marking for sync
- **Added `permanentlyDeleteNote()`**: For cleanup operations that need hard deletion
- **Updated `fetchNotes()`**: Added `includeDeleted` parameter to optionally exclude deleted notes

### 2. SupabaseSyncService.swift
- **Updated `fetchNotesForSync()`**: Now includes deleted notes (with `syncStatus != "synced"`) for upload
- **Modified `downloadNotesFromSupabase()`**: Filters out deleted notes using `is("deleted_at", value: nil)`
- **Enhanced `resolveNoteConflict()`**: Skips deleted remote notes and doesn't update locally deleted notes
- **Added `deleteNoteFromSupabase()`**: Permanently deletes notes from Supabase and marks for cleanup
- **Added `deleteFolderFromSupabase()`**: Permanently deletes folders from Supabase and marks for cleanup
- **Added `cleanupDeletedItems()`**: Safely removes items deleted from Supabase after sync completes
- **Added `cleanupInvalidFolders()`**: Removes empty folders with default values that shouldn't exist
- **Added `cleanupOldDeletedNotes()`**: Permanently deletes notes soft-deleted more than 30 days ago

### 3. HomeViewModel.swift
- **Updated `fetchNotes()`**: Added predicate to exclude deleted notes (`deletedAt == nil`)
- **Modified `filterNotes()`**: Added deleted note exclusion to both title and content search

### 4. Test Implementation
- **Created `SoftDeleteTest.swift`**: Contains test methods to verify soft delete functionality

## How It Works

### Deletion Flow
1. User deletes a note in the app
2. `PersistenceController.deleteNote()` sets `deletedAt = Date()` and `syncStatus = "pending"`
3. Note remains in CoreData but is hidden from normal queries
4. During sync, the deleted note is uploaded to Supabase with its `deletedAt` timestamp
5. Supabase now knows the note is deleted

### Sync Flow
1. **Upload Phase**:
   - Deleted notes/folders are permanently removed from Supabase
   - Active notes/folders are uploaded/updated normally
   - Deleted items are marked as "deleted_from_supabase" (not immediately deleted to avoid threading issues)
2. **Download Phase**: Only non-deleted notes (where `deleted_at IS NULL`) are downloaded from Supabase
3. **Conflict Resolution**: Deleted notes are skipped during conflict resolution
4. **Cleanup Phase**: Items marked as "deleted_from_supabase" are permanently removed from local CoreData

### UI Flow
1. All fetch operations exclude deleted notes by default
2. Search operations also exclude deleted notes
3. Users never see deleted notes in the interface

## Testing the Implementation

### Manual Testing
1. Create a note in the app
2. Delete the note
3. Perform a sync
4. Verify the note doesn't reappear after sync

### Programmatic Testing
```swift
// Run the test methods
SoftDeleteTest.testSoftDelete()
SoftDeleteTest.testSyncFiltering()
```

### Usage Examples
```swift
// Normal deletion (now uses soft delete)
try PersistenceController.shared.deleteNote(note)

// Fetch active notes (excludes deleted)
let activeNotes = try PersistenceController.shared.fetchNotes()

// Fetch all notes including deleted (for admin/cleanup)
let allNotes = try PersistenceController.shared.fetchNotes(includeDeleted: true)

// Cleanup old deleted notes (call periodically)
try await SupabaseSyncService.shared.cleanupOldDeletedNotes(context: context)

// Clean up any invalid "Untitled Folder" with blue color (one-time fix)
SoftDeleteTest.cleanupInvalidFolders()
```

### Verification Points
- ✅ Deleted notes have `deletedAt` timestamp set
- ✅ Deleted notes are marked with `syncStatus = "pending"`
- ✅ Normal fetch operations exclude deleted notes
- ✅ Sync operations include deleted notes for deletion from Supabase
- ✅ Download operations exclude deleted notes
- ✅ Deleted notes don't reappear after sync
- ✅ Deleted notes are permanently removed from Supabase during sync
- ✅ Deleted notes are permanently removed from local CoreData after Supabase deletion

## Cleanup Strategy
- Notes soft-deleted for more than 30 days can be permanently removed using `cleanupOldDeletedNotes()`
- This can be called periodically or during app maintenance
- Associated files are also cleaned up during permanent deletion

## Benefits
1. **Data Integrity**: No accidental data loss from hard deletes
2. **Sync Reliability**: Deletions are properly propagated across devices
3. **Recovery Possible**: Soft-deleted notes could be recovered if needed
4. **Performance**: Deleted notes are efficiently filtered out of normal operations

## Known Issues Fixed

### "Untitled Folder" Issue
**Problem**: An "Untitled Folder" with blue color appeared in the folders list but wasn't in Supabase.

**Cause**: CoreData model has default values (`name="Untitled Folder"`, `color="blue"`) that were being used during sync operations, creating phantom folders.

**Solution**:
- Added validation to skip syncing empty folders with default values
- Added `cleanupInvalidFolders()` to remove existing invalid folders
- Sync now ignores folders with default values that have no notes

## Migration Notes
- Existing notes without `deletedAt` field will continue to work normally
- The `deletedAt` field is optional in the CoreData model
- No database migration is required as the field already exists
- Run `SoftDeleteTest.cleanupInvalidFolders()` once to remove any existing invalid folders
