# DevDiary - Product Requirements Document

**Version:** 0.1 (Draft)  
**Datum:** 2024-12-03  
**Status:** Initial Draft

---

## 1. Executive Summary

DevDiary ist eine native macOS-App, die automatisch die tägliche Entwicklungsarbeit trackt und in lesbare Zusammenfassungen verwandelt. Entwickler erhalten ein automatisches "Tagebuch" ihrer Coding-Sessions ohne manuellen Aufwand.

### Kernwert
- Automatische Dokumentation der täglichen Arbeit für Stand-ups, Reports oder persönliche Reflexion
- Privacy-First: Alle Daten bleiben lokal auf dem Mac
- Zero-Effort: Läuft im Hintergrund, kein manuelles Tracking nötig

---

## 2. Zielgruppe

### Primary Persona: "Der Solo-Entwickler"
- Arbeitet an mehreren Projekten parallel
- Muss regelmäßig Reports über Fortschritt erstellen (Freelancer, Remote Worker)
- Vergisst oft Details über vergangene Arbeitstage
- Nutzt Git professionell

### Secondary Persona: "Der Team Lead"
- Braucht Übersicht über eigene technische Arbeit neben Management-Tasks
- Muss wöchentliche/monatliche Updates für Stakeholder erstellen
- Schätzt datenbasierte Insights über Arbeitspatterns

---

## 3. Features & Funktionen

### 3.1 MVP Features (Version 1.0)

#### Repository Tracking
- **Auto-Discovery:** Findet automatisch Git-Repos in ~/Developer, ~/Projects, ~/Code
- **Manual Add:** User kann weitere Repos hinzufügen
- **Commit Tracking:** Liest Git-Historie (Commits, Messages, Changed Files)
- **Branch Detection:** Zeigt auf welchem Branch gearbeitet wurde

#### Activity Monitoring
- **File Events:** Trackt welche Dateien geöffnet/bearbeitet/gespeichert wurden
- **Session Detection:** Gruppiert Aktivitäten in Sessions (Pause >15min = neue Session)
- **Active Project:** Erkennt welches Projekt gerade aktiv ist
- **Time Tracking:** Reine Arbeitszeit pro Projekt/Session

#### Daily Summary
- **Timeline View:** Chronologische Übersicht des heutigen Tages
- **Commit List:** Alle Commits mit Messages
- **File Statistics:** Meist bearbeitete Dateien
- **Session Summary:** "3 Sessions, 4.5h produktive Zeit, 12 Commits"

#### UI/UX
- **Menubar App:** Kleines Icon in der Menubar
- **Quick View:** Dropdown mit "Today Summary"
- **Main Window:** Detailliertes Dashboard
- **Notifications:** Optional bei Session-Ende

#### Privacy & Data
- **Local Storage:** SQLite-Datenbank in ~/Library/Application Support
- **No Cloud:** Keine Daten verlassen den Mac
- **Selective Tracking:** User kann Repos/Ordner ausschließen
- **Data Retention:** Konfigurierbare Aufbewahrungsdauer (default: 90 Tage)

### 3.2 Post-MVP Features (Version 2.0+)

#### AI-Generated Summaries
- Integration lokaler LLM (llama.cpp)
- Generiert lesbare Zusammenfassungen aus Commits
- "Heute hast du hauptsächlich an der Authentication gearbeitet und 3 Bugs im User-Service gefixt"

#### Advanced Analytics
- **Heatmaps:** Produktivste Zeiten/Tage
- **Code Velocity:** Commits/Lines per week
- **Project Distribution:** Zeitverteilung über Projekte
- **Focus Time:** Längste unterbrechungsfreie Sessions

#### Export & Reporting
- **Markdown Export:** Für Stand-up Notes
- **Weekly Digest:** Automatische Wochenzusammenfassung
- **PDF Reports:** Schöne Visualisierungen für Stakeholder
- **JSON Export:** Für weitere Analysen

#### Build & Test Integration
- Erkennt Build-Prozesse (Swift, Cargo, npm, etc.)
- Trackt Build-Erfolg/-Fehler
- Test-Execution Detection

#### IDE Integration
- Xcode-Plugin für tiefere Integration
- VS Code Extension
- JetBrains IDEs Support

---

## 4. Technische Architektur

### 4.1 Tech Stack
- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Database:** SQLite (via SQLite.swift)
- **Git Integration:** libgit2 oder direct shell commands
- **File System:** FSEvents API
- **Process Monitoring:** NSWorkspace

### 4.2 Kern-Komponenten

```
DevDiary
├── Core
│   ├── RepositoryWatcher     # Git-Repo monitoring
│   ├── FileSystemMonitor     # FSEvents tracking
│   ├── ActivityTracker       # Session detection & timing
│   └── DatabaseManager       # SQLite operations
├── Models
│   ├── Project
│   ├── Session
│   ├── Commit
│   └── FileEvent
├── Services
│   ├── GitService            # Git operations
│   ├── ParserService         # Commit message parsing
│   └── StatisticsService     # Data aggregation
└── UI
    ├── MenuBarView
    ├── MainWindow
    ├── TodayView
    └── SettingsView
```

### 4.3 Datenmodell

#### Projects
- id (UUID)
- name (String)
- path (String)
- is_tracked (Bool)
- created_at (DateTime)

#### Sessions
- id (UUID)
- project_id (FK)
- start_time (DateTime)
- end_time (DateTime?)
- is_active (Bool)

#### Commits
- id (UUID)
- session_id (FK)
- hash (String)
- message (String)
- author (String)
- timestamp (DateTime)
- files_changed (Int)
- additions (Int)
- deletions (Int)

#### FileEvents
- id (UUID)
- session_id (FK)
- file_path (String)
- event_type (Enum: opened, modified, saved)
- timestamp (DateTime)

---

## 5. User Stories

### MVP Stories

**US-001: Repository Discovery**
Als Entwickler möchte ich, dass die App automatisch meine Git-Repos findet, damit ich nicht manuell konfigurieren muss.

**US-002: Heute-Übersicht**
Als Entwickler möchte ich schnell sehen was ich heute gemacht habe, damit ich im Stand-up berichten kann.

**US-003: Commit-Historie**
Als Entwickler möchte ich alle meine heutigen Commits mit Messages sehen, damit ich meinen Fortschritt nachvollziehen kann.

**US-004: Privacy Control**
Als Entwickler möchte ich bestimmte Repos vom Tracking ausschließen können, damit private/sensitive Projekte nicht getrackt werden.

**US-005: Session-Tracking**
Als Entwickler möchte ich sehen wie lange ich an welchem Projekt gearbeitet habe, damit ich meine Zeit besser einschätzen kann.

### Post-MVP Stories

**US-006: AI Summary**
Als Entwickler möchte ich eine automatisch generierte Zusammenfassung meines Arbeitstages, damit ich Reports schneller erstellen kann.

**US-007: Weekly Report**
Als Freelancer möchte ich einen wöchentlichen Report exportieren können, damit ich meinen Kunden Updates schicken kann.

**US-008: Productivity Insights**
Als Entwickler möchte ich sehen zu welchen Zeiten ich am produktivsten bin, damit ich meinen Arbeitsalltag optimieren kann.

---

## 6. UI/UX Konzept

### 6.1 Menubar Icon
- Kleines Codier-Symbol (</> oder 📝)
- Badge mit Anzahl heutiger Commits
- Klick öffnet Quick View Dropdown

### 6.2 Quick View Dropdown
```
┌─────────────────────────────────┐
│ ⚡ DevDiary                      │
├─────────────────────────────────┤
│ Today's Summary                 │
│                                 │
│ 🕐 3h 24min                     │
│ 📝 12 commits                   │
│ 📂 MainProject                  │
│                                 │
│ Last commit:                    │
│ "Fix login validation bug"      │
│ 14 minutes ago                  │
│                                 │
│ [Open Dashboard]  [Settings]    │
└─────────────────────────────────┘
```

### 6.3 Main Dashboard
Tabs:
- **Today:** Live-View der aktuellen Session
- **History:** Timeline der letzten 7/30 Tage
- **Projects:** Übersicht aller getrackten Projekte
- **Settings:** Konfiguration

---

## 7. Sicherheit & Privacy

### Grundprinzipien
1. **Local First:** Keine Daten verlassen den Mac
2. **User Control:** Volle Kontrolle über was getrackt wird
3. **Transparent:** Klare Kommunikation welche Daten gesammelt werden
4. **Secure Storage:** Datenbank mit File Permissions geschützt

### Ausschluss-Regeln (Auto)
- Keine .env Files
- Keine Dateien mit "secret", "password", "key" im Namen
- Keine node_modules, .git Ordner-Inhalte
- Kein Tracking von non-Code Files (außer konfiguriert)

### Opt-In für sensible Features
- Analytics/Statistics: Default ON
- AI Summaries: Default OFF (Privacy-bewusste User)
- Commit Message Reading: Default ON

---

## 8. Success Metrics (KPIs)

### MVP Success
- 100+ Beta-Tester innerhalb 4 Wochen
- 70%+ nutzen die App täglich
- Durchschnittliche Session-Länge: >30min/Tag
- User Feedback Score: >4/5

### Engagement
- Daily Active Users (DAU)
- Commits tracked per user/day
- Feature usage (welche Views werden geöffnet)

### Qualitative Metrics
- "Hat dir DevDiary Zeit gespart?" - Target: 80% Yes
- "Würdest du DevDiary weiterempfehlen?" - Target: NPS >50

---

## 9. Offene Fragen

1. **Git-Integration:** libgit2 vs. Shell Commands? (Performance vs. Einfachheit)
2. **AI-Feature:** Lokales Model oder optionale Cloud-API als Fallback?
3. **Pricing:** Kostenlos vs. Freemium (AI-Features kostenpflichtig)?
4. **Distribution:** Mac App Store vs. Direct Download vs. Homebrew?
5. **Update Mechanism:** Sparkle Framework oder manuell?
6. **Sandboxing:** App Store-kompatibel (sandboxed) oder unrestricted?
7. **IDE-Integration:** Notwendig für MVP oder erst v2.0?

---

## 10. Roadmap (Grob)

### Phase 1: MVP (3-4 Monate)
- Woche 1-2: Architecture & Core Setup
- Woche 3-4: Repository Tracking Implementation
- Woche 5-6: File System Monitoring
- Woche 7-8: Database & Models
- Woche 9-10: UI Development (Menubar + Main Window)
- Woche 11-12: Testing & Bug Fixing
- Woche 13-14: Beta Release

### Phase 2: Polish & Feedback (1-2 Monate)
- Beta-Testing mit 50-100 Entwicklern
- Bug Fixes & UX Improvements
- Performance Optimization

### Phase 3: AI Features (2-3 Monate)
- LLM Integration
- Summary Generation
- Advanced Analytics

### Phase 4: Launch (1 Monat)
- Marketing Materials
- Documentation
- Public Release

---

## 11. Risiken & Mitigation

| Risiko | Impact | Wahrscheinlichkeit | Mitigation |
|--------|---------|-------------------|------------|
| Zu hoher Battery Drain | Hoch | Mittel | FSEvents nutzen statt Polling, Throttling |
| Privacy Bedenken der User | Hoch | Mittel | Transparente Kommunikation, Local-First |
| Git-Repos zu groß/langsam | Mittel | Hoch | Caching, nur HEAD-Commits, Background Processing |
| Konkurrenz (WakaTime, etc.) | Mittel | Hoch | Fokus auf Git-Integration + AI Summaries |
| Sandboxing-Limitations | Hoch | Mittel | Entscheidung: Kein App Store oder Restricted Features |

---

## 12. Dependencies & Annahmen

### Technische Dependencies
- macOS 13.0+ (Ventura)
- Git installiert auf dem System
- Swift 5.9+ (Xcode 15+)

### User Annahmen
- Nutzt Git für Versionskontrolle
- Arbeitet primär an einem Mac
- Hat Grundverständnis für Terminal/Git
- Ist bereit Background-App laufen zu lassen

### Business Annahmen
- Es gibt Bedarf für automatisches Work Tracking
- Entwickler sind bereit für Productivity Tools zu zahlen (Post-MVP)
- Local-First ist ein Selling Point vs. Cloud-basierte Tools

---

## Nächste Schritte

1. ✅ PRD erstellen
2. ⏳ Feedback einholen & iterieren
3. ⏳ Technische Machbarkeitsstudie (FSEvents + libgit2)
4. ⏳ UI Mockups erstellen
5. ⏳ Prototype: Minimale Version mit Repo-Discovery + Simple Timeline
6. ⏳ Architecture finalisieren
7. ⏳ Development starten

---

**Dokument Ende**
