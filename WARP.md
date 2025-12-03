# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

DevDiary is a native macOS application that automatically tracks daily development work and transforms it into readable summaries. It's a privacy-first, local-only tool that runs in the background to create an automatic "diary" of coding sessions.

**Key Principles:**
- Privacy-First: All data stays local on the Mac (SQLite database)
- Zero-Effort: Runs in the background, no manual tracking needed
- Git-Focused: Primary tracking mechanism is Git commits and repository activity

## Build & Development Commands

### Building
```bash
swift build
```

### Running
```bash
swift run DevDiary
```

### Building for Release
```bash
swift build -c release
```

### Cleaning Build Artifacts
```bash
swift package clean
```

### Updating Dependencies
```bash
swift package update
```

### Generating Xcode Project (if needed)
```bash
swift package generate-xcodeproj
```

## Project Architecture

### Tech Stack
- **Language:** Swift 5.9+
- **Minimum Platform:** macOS 13.0 (Ventura)
- **UI Framework:** SwiftUI
- **Database:** SQLite (via SQLite.swift dependency)
- **Package Manager:** Swift Package Manager

### Core Components (Target Architecture)

The project is structured into the following logical layers:

**Core/**
- `RepositoryWatcher` - Monitors Git repositories for changes
- `FileSystemMonitor` - Uses FSEvents API to track file system changes
- `ActivityTracker` - Detects and groups work sessions (pause >15min = new session)
- `DatabaseManager` - Handles all SQLite operations

**Models/**
- `Project` - Represents tracked Git repositories
- `Session` - Work sessions with timing and project association
- `Commit` - Git commit information (hash, message, author, stats)
- `FileEvent` - File system events (opened, modified, saved)

**Services/**
- `GitService` - Git operations (libgit2 or shell commands TBD)
- `ParserService` - Parses commit messages and extracts meaningful data
- `StatisticsService` - Aggregates data for summaries and reports

**UI/**
- `MenuBarView` - Menu bar icon and quick view dropdown
- `MainWindow` - Main dashboard with tabs (Today, History, Projects, Settings)
- `TodayView` - Real-time view of current session
- `SettingsView` - Configuration and privacy controls

### Database Schema

**Projects Table:**
- id (UUID), name, path, is_tracked, created_at

**Sessions Table:**
- id (UUID), project_id (FK), start_time, end_time, is_active

**Commits Table:**
- id (UUID), session_id (FK), hash, message, author, timestamp, files_changed, additions, deletions

**FileEvents Table:**
- id (UUID), session_id (FK), file_path, event_type (enum), timestamp

## Development Guidelines

### Git Integration Approach
Decision pending between libgit2 (better performance) vs. shell commands (simpler implementation). When implementing, prioritize:
- Background processing to avoid blocking UI
- Caching of repository state
- Only tracking HEAD commits to avoid performance issues with large repos

### File System Monitoring
- Use FSEvents API (not polling) to minimize battery impact
- Implement throttling to prevent excessive event processing
- Auto-exclude: .env files, files with "secret"/"password"/"key" in name, node_modules, .git contents

### Privacy & Security
- All data storage in `~/Library/Application Support/DevDiary/`
- Default retention: 90 days (configurable)
- User must be able to exclude specific repos/folders from tracking
- No network requests - completely offline application

### Session Detection Logic
- Group activities into sessions
- New session starts after >15 minutes of inactivity
- Track active project based on most recent file modifications

### Performance Considerations
- Avoid battery drain through efficient FSEvents usage
- Use background processing for Git operations
- Implement caching for repository information
- Consider throttling for large repositories

## Current State

This is an early-stage project. As of now:
- Basic SwiftUI app structure exists
- Directory structure (Core/, Models/, Services/, UI/) is defined but empty
- SQLite.swift dependency is configured
- No tests are implemented yet

## Future Features (Post-MVP)

- AI-generated summaries using local LLM (llama.cpp)
- Advanced analytics (heatmaps, code velocity, focus time)
- Export formats (Markdown, PDF, JSON)
- Build & test integration
- IDE plugins (Xcode, VS Code, JetBrains)

## Development Language

PRD and some documentation are in German, but code (including comments, variable names, and commit messages) should be in English following Swift/Apple development conventions.
