# SwiftNote AI - Project Structure

## 📁 **Two-Level Folder Organization**

This document outlines the organized folder structure for SwiftNote AI, designed for clarity, maintainability, and scalability.

### **Folder Structure Overview**

```
SwiftNote AI/
├── Info.plist                 # App configuration (Xcode required)
├── SwiftNote_AI.entitlements  # App entitlements (Xcode required)
├── SwiftNote_AI.xcdatamodeld/ # CoreData model (Xcode required)
├── Assets.xcassets/           # App assets (Xcode required)
├── Preview Content/           # Preview assets (Xcode required)
├── App/                       # Application entry point and source
├── Core/                      # Core app infrastructure
├── Models/                    # Data models and structures
├── Views/                     # SwiftUI views and UI components
├── ViewModels/                # View logic and state management
├── Services/                  # External service integrations
├── Sync/                      # Supabase sync system (refactored)
├── Authentication/            # User authentication and security
├── Components/                # Reusable UI components and styles
├── Utilities/                 # Helper classes and utility functions
├── Extensions/                # Swift extensions
├── Documentation/             # Project documentation
├── Resources/                 # Additional resources
└── Config/                    # Configuration files
```

## 📂 **Detailed Folder Contents**

### **Root Directory** - Build & Configuration Files
- `Info.plist` - App configuration and permissions (required by Xcode)
- `SwiftNote_AI.entitlements` - App entitlements and capabilities (required by Xcode)
- `SwiftNote_AI.xcdatamodeld/` - CoreData model definitions (required by Xcode)
- `Assets.xcassets/` - App assets and resources (required by Xcode)
- `Preview Content/` - SwiftUI preview assets (required by Xcode)

### **App/** - Application Foundation
- `SwiftNote_AIApp.swift` - App entry point and lifecycle
- `ContentView.swift` - Main application content view
- `Secrets.swift` - API keys and sensitive configuration

### **Core/** - Infrastructure
- `Persistence.swift` - CoreData stack and persistence layer
- `Theme.swift` - App-wide theming and styling
- `SupabaseConfig.swift` - Supabase configuration and setup

### **Models/** - Data Structures
- `SyncDataModels.swift` - Sync-related data models
- `SupabaseModels.swift` - Supabase entity models
- `ChatModels.swift` - Chat and conversation models
- `QuizModels.swift` - Quiz and assessment models
- `StudyModels.swift` - Study session models
- `NoteCardModels.swift` - Note card display models
- `LanguageModel.swift` - Language and localization models

### **Views/** - User Interface
- `HomeViewModel.swift` - Main dashboard view model
- `NoteDetailsView.swift` - Individual note display and editing
- `FolderDetailView.swift` - Folder contents and management
- `FolderListView.swift` - Folder navigation and organization
- `AudioRecordingView.swift` - Audio recording interface
- `AudioPlayerView.swift` - Audio playback controls
- `AudioUploadView.swift` - Audio file upload interface
- `TextUploadView.swift` - Text content upload
- `WebLinkImportView.swift` - Web content import
- `YoutubeView.swift` - YouTube video import
- `ScanTextView.swift` - OCR text scanning
- `SettingsView.swift` - App settings and preferences
- `PrivacySettingsView.swift` - Privacy and security settings
- `AppLockView.swift` - App lock authentication
- `AppLockWrapper.swift` - App lock state management
- `NotificationView.swift` - In-app notifications
- `NoteStudyTab.swift` - Study mode interface
- `QuizTabView.swift` - Quiz and assessment interface
- `NoteListCards.swift` - Note card display components

### **ViewModels/** - Business Logic
- `AudioPlayerViewModel.swift` - Audio playback logic
- `ChatViewModel.swift` - Chat interaction logic
- `FlashcardsViewModel.swift` - Flashcard study logic
- `QuizGeneratorViewModel.swift` - Quiz generation logic
- `QuizViewModel.swift` - Quiz interaction logic
- `ReadTabViewModel.swift` - Reading mode logic
- `TranscriptViewModel.swift` - Transcript processing logic
- `WaveformViewModel.swift` - Audio waveform visualization

### **Services/** - External Integrations
- `SupabaseService.swift` - Base Supabase client and operations
- `AIProxyService.swift` - AI service proxy and management
- `AudioTranscriptionService.swift` - Audio-to-text conversion
- `NoteGenerationService.swift` - AI-powered note generation
- `TranscriptionService.swift` - General transcription services
- `WebContentScraperService.swift` - Web content extraction
- `WebLinkService.swift` - Web link processing
- `YouTubeService.swift` - YouTube API integration
- `YouTubeTranscriptService.swift` - YouTube transcript extraction
- `PDFExportService.swift` - PDF generation and export

### **Sync/** - Synchronization System
- `SupabaseSyncService.swift` - Main sync orchestrator (689 lines)
- `NoteSyncManager.swift` - Note sync operations (1,198 lines)
- `FolderSyncManager.swift` - Folder sync operations
- `SyncTransactionManager.swift` - Transaction management
- `NetworkRecoveryManager.swift` - Network resilience and retry logic
- `ProgressUpdateCoordinator.swift` - Sync progress tracking

### **Authentication/** - Security & Auth
- `AuthenticationManager.swift` - Core authentication logic
- `AuthenticationView.swift` - Login/signup interface
- `AuthenticationWrapper.swift` - Auth state management
- `AuthProfileView.swift` - User profile management
- `EmailConfirmationView.swift` - Email verification
- `AppleSignInButton.swift` - Apple Sign-In integration
- `GoogleSignInButton.swift` - Google Sign-In integration
- `BiometricAuthManager.swift` - Face ID/Touch ID authentication

### **Components/** - Reusable UI
- `SharedComponents.swift` - Common UI components
- `InteractiveComponents.swift` - Interactive UI elements
- `LayoutComponents.swift` - Layout and container components
- `FeedbackComponents.swift` - User feedback UI
- `CustomButtonStyle.swift` - Custom button styling
- `CustomInput.swift` - Custom input components
- `NoteFolderDropDelegate.swift` - Drag and drop functionality

### **Utilities/** - Helper Functions
- `NotePersistenceManager.swift` - Note persistence utilities
- `TranscriptProcessor.swift` - Transcript processing utilities
- `YouTubeTranscriptProcessor.swift` - YouTube-specific processing
- `TranscriptSegment.swift` - Transcript segmentation
- `CleanupUtilities.swift` - Data cleanup utilities
- `SoftDeleteTest.swift` - Testing and validation utilities

### **Extensions/** - Swift Extensions
- `Data+Base64.swift` - Data encoding/decoding extensions

### **Documentation/** - Project Documentation
- `REFACTORING_BREAKDOWN.md` - Sync system refactoring documentation
- `Supabase_Sync_Implementation_Strategy.md` - Sync implementation guide
- `Supabase_Sync_Issues_Tracking.md` - Known issues and solutions
- `product-spec-v2.md` - Product specifications
- `ColorAssetsDefinition.txt` - Color asset definitions
- `PROJECT_STRUCTURE.md` - This file

### **Resources/** - Additional Resources
- *(Build-related assets moved to root for Xcode compatibility)*

### **Config/** - Configuration
- `YouTubeConfig.swift` - YouTube API configuration

## 🎯 **Benefits of This Structure**

### **Developer Experience**
- **Quick Navigation**: Find files instantly by category
- **Clear Ownership**: Each folder has a specific responsibility
- **Scalable Growth**: Easy to add new features without clutter

### **Code Maintainability**
- **Logical Grouping**: Related functionality is co-located
- **Separation of Concerns**: UI, logic, and data are clearly separated
- **Reduced Complexity**: No more 80+ files in root directory

### **Team Collaboration**
- **Consistent Organization**: Everyone knows where to find/place files
- **Reduced Conflicts**: Changes are isolated to specific areas
- **Easier Code Reviews**: Reviewers can focus on relevant folders

## 📊 **Migration Impact**

### **Before Organization**
- **Root Directory**: 80+ files in single folder
- **Navigation**: Difficult to find specific functionality
- **Maintenance**: Hard to understand code relationships

### **After Organization**
- **Structured Folders**: 13 logical categories
- **Clear Hierarchy**: Two-level maximum depth
- **Professional Layout**: Industry-standard organization

## 🔧 **Implementation Notes**

This structure was implemented as part of the major sync system refactoring that:
- Reduced `SupabaseSyncService.swift` from 3,007 to 689 lines (77.1% reduction)
- Extracted 6 specialized managers totaling 2,509 lines
- Maintained full functionality and Swift 6 compliance
- Achieved zero compilation errors

## ✅ **Implementation Status: COMPLETED**

**Date Implemented**: December 2024
**Status**: ✅ Successfully organized all 100+ files into logical folder structure
**Compilation**: ✅ Zero errors after reorganization
**Approach**: Hybrid structure - Xcode build files in root, source code organized in folders
**Benefits Achieved**:
- 📁 Clean two-level folder hierarchy for source code
- 🔍 Easy file navigation and discovery
- 🏗️ Professional project structure
- 📈 Improved maintainability and scalability
- ⚙️ Xcode compatibility maintained

The organization supports the refactored architecture while providing a clean, maintainable codebase for future development.

## 🎯 **Quick Navigation Guide**

- **Need to modify app startup?** → `App/`
- **Working on UI components?** → `Views/` or `Components/`
- **Adding business logic?** → `ViewModels/` or `Services/`
- **Sync system changes?** → `Sync/`
- **Authentication features?** → `Authentication/`
- **Data model updates?** → `Models/` or `Core/`
- **Adding utilities?** → `Utilities/` or `Extensions/`
- **Documentation updates?** → `Documentation/`
