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

### Phase 1: Basic One-Way Sync (CoreData → Supabase)

Start with a minimal implementation to validate the basic connection and data format:

1. **Sync only basic note metadata**:
   - id (UUID)
   - title (String)
   - timestamp (Date)
   - last_modified (Date)
   - source_type (String)
   - is_favorite (Boolean)
   - processing_status (String)
   - user_id (UUID) - from Supabase Auth session

2. **Exclude problematic fields**:
   - original_content (binary data)
   - ai_generated_content (binary data)
   - Any complex relationships

3. **Testing**:
   - Create test notes in the app
   - Trigger the sync
   - Verify in Supabase console that metadata appears correctly

### Phase 2: Expanded Sync (After Phase 1 Validation)

Once basic metadata sync is working:

1. **Add folder sync**:
   - Sync folders first (due to foreign key constraints)
   - Then sync notes with folder relationships

2. **Add more fields**:
   - Gradually add more fields to the sync
   - Test each addition thoroughly

3. **Implement binary data handling**:
   - Develop and test proper encoding/decoding for binary fields

### Phase 3: Two-Way Sync (Future Implementation)

After one-way sync is stable:

1. **Implement download from Supabase**:
   - Retrieve notes from Supabase to CoreData
   - Handle merging with existing data

2. **Conflict resolution**:
   - Implement "Last Write Wins" strategy using updated_at/last_modified fields
   - Handle sync conflicts gracefully

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

## Technical Implementation Notes

### Authentication and User ID
- The `user_id` field in Supabase tables comes from Supabase Auth, not CoreData
- Must retrieve the authenticated user's ID from the current Supabase session
- This ID must be included in all records created in Supabase tables

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
- Use CodingKeys in Codable models to handle this mapping

### Supabase Recommended Approach
- Use Codable models to decode database responses
- Access data through the `value` property which returns a decoded model
- Example:
  ```swift
  struct NoteModel: Codable {
      var id: UUID
      var title: String
      // other fields
      
      // Custom coding keys if needed
      enum CodingKeys: String, CodingKey {
          case id
          case title
          // other mappings
      }
  }
  ```

## Implementation Recommendations

1. **Use Existing Models**:
   - Leverage the existing `SupabaseNote` model from SupabaseModels.swift
   - Ensure proper CodingKeys for field name mapping

2. **Incremental Testing**:
   - Test with real data but limited scope
   - Verify each step before proceeding

3. **Error Handling**:
   - Implement robust error handling
   - Log sync failures for debugging

4. **Session Management**:
   - Ensure valid authentication before attempting sync
   - Handle authentication errors gracefully

## Next Steps

1. Implement basic one-way sync of note metadata
2. Verify data appears correctly in Supabase
3. Only proceed to more complex sync features after validation
