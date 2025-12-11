# Feature: GitHub Integration & Project Management

**Version:** 0.1  
**Datum:** 2024-12-11  
**Status:** Draft  
**Abhängigkeiten:** PRD.md (MVP abgeschlossen)

---

## 1. Übersicht

Dieses Dokument beschreibt die Erweiterung von DevDiary um:
1. **Projekt-Management Verbesserungen** - Entfernen von Projekten aus der Überwachung
2. **GitHub-Integration** - Optionale Verbindung zu GitHub für erweiterte Funktionen

### Kernprinzipien
- **Freiwillig:** GitHub-Verknüpfung ist vollständig optional
- **Privacy-First:** Tokens werden sicher im macOS Keychain gespeichert
- **Offline-First:** App funktioniert vollständig ohne GitHub-Verbindung
- **Erweiterbar:** Architektur ermöglicht spätere Integration weiterer Git-Dienste (GitLab, Bitbucket)

---

## 2. Problemstellung

### 2.1 Fehlende Projekt-Entfernung (Bug/Missing Feature)
**Aktueller Zustand:** In `ProjectsView.swift` können Projekte:
- ✅ Hinzugefügt werden (manuell oder via Auto-Discovery)
- ✅ Tracking ein/ausgeschaltet werden (Toggle)
- ❌ **NICHT** aus der Liste entfernt werden

**Auswirkung:** User können irrtümlich hinzugefügte oder nicht mehr existierende Projekte nicht aus der Datenbank entfernen.

### 2.2 Keine Remote-Repository Übersicht
**Aktueller Zustand:** DevDiary kennt nur lokale Git-Repositories.

**Gewünschte Funktionen:**
- Übersicht aller GitHub-Repositories des Users
- Erkennen welche Remote-Repos bereits lokal vorhanden sind
- Schnelles Klonen von Remote-Repos

---

## 3. Feature: Projekt entfernen

### 3.1 User Story
> Als Entwickler möchte ich Projekte aus DevDiary entfernen können, damit meine Projektliste übersichtlich bleibt und keine verwaisten Einträge enthält.

### 3.2 Implementierung

**UI-Änderungen in `ProjectsView.swift`:**
- Context Menu auf Projekt-Zeile mit "Entfernen" Option
- Alternativ: Delete-Button in `ProjectDetailView`
- Bestätigungsdialog vor dem Entfernen

**Logik:**
- Projekt wird aus der Datenbank gelöscht (`DatabaseManager.deleteProject()` existiert bereits)
- Zugehörige Sessions und Commits bleiben optional erhalten (konfigurierbar)
- Lokale Dateien werden NICHT angetastet

**Lokalisierung:**
- `projects.remove` - "Entfernen" / "Remove"
- `projects.remove.confirm.title` - "Projekt entfernen?" / "Remove project?"
- `projects.remove.confirm.message` - "Das Projekt wird aus DevDiary entfernt. Die lokalen Dateien bleiben unverändert."

### 3.3 Datenschutz-Optionen
Beim Entfernen eines Projekts:
- [ ] "Auch Session-Historie löschen" (Default: aus)

---

## 4. Feature: GitHub-Integration

### 4.1 User Stories

**US-GH-001: GitHub verbinden**
> Als Entwickler möchte ich mein GitHub-Konto mit DevDiary verbinden können, damit ich eine Übersicht meiner Remote-Repositories erhalte.

**US-GH-002: Remote-Repos anzeigen**
> Als Entwickler möchte ich sehen welche meiner GitHub-Repos lokal vorhanden sind und welche nur remote existieren.

**US-GH-003: Repo klonen**
> Als Entwickler möchte ich ein Remote-Repo direkt aus DevDiary klonen können, um es dann zu tracken.

**US-GH-004: Verbindung trennen**
> Als Entwickler möchte ich die GitHub-Verbindung jederzeit trennen können, wobei alle Tokens sicher gelöscht werden.

### 4.2 Architektur

#### Neue Komponenten

```
Services/
├── GitService.swift           # (existiert)
├── GitHubService.swift        # NEU - GitHub API Client
└── KeychainService.swift      # NEU - Token-Verwaltung

Models/
├── Project.swift              # (existiert)
├── GitHubAccount.swift        # NEU - Verknüpftes GitHub-Konto
└── RemoteRepository.swift     # NEU - GitHub-Repository Info

UI/
├── SettingsView.swift         # (erweitern)
├── GitHubConnectionView.swift # NEU - OAuth Flow UI
└── RemoteReposView.swift      # NEU - Remote-Repos Übersicht
```

#### Datenmodell-Erweiterungen

**GitHubAccounts Table (NEU):**
- id (UUID)
- username (String)
- avatar_url (String?)
- connected_at (DateTime)
- last_sync (DateTime?)

**RemoteRepositories Table (NEU):**
- id (UUID)
- github_account_id (FK)
- github_id (Int) - GitHub's Repository ID
- name (String)
- full_name (String) - "owner/repo"
- clone_url (String)
- is_private (Bool)
- local_project_id (FK?, nullable) - Verknüpfung zu lokalem Projekt
- last_synced (DateTime)

**Projects Table (erweitern):**
- remote_repository_id (FK?, nullable) - Verknüpfung zu Remote-Repo

### 4.3 OAuth-Implementierung

#### Authentifizierungs-Flow
1. User klickt "Mit GitHub verbinden" in Settings
2. App öffnet GitHub OAuth URL im Standard-Browser
3. User autorisiert die App auf github.com
4. GitHub leitet zu Custom URL Scheme zurück: `devdiary://oauth/github?code=...`
5. App tauscht Code gegen Access Token
6. Token wird im macOS Keychain gespeichert

#### OAuth App Konfiguration (github.com)
- **Application name:** DevDiary
- **Homepage URL:** https://github.com/[repo-url]
- **Authorization callback URL:** `devdiary://oauth/github`
- **Scopes benötigt:** `repo` (für private Repos), `read:user`

#### Sicherheit
- Access Token nur im macOS Keychain speichern
- Client Secret NICHT in der App hardcoden (Device Flow oder Public Client nutzen)
- Token bei Verbindungstrennung sicher löschen
- Refresh Token Support für langfristige Verbindung

### 4.4 GitHub API Endpoints

**Benötigte Endpoints:**

| Endpoint | Zweck |
|----------|-------|
| `GET /user` | User-Info nach Login |
| `GET /user/repos` | Alle Repos des Users (inkl. private) |
| `GET /repos/{owner}/{repo}` | Details zu einem Repo |

**API-Limits beachten:**
- Authenticated: 5.000 Requests/Stunde
- Caching implementieren
- Pagination für viele Repos

### 4.5 UI/UX Design

#### Settings → Accounts (Neue Sektion)
```
┌─────────────────────────────────────────────┐
│ 🔗 Verknüpfte Konten                        │
├─────────────────────────────────────────────┤
│                                             │
│   [GitHub Logo]  GitHub                     │
│                  Nicht verbunden            │
│                  [Mit GitHub verbinden]     │
│                                             │
│   - - - - - - - - - - - - - - - - - - - -  │
│                                             │
│   [GitLab Logo]  GitLab       (Bald verfügbar)
│   [Bitbucket]    Bitbucket    (Bald verfügbar)
│                                             │
└─────────────────────────────────────────────┘
```

#### Nach erfolgreicher Verbindung
```
┌─────────────────────────────────────────────┐
│ 🔗 Verknüpfte Konten                        │
├─────────────────────────────────────────────┤
│                                             │
│   [Avatar]  @username                       │
│             Verbunden seit 11.12.2024       │
│             42 Repositories                 │
│                                             │
│   [Synchronisieren]  [Verbindung trennen]   │
│                                             │
└─────────────────────────────────────────────┘
```

#### Projects View → Neuer Tab "Remote"
```
┌─────────────────────────────────────────────┐
│ [Lokal]  [Remote]                           │
├─────────────────────────────────────────────┤
│                                             │
│ 🔒 private-project                          │
│    ✅ Lokal vorhanden: ~/Code/private-project
│                                             │
│ 📂 public-website                           │
│    ⬇️ Nicht lokal  [Klonen]                 │
│                                             │
│ 🔒 secret-api                               │
│    ⬇️ Nicht lokal  [Klonen]                 │
│                                             │
└─────────────────────────────────────────────┘
```

### 4.6 Sync-Logik

**Automatischer Sync:**
- Bei App-Start (wenn GitHub verbunden)
- Alle 30 Minuten im Hintergrund
- Manuell per "Synchronisieren" Button

**Lokale Verknüpfung erkennen:**
1. Remote-Repos laden von GitHub API
2. Für jedes Remote-Repo:
   - Prüfen ob `clone_url` oder `full_name` in lokalem Projekt-Remote vorkommt
   - Git-Remote-URLs der lokalen Projekte auslesen: `git remote get-url origin`
3. Verknüpfungen in `remote_repository_id` speichern

---

## 5. Implementierungs-Roadmap

### Phase 1: Projekt entfernen (1-2 Tage)
- [ ] Context Menu in ProjectRow
- [ ] Bestätigungsdialog
- [ ] Lokalisierungs-Strings
- [ ] Optional: Checkbox "Session-Historie löschen"

### Phase 2: Keychain & OAuth Infrastruktur (3-4 Tage)
- [ ] KeychainService implementieren
- [ ] URL Scheme `devdiary://` registrieren (Info.plist)
- [ ] OAuth Flow mit ASWebAuthenticationSession
- [ ] GitHub OAuth App erstellen und konfigurieren

### Phase 3: GitHub API Client (2-3 Tage)
- [ ] GitHubService mit URLSession
- [ ] Models: GitHubAccount, RemoteRepository
- [ ] Datenbank-Migration für neue Tabellen
- [ ] Error Handling & Rate Limiting

### Phase 4: UI Integration (3-4 Tage)
- [ ] Settings → Accounts Sektion
- [ ] GitHubConnectionView (OAuth Flow)
- [ ] Projects → Remote Tab
- [ ] Clone-Funktionalität

### Phase 5: Polish & Testing (2-3 Tage)
- [ ] Lokalisierung (DE/EN)
- [ ] Edge Cases (Token expired, API errors, etc.)
- [ ] Offline-Handling
- [ ] Dokumentation aktualisieren

**Geschätzter Gesamtaufwand:** 11-16 Tage

---

## 6. Zukünftige Erweiterungen

### 6.1 Weitere Git-Dienste
- **GitLab** - Ähnliche OAuth-Integration
- **Bitbucket** - Atlassian OAuth
- **Self-hosted** - Support für Custom-URLs

### 6.2 Erweiterte GitHub-Features
- Pull Request Übersicht
- Issues anzeigen
- Commit-History mit GitHub vergleichen
- GitHub Actions Status

### 6.3 Projekt-Synchronisation
- Automatisches Klonen bei erstem Commit
- Remote-URL aus Projekt-Pfad ableiten

---

## 7. Offene Fragen

1. **OAuth App Hosting:** Wo wird die GitHub OAuth App registriert?
   - Persönlicher Account des Entwicklers?
   - Dedizierter DevDiary-Account?

2. **Client Secret Handling:** 
   - Device Flow (kein Secret nötig) vs. Standard OAuth?
   - Empfehlung: Device Flow für Desktop-Apps

3. **Daten bei Trennung:**
   - Remote-Repo-Daten löschen oder behalten?
   - Empfehlung: User-Wahl mit Checkbox

4. **Multi-Account Support:**
   - Mehrere GitHub-Konten gleichzeitig?
   - Initial: Nein, ein Konto pro Dienst

---

**Dokument Ende**
