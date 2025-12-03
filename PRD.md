# DevDiary - Product Requirements Document

**Version:** 0.2  
**Datum:** 2024-12-03  
**Status:** Implementation Ready

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
- **Git Integration:** Shell Commands via Process API
- **Localization:** String Catalogs (Deutsch + English)
- **Distribution:** Direct Download (unsandboxed)
- **Updates:** Sparkle Framework

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

## 9. Technische Entscheidungen (Resolved)

| Frage | Entscheidung | Begründung |
|-------|--------------|------------|
| Git-Integration | Shell Commands | Einfacher zu implementieren, Git ist ohnehin installiert |
| Distribution | Direct Download | Voller Dateisystem-Zugriff ohne Sandbox-Einschränkungen |
| Sandboxing | Unsandboxed | Notwendig für freien Zugriff auf Git-Repos |
| Update Mechanism | Sparkle Framework | Standard für macOS Direct-Download Apps |
| UI-Sprache | Lokalisiert (DE/EN) | Größere Zielgruppe, interne Entwickler benötigen Deutsch |
| FSEvents/File Monitoring | Post-MVP | Reduziert MVP-Komplexität, Git-Tracking reicht für v1.0 |
| IDE-Integration | Post-MVP (v2.0+) | Fokus auf Kernfunktionalität zuerst |

### Offene Fragen (Post-MVP)
- AI-Feature: Lokales Model (llama.cpp) vs. optionale Cloud-API?
- Pricing: Kostenlos vs. Freemium?

---

## 10. Detaillierte Implementierungs-Roadmap

### Milestone 1: Foundation (Woche 1-2)
**Ziel:** Lauffähige App-Struktur mit Datenbank

**M1.1 - Projekt-Setup**
- SwiftUI App mit Menubar-Integration (NSStatusItem)
- App-Icon und grundlegendes Branding
- Lokalisierung Setup (String Catalogs für DE/EN)
- Logging-Infrastruktur (os.log)

**M1.2 - Datenbank-Layer**
- SQLite.swift Integration
- Schema-Migration-System für zukünftige Updates
- DatabaseManager mit CRUD-Operationen
- Models: Project, Session, Commit

**Deliverable:** App startet, zeigt Menubar-Icon, Datenbank ist funktional

---

### Milestone 2: Git Integration (Woche 3-4)
**Ziel:** Commits aus Git-Repositories auslesen

**M2.1 - GitService**
- Shell Command Wrapper (Process API)
- `git log` parsing (Commits mit Hash, Message, Author, Timestamp)
- `git diff --stat` für Additions/Deletions
- Branch-Detection (`git branch --show-current`)
- Error Handling für nicht-Git-Verzeichnisse

**M2.2 - Repository Discovery**
- Scan von Standard-Verzeichnissen: ~/Developer, ~/Projects, ~/Code, ~/Documents
- Rekursive Suche nach .git Ordnern (max. Tiefe: 3)
- Manuelles Hinzufügen von Repos via Drag & Drop oder Folder Picker
- Speicherung in Datenbank mit is_tracked Flag

**M2.3 - Commit Polling**
- Timer-basiertes Polling (alle 60 Sekunden)
- Vergleich mit zuletzt bekanntem Commit-Hash
- Neue Commits in Datenbank speichern
- Background-Thread für Git-Operationen

**Deliverable:** App erkennt Repos, liest Commits, speichert in DB

---

### Milestone 3: Session Management (Woche 5-6)
**Ziel:** Arbeitszeit-Tracking basierend auf Git-Aktivität

**M3.1 - Session-Logik**
- Session startet bei erstem Commit des Tages
- Session endet nach 15 Minuten Inaktivität (konfigurierbar)
- Automatische Zuordnung: Commit → Session → Project
- Berechnung der Session-Dauer

**M3.2 - ActivityTracker**
- Zentrale Komponente für Session-State-Management
- Observer-Pattern für UI-Updates
- Persistierung des aktiven Session-Status (App-Neustart)

**M3.3 - Statistik-Berechnung**
- Tages-Statistiken: Commits, aktive Zeit, Projekte
- Projekt-Statistiken: Commits pro Projekt, Zeit pro Projekt
- StatisticsService für Aggregation

**Deliverable:** Sessions werden automatisch erkannt und getrackt

---

### Milestone 4: Menubar UI (Woche 7-8)
**Ziel:** Quick View mit Tages-Übersicht

**M4.1 - Menubar-Integration**
- NSStatusItem mit Custom Icon
- Popover mit SwiftUI Content
- Keyboard Shortcut zum Öffnen (⌘⇧D)

**M4.2 - Quick View Design**
- Tages-Summary: Zeit, Commits, aktives Projekt
- Letzter Commit mit Message und Zeitstempel
- "Open Dashboard" und "Settings" Buttons
- Live-Updates bei neuen Commits

**M4.3 - Lokalisierung**
- Alle UI-Strings in String Catalog
- Deutsche Übersetzungen
- Plural-Handling (1 Commit vs. 5 Commits)
- Datums-/Zeitformatierung nach Locale

**Deliverable:** Funktionale Menubar-App mit Quick View

---

### Milestone 5: Main Dashboard (Woche 9-10)
**Ziel:** Detaillierte Ansichten und Konfiguration

**M5.1 - Dashboard Window**
- Separates NSWindow (öffnet aus Menubar)
- Tab-Navigation: Today, History, Projects, Settings
- Window-Position merken

**M5.2 - Today View**
- Timeline der heutigen Sessions
- Commit-Liste mit Details (klappbar)
- Projekt-Wechsel visualisiert
- Echtzeit-Updates

**M5.3 - History View**
- Kalender-Navigation (letzte 30 Tage)
- Tages-Auswahl zeigt Details
- Einfache Statistiken pro Tag

**M5.4 - Projects View**
- Liste aller getrackten Repositories
- Toggle: Tracking an/aus
- Statistiken pro Projekt
- "Add Repository" Button

**M5.5 - Settings View**
- Allgemein: Launch at Login, Sprache
- Tracking: Poll-Intervall, Session-Timeout
- Privacy: Excluded Paths, Data Retention
- About: Version, Lizenz, Update-Check

**Deliverable:** Vollständiges Dashboard mit allen Views

---

### Milestone 6: Polish & Beta (Woche 11-12)
**Ziel:** Release-Qualität erreichen

**M6.1 - Stabilität**
- Error Handling für alle Edge Cases
- Crash-freie Nutzung bei fehlerhaften Git-Repos
- Memory Leak Check (Instruments)
- Performance-Optimierung für viele Repos (>20)

**M6.2 - UX Polish**
- Animations und Transitions
- Empty States (keine Commits heute, etc.)
- Onboarding bei erstem Start
- Hilfreiche Tooltips

**M6.3 - Distribution**
- Code Signing mit Developer ID
- Notarization für Gatekeeper
- DMG-Installer erstellen
- Sparkle für Auto-Updates integrieren
- Download-Website / GitHub Releases

**M6.4 - Dokumentation**
- README mit Screenshots
- FAQ / Troubleshooting
- Changelog

**Deliverable:** Beta-Release bereit für externe Tester

---

### Post-MVP Roadmap

**Version 1.1 - File System Monitoring**
- FSEvents Integration
- Tracking welche Dateien bearbeitet wurden
- Erweiterte Session-Detection

**Version 1.2 - Export & Reporting**
- Markdown Export für Stand-ups
- Wochen-/Monats-Reports
- Copy-to-Clipboard für schnelles Teilen

**Version 2.0 - AI Summaries**
- Integration lokaler LLM (llama.cpp / MLX)
- Automatische Zusammenfassung des Arbeitstages
- "Was habe ich diese Woche gemacht?" Feature

**Version 2.1 - Advanced Analytics**
- Produktivitäts-Heatmaps
- Code Velocity Trends
- Focus Time Tracking

---

## 11. Risiken & Mitigation

| Risiko | Impact | Wahrscheinlichkeit | Mitigation |
|--------|---------|-------------------|------------|
| Git-Shell-Commands langsam | Mittel | Mittel | Background-Thread, Caching, nur neue Commits laden |
| Privacy Bedenken der User | Hoch | Mittel | Transparente Kommunikation, Local-First, klare Settings |
| Git-Repos zu groß/langsam | Mittel | Hoch | Limit auf letzte 100 Commits, nur HEAD-Branch |
| Konkurrenz (WakaTime, etc.) | Mittel | Hoch | Differenzierung: Privacy-First, keine Cloud, AI lokal |
| Notarization-Probleme | Mittel | Niedrig | Frühzeitig testen, Apple Developer Account bereit |
| Polling verpasst Commits | Niedrig | Niedrig | 60s Intervall ist ausreichend, User kann manuell refreshen |

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

## 13. Implementierungs-Checkliste

### Milestone 1: Foundation
- [ ] SwiftUI Menubar App Grundstruktur
- [ ] SQLite.swift Datenbank Setup
- [ ] Schema Migration System
- [ ] Lokalisierung Infrastructure (String Catalogs)
- [ ] Models: Project, Session, Commit

### Milestone 2: Git Integration
- [ ] GitService mit Shell Command Wrapper
- [ ] Git Log Parsing
- [ ] Repository Discovery (Standard-Pfade)
- [ ] Manuelles Repo hinzufügen
- [ ] Commit Polling (Timer-basiert)

### Milestone 3: Session Management
- [ ] Session-Logik (Start/Ende/Timeout)
- [ ] ActivityTracker Komponente
- [ ] Statistik-Berechnung

### Milestone 4: Menubar UI
- [ ] NSStatusItem + Popover
- [ ] Quick View mit Tages-Summary
- [ ] Deutsche Übersetzungen
- [ ] Keyboard Shortcut

### Milestone 5: Main Dashboard
- [ ] Dashboard Window
- [ ] Today View mit Timeline
- [ ] History View mit Kalender
- [ ] Projects View
- [ ] Settings View

### Milestone 6: Polish & Beta
- [ ] Error Handling komplett
- [ ] Performance-Optimierung
- [ ] Code Signing + Notarization
- [ ] DMG Installer
- [ ] Sparkle Auto-Updates
- [ ] README + Dokumentation

---

**Dokument Ende**
