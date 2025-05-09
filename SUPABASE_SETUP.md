# Supabase Setup for SwiftNote AI

This document provides instructions for setting up the Supabase backend for SwiftNote AI.

## Prerequisites

1. A Supabase account (sign up at [supabase.com](https://supabase.com))
2. A new Supabase project created

## Configuration Steps

### 1. Update Credentials

1. Open `SwiftNote AI/Secrets.swift`
2. Replace the placeholder values with your actual Supabase credentials:
   - `supabaseURL`: Your Supabase project URL (e.g., "https://abcdefghijklm.supabase.co")
   - `supabaseAnonKey`: Your Supabase anon/public key

### 2. Create Database Tables

Execute the following SQL in the Supabase SQL Editor to create the necessary tables:

```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create profiles table (extends the auth.users table)
CREATE TABLE profiles (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  email TEXT NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Create folders table
CREATE TABLE folders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL DEFAULT 'Untitled Folder',
  color TEXT NOT NULL DEFAULT 'blue',
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  user_id UUID REFERENCES auth.users(id) NOT NULL
);

-- Create notes table
CREATE TABLE notes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title TEXT NOT NULL,
  original_content BYTEA,
  ai_generated_content BYTEA,
  source_type TEXT NOT NULL,
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  last_modified TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  is_favorite BOOLEAN DEFAULT FALSE NOT NULL,
  processing_status TEXT NOT NULL DEFAULT 'completed',
  folder_id UUID REFERENCES folders(id),
  summary TEXT,
  key_points TEXT,
  citations TEXT,
  duration DOUBLE PRECISION,
  language_code TEXT,
  user_id UUID REFERENCES auth.users(id) NOT NULL
);

-- Create quiz_analytics table
CREATE TABLE quiz_analytics (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  note_id UUID REFERENCES notes(id) NOT NULL,
  average_score DOUBLE PRECISION DEFAULT 0 NOT NULL,
  completed_quizzes INTEGER DEFAULT 0 NOT NULL,
  correct_answers INTEGER DEFAULT 0 NOT NULL,
  total_questions INTEGER DEFAULT 0 NOT NULL,
  topic_performance BYTEA,
  user_id UUID REFERENCES auth.users(id) NOT NULL
);

-- Create quiz_progress table
CREATE TABLE quiz_progress (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  note_id UUID REFERENCES notes(id) NOT NULL,
  quiz_type TEXT NOT NULL,
  score DOUBLE PRECISION NOT NULL,
  completed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  user_id UUID REFERENCES auth.users(id) NOT NULL
);

-- Create user_settings table
CREATE TABLE user_settings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  analytics_enabled BOOLEAN DEFAULT TRUE NOT NULL,
  biometric_enabled BOOLEAN DEFAULT FALSE NOT NULL,
  theme TEXT DEFAULT 'system' NOT NULL,
  last_sync TIMESTAMP WITH TIME ZONE,
  user_id UUID REFERENCES auth.users(id) NOT NULL UNIQUE
);

-- Create indexes for better performance
CREATE INDEX idx_notes_user_id ON notes(user_id);
CREATE INDEX idx_notes_folder_id ON notes(folder_id);
CREATE INDEX idx_notes_timestamp ON notes(timestamp);
CREATE INDEX idx_notes_source_type ON notes(source_type);
CREATE INDEX idx_folders_user_id ON folders(user_id);
CREATE INDEX idx_quiz_analytics_note_id ON quiz_analytics(note_id);
CREATE INDEX idx_quiz_progress_note_id ON quiz_progress(note_id);
```

### 3. Set Up Row Level Security (RLS) Policies

Execute the following SQL to set up RLS policies:

```sql
-- Enable Row Level Security on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE folders ENABLE ROW LEVEL SECURITY;
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE quiz_analytics ENABLE ROW LEVEL SECURITY;
ALTER TABLE quiz_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;

-- Create policies for profiles
CREATE POLICY "Users can view their own profile" 
  ON profiles FOR SELECT 
  USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile" 
  ON profiles FOR UPDATE 
  USING (auth.uid() = id);

-- Create policies for folders
CREATE POLICY "Users can view their own folders" 
  ON folders FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own folders" 
  ON folders FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own folders" 
  ON folders FOR UPDATE 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own folders" 
  ON folders FOR DELETE 
  USING (auth.uid() = user_id);

-- Create policies for notes
CREATE POLICY "Users can view their own notes" 
  ON notes FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own notes" 
  ON notes FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own notes" 
  ON notes FOR UPDATE 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own notes" 
  ON notes FOR DELETE 
  USING (auth.uid() = user_id);

-- Create policies for quiz_analytics
CREATE POLICY "Users can view their own quiz analytics" 
  ON quiz_analytics FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own quiz analytics" 
  ON quiz_analytics FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own quiz analytics" 
  ON quiz_analytics FOR UPDATE 
  USING (auth.uid() = user_id);

-- Create policies for quiz_progress
CREATE POLICY "Users can view their own quiz progress" 
  ON quiz_progress FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own quiz progress" 
  ON quiz_progress FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

-- Create policies for user_settings
CREATE POLICY "Users can view their own settings" 
  ON user_settings FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own settings" 
  ON user_settings FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own settings" 
  ON user_settings FOR UPDATE 
  USING (auth.uid() = user_id);
```

### 4. Set Up Triggers for User Creation

Execute the following SQL to create triggers that will automatically create user profiles and settings:

```sql
-- Function to create a profile when a new user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user() 
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email)
  VALUES (NEW.id, NEW.email);
  
  INSERT INTO public.user_settings (user_id)
  VALUES (NEW.id);
  
  -- Create default "All Notes" folder
  INSERT INTO public.folders (name, color, sort_order, user_id)
  VALUES ('All Notes', 'blue', 0, NEW.id);
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function when a new user is created
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
```

## Testing the Setup

After completing the setup, you should be able to:

1. Run the app with your Supabase credentials
2. Sign up a new user
3. Create folders and notes
4. Verify that the data is being stored in Supabase

## Troubleshooting

If you encounter issues:

1. Check that your Supabase URL and anon key are correct
2. Verify that all tables and policies have been created correctly
3. Check the Supabase logs for any errors
4. Ensure that the app has internet connectivity
