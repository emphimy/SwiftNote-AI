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

### Phase 2: Expanded Sync (Next Steps)

Once basic metadata sync is working:

1. **Add folder sync**:
   - Sync folders first (due to foreign key constraints)
   - Then sync notes with folder relationships

2. **Add more fields**:
   - Gradually add more fields to the sync
   - Test each addition thoroughly

3. **Implement binary data handling**:
   - Develop and test proper encoding/decoding for binary fields
   - Consider Base64 encoding for binary data if bytea conversion is problematic

### Phase 3: Two-Way Sync (Future Implementation)

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

### Challenges Overcome
1. **JSON Encoding Issues**:
   - Solved by using a simplified model with only metadata fields
   - Avoided complex conversions between different formats

2. **Field Mapping**:
   - Properly mapped fields between CoreData and Supabase
   - Handled differences in field names and types

3. **iOS Compatibility**:
   - Ensured compatibility with iOS 16+ by using proper date storage techniques
   - Avoided using features only available in newer iOS versions

## Future Implementation Recommendations

1. **Folder Sync Implementation**:
   - Create a similar SimpleSupabaseFolder model
   - Sync folders before notes due to foreign key constraints
   - Update note sync to include folder relationships

2. **Binary Data Handling**:
   - Consider Base64 encoding for binary data fields
   - Test with small binary data first before scaling up
   - Implement proper error handling for binary data conversion

3. **Two-Way Sync**:
   - Implement proper conflict resolution with "Last Write Wins" strategy
   - Use updated_at/last_modified fields for determining which version is newer
   - Handle merging of data carefully to avoid data loss

4. **User Experience Improvements**:
   - Add automatic sync triggers (app launch, note creation/modification)
   - Implement background sync to avoid blocking the UI
   - Add more detailed sync status reporting and error recovery
