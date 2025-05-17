# Supabase Sync Implementation Strategy

## Overview

This document outlines the strategy for implementing synchronization between CoreData and Supabase for SwiftNote AI. Based on previous sync attempts that encountered issues, we're taking an incremental approach starting with basic metadata sync.

## Previous Issues

1. **Content retrieval issues**: Notes synced to Supabase couldn't be properly retrieved with their full content
2. **JSON format errors**: When creating new notes, sync failed with JSON format errors
3. **Binary data display**: After app reinstallation, notes appeared as binary data instead of readable text
4. **Foreign key constraints**: Notes with folders couldn't be uploaded properly due to foreign key constraints
5. **Data type conversion**: Issues with Data to bytea conversion for fields like original_content

## Implementation Strategy

### Phase 1: Basic One-Way Sync (CoreData → Supabase) - COMPLETED

Started with a minimal implementation to validate the basic connection and data format:

1. **Sync only note metadata**:
   - id (UUID)
   - title (String)
   - timestamp (Date)
   - last_modified (Date)
   - source_type (String)
   - is_favorite (Boolean)
   - processing_status (String)
   - user_id (UUID) - from Supabase Auth session
   - Additional text-based fields (tags, transcript, etc.)

2. **Excluded problematic fields**:
   - original_content (binary data)
   - ai_generated_content (binary data)
   - sections, mind_map, supplementary_materials (binary data)

3. **Implementation Details**:
   - Created `SupabaseSyncService` class for handling sync logic
   - Used a simplified `SimpleSupabaseNote` model to avoid encoding issues
   - Added UI in Settings view to trigger sync and display results
   - Implemented proper error handling and status reporting

4. **Key Learnings**:
   - Direct use of Supabase client methods with Codable objects works best
   - Proper field mapping with CodingKeys is essential
   - Simplified models help avoid JSON encoding/decoding issues
   - Detailed error logging helps identify and fix issues

### Phase 2: Folder and Note Relationship Sync - COMPLETED

Expanded the sync implementation to include folders and maintain proper relationships:

1. **Folder Sync Implementation**:
   - Created `SimpleSupabaseFolder` model with proper field mapping
   - Implemented folder sync before note sync to maintain foreign key relationships
   - Added special handling for the "All Notes" folder
   - Ensured proper color handling for folders

2. **Enhanced Note Sync**:
   - Updated note sync to properly include folder relationships
   - Maintained folder references when syncing notes
   - Ensured notes appear in their correct folders in Supabase

3. **UI Improvements**:
   - Updated sync button text from "Sync Notes to Cloud" to "Sync to Cloud"
   - Added description explaining that both folders and notes are synced
   - Maintained the same feedback mechanisms (progress indicator, success/error messages)

### Phase 3: Binary Data Sync - COMPLETED

Expanded the sync implementation to include binary data fields:

1. **Base64 Encoding for Binary Data**:
   - Implemented Base64 encoding for binary data fields (originalContent, aiGeneratedContent, etc.)
   - Created utility extensions for Data to handle Base64 conversion and size calculations
   - Successfully stored binary data in Supabase's bytea columns without conversion issues

2. **User Control and Size Limits**:
   - Added a toggle in Settings to enable/disable binary data sync
   - Implemented size validation (10MB limit per field) to prevent performance issues
   - Added detailed logging of binary data sizes for monitoring

3. **Enhanced Progress Tracking**:
   - Created a SyncProgress structure to track folder and note sync operations
   - Added progress bar and status messages in the UI during sync
   - Implemented actor-isolated counters for thread-safe progress tracking

4. **UI Improvements**:
   - Added binary data toggle with clear description in Settings
   - Enhanced sync feedback with progress bar and detailed status messages
   - Updated success/error messages to indicate if binary data was included

### Phase 4: Two-Way Sync (Future Implementation)

After one-way sync is stable:

1. **Implement download from Supabase**:
   - Retrieve notes from Supabase to CoreData
   - Handle merging with existing data

2. **Conflict resolution**:
   - Implement "Last Write Wins" strategy using updated_at/last_modified fields
   - Handle sync conflicts gracefully

3. **User Experience Improvements**:
   - Add automatic sync on app launch or note creation
   - Implement background sync
   - Add more detailed sync status reporting

## Data Model Comparison

### CoreData Note Entity
- **Basic Metadata**: id (UUID), title (String), timestamp (Date), lastModified (Date), sourceType (String), isFavorite (Boolean), processingStatus (String)
- **Content Fields**: originalContent (Binary), aiGeneratedContent (Binary)
- **Additional Fields**: citations, duration, keyPoints, mindMap, sections, sourceURL, supplementaryMaterials, tags, transcript, transcriptLanguage, videoId
- **Sync Fields**: syncStatus (String), deletedAt (Date)
- **Relationships**: folder (to Folder), analytics (to QuizAnalytics), quizProgress (to QuizProgress)

### Supabase Notes Table
- **Basic Metadata**: id (UUID), title (text), timestamp (timestamp), last_modified (timestamp), source_type (text), is_favorite (boolean), processing_status (text)
- **Content Fields**: original_content (bytea), ai_generated_content (bytea)
- **Additional Fields**: citations, duration, key_points, mind_map, sections, source_url, supplementary_materials, tags, transcript, language_code, video_id
- **Sync Fields**: sync_status (text), deleted_at (timestamp)
- **Foreign Keys**: folder_id (UUID), user_id (UUID)

### CoreData Folder Entity
- **Basic Fields**: id (UUID), name (String), color (String), timestamp (Date), sortOrder (Integer)
- **Sync Fields**: syncStatus (String), updatedAt (Date), deletedAt (Date)
- **Relationships**: notes (to Note)

### Supabase Folders Table
- **Basic Fields**: id (UUID), name (text), color (text), timestamp (timestamp), sort_order (integer)
- **Sync Fields**: sync_status (text), updated_at (timestamp), deleted_at (timestamp)
- **Foreign Keys**: user_id (UUID)

## Technical Implementation Details

### Phase 1 Implementation (Completed)

We successfully implemented the basic one-way sync with the following components:

1. **SupabaseSyncService Class**:
   - Singleton service for handling sync operations
   - Methods for syncing note metadata to Supabase
   - Error handling and logging

2. **SimpleSupabaseNote Model**:
   - Simplified version of SupabaseNote with only metadata fields
   - Proper CodingKeys for field name mapping
   - Avoids complex binary data fields

3. **UI Integration**:
   - Added to Settings view under "Cloud Sync" section
   - Shows sync status, last sync time, and results
   - Provides user feedback during sync process

4. **Key Implementation Decisions**:
   - Used direct Supabase client methods with Codable objects
   - Implemented proper error handling with detailed logging
   - Stored last sync time in UserDefaults with proper iOS 16+ compatibility

### Phase 2 Implementation (Completed)

We expanded the sync implementation to include folders and maintain proper relationships:

1. **SimpleSupabaseFolder Model**:
   - Created a simplified model for folder data
   - Included all necessary fields with proper CodingKeys
   - Ensured compatibility with Supabase's data structure

2. **Folder Sync Methods**:
   - Implemented `syncFoldersToSupabase` method to sync folders to Supabase
   - Added `fetchFoldersForSync` to get folders from CoreData
   - Added `updateFolderSyncStatus` to update sync status in CoreData

3. **Updated Sync Process**:
   - Modified `syncToSupabase` to sync folders first, then notes
   - Changed `syncNotesMetadataToSupabase` to return a boolean instead of using a completion handler
   - Ensured proper error handling throughout the sync process

4. **Special Handling for "All Notes" Folder**:
   - Added special color handling for the "All Notes" folder
   - Ensured "All Notes" folder is properly synced with a consistent appearance
   - Updated the folder count display to show the correct number of notes

### Phase 3 Implementation (Completed)

We implemented binary data sync with Base64 encoding and enhanced progress tracking:

1. **Data+Base64 Extension**:
   - Created utility methods for Base64 encoding/decoding of binary data
   - Added size calculation methods (bytes, KB, MB) for monitoring
   - Implemented proper error handling for encoding/decoding failures

2. **EnhancedSupabaseNote Model**:
   - Created a model that extends SimpleSupabaseNote with Base64-encoded binary fields
   - Implemented custom initializers to handle fields excluded from CodingKeys
   - Added size metadata fields for monitoring and debugging

3. **Binary Data Sync Methods**:
   - Implemented `syncNotesToSupabase` method that supports binary data
   - Added `syncNoteWithBinaryData` and `syncNoteMetadataOnly` methods
   - Implemented size validation to prevent performance issues with large data

4. **Progress Tracking**:
   - Created a SyncProgress structure to track sync operations
   - Implemented actor-isolated counters for thread-safe progress tracking
   - Added progress publishing for UI updates using Combine

5. **UI Enhancements**:
   - Added binary data toggle in Settings with AppStorage persistence
   - Implemented progress bar and status messages during sync
   - Enhanced feedback with detailed status updates

### Authentication and User ID
- The `user_id` field in Supabase tables comes from Supabase Auth, not CoreData
- We retrieve the authenticated user's ID from the current Supabase session
- This ID is included in all records created in Supabase tables

### Row Level Security (RLS)
- RLS policies are set up to restrict access based on `auth.uid() = user_id`
- Ensures users can only access their own data

### Data Type Handling
- CoreData's Binary fields map to Supabase's bytea type
- CoreData's Date fields map to Supabase's timestamp with time zone
- CoreData's UUID fields map to Supabase's uuid type

### Field Naming Conventions
- CoreData uses camelCase (lastModified)
- Supabase uses snake_case (last_modified)
- We use CodingKeys in Codable models to handle this mapping

### Special Handling for "All Notes" Folder

The "All Notes" folder requires special handling because it's a special view that shows all notes regardless of their folder assignment:

1. **UI Implementation**:
   - Modified `FolderDetailViewModel` to fetch all notes when the "All Notes" folder is selected
   - Updated the note count display to show the correct total number of notes
   - Added a special gray color for the "All Notes" folder to distinguish it from user-created folders

2. **Data Model Considerations**:
   - Each user has their own "All Notes" folder in Supabase
   - The "All Notes" folder is created automatically when a user first uses the app
   - Added code to consolidate multiple "All Notes" folders if they exist

3. **Sync Behavior**:
   - The "All Notes" folder is synced to Supabase like any other folder
   - Notes maintain their folder relationships when synced
   - The app's special behavior for the "All Notes" folder is implemented in the UI layer, not the data layer

### Challenges Overcome

#### Phase 1 & 2 Challenges
1. **JSON Encoding Issues**:
   - Solved by using a simplified model with only metadata fields
   - Avoided complex conversions between different formats

2. **Field Mapping**:
   - Properly mapped fields between CoreData and Supabase
   - Handled differences in field names and types

3. **iOS Compatibility**:
   - Ensured compatibility with iOS 16+ by using proper date storage techniques
   - Avoided using features only available in newer iOS versions

4. **Folder Relationship Issues**:
   - Implemented folder sync before note sync to maintain foreign key relationships
   - Added special handling for the "All Notes" folder
   - Fixed note count display to show the correct number of notes

#### Phase 3 Challenges
1. **Binary Data Conversion**:
   - Solved by using Base64 encoding instead of direct bytea conversion
   - Implemented proper size validation to prevent performance issues

2. **Schema Mismatch Issues**:
   - Resolved by excluding size metadata fields from CodingKeys
   - Implemented custom initializers to handle fields not in the JSON

3. **Swift Concurrency Issues**:
   - Fixed by using actor-isolated counters for thread-safe progress tracking
   - Ensured proper MainActor usage for UI updates

4. **Size Calculation Accuracy**:
   - Corrected size calculation formulas in debug logs
   - Added proper byte-to-MB conversion for accurate reporting

## Future Implementation Recommendations

1. **Phase 4: Two-Way Sync**:
   - Implement download from Supabase to CoreData
   - Add proper conflict resolution with "Last Write Wins" strategy
   - Use updated_at/last_modified fields for determining which version is newer
   - Handle merging of data carefully to avoid data loss

2. **Binary Data Optimization**:
   - Add compression for large binary data fields
   - Implement selective sync for specific binary fields
   - Consider chunked uploads for very large content

3. **User Experience Improvements**:
   - Add automatic sync triggers (app launch, note creation/modification)
   - Implement background sync to avoid blocking the UI
   - Add more detailed sync status reporting and error recovery

4. **Sync Optimization**:
   - Implement incremental sync to only sync changed items
   - Add batch processing for large datasets
   - Optimize network usage and performance

5. **Advanced Features**:
   - Add sync history and version control
   - Implement selective rollback for specific notes
   - Add collaborative editing features
