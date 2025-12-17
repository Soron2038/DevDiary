# Security Audit Report - DevDiary macOS Application

**Audit Date:** December 5, 2025

## Summary

| Severity | Count |
|----------|-------|
| High | 1 |
| Medium | 8 |
| Low | 4 |
| Informational | 2 |
| **Total** | **15** |

---

## High Severity Issues

### 1. Command Injection - Git Hash Parameters

**File:** `Sources/DevDiary/Services/GitService.swift`
**Lines:** 85-90
**Type:** Code Injection

**Description:** Git commit hash values are passed directly into command arguments without validation. The hash parameter is interpolated directly into the git range specification (`\(hash)..HEAD`).

**Vulnerable Code:**
```swift
func getCommitsSince(hash: String, at path: String, limit: Int = 50) -> [GitCommit] {
    let args = [
        "log",
        "--format=%H%n%s%n%an%n%aI%n---COMMIT_END---",
        "\(hash)..HEAD",  // Direct interpolation of user-controlled data
        "-n", "\(limit)"
    ]
```

**Risk:** While the Process API doesn't execute shell injection directly (arguments are passed as array), a malformed commit hash could cause unexpected git behavior or reveal error information. An attacker with repository access could craft malicious commit hash values.

**Recommendation:**
- Validate that hash matches expected format (40 hex characters for SHA-1 or 64 for SHA-256)
- Use whitelist validation for git hashes before passing to git commands

---

## Medium Severity Issues

### 2. Path Traversal - Repository Path Handling

**File:** `Sources/DevDiary/Core/RepositoryDiscovery.swift`
**Lines:** 68, 77
**Type:** Path Traversal

**Description:** User-supplied paths are accepted and used directly without proper canonicalization. The `addRepository(at path:)` method expands tilde (`~`) but does not resolve symlinks or validate the resulting path.

**Vulnerable Code:**
```swift
func addRepository(at path: String) throws -> Project? {
    let normalizedPath = (path as NSString).expandingTildeInPath
    let repoRoot = gitService.getRepositoryRoot(at: normalizedPath) ?? normalizedPath
```

**Risk:** An attacker could provide paths with `..` components to access repositories outside intended directories. Symlinks could be exploited to monitor repositories in arbitrary locations.

**Recommendation:**
- Call `resolvingSymlinksInPath` on normalized paths
- Implement path containment checks
- Reject paths containing `..` traversal sequences

---

### 3. Missing Input Validation - User Path Input

**File:** `Sources/DevDiary/UI/ProjectsView.swift`
**Lines:** 151-158, 327
**Type:** Input Validation

**Description:** The text field for repository path input has no validation. User input is passed directly to `RepositoryDiscovery.addRepository()` without checking for special characters or malicious patterns.

**Vulnerable Code:**
```swift
TextField("projects.add.path", text: $selectedPath)
    .textFieldStyle(.roundedBorder)
// ...
Button("projects.add.confirm") {
    onAdd(selectedPath)  // Direct pass-through of unvalidated input
    dismiss()
}
.disabled(selectedPath.isEmpty)  // Only checks for empty
```

**Risk:** Malformed paths could cause unexpected behavior or be used to probe filesystem structure.

**Recommendation:**
- Add regex validation for valid file paths
- Check that path exists and is a directory
- Validate Git repository structure before adding

---

### 4. Unsafe Forced Unwrap - Database Path Creation

**File:** `Sources/DevDiary/Core/DatabaseManager.swift`
**Lines:** 66
**Type:** Error Handling

**Description:** Uses forced unwrap on `fileManager.urls()` which could crash if Application Support directory is unavailable.

**Vulnerable Code:**
```swift
let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
```

**Risk:** Application crash on startup if directory lookup fails. No graceful error handling for filesystem issues.

**Recommendation:**
- Handle the optional properly with guard or do-catch
- Provide meaningful error messages when database directory is inaccessible

---

### 5. Missing Commit Hash Validation

**File:** `Sources/DevDiary/Services/GitService.swift`
**Lines:** 158, 324
**Type:** Input Validation

**Description:** Commit hashes from git output are stored directly in the database without format validation. Malicious git repositories could have commits with specially crafted messages or author names.

**Risk:** Commit messages and author fields are user-controlled data from git. Could contain control characters or malformed data that gets stored directly in database.

**Recommendation:**
- Validate commit hash format (exactly 40 hex chars for SHA-1)
- Sanitize or limit message and author field lengths
- Add input validation for git output parsing

---

### 6. Unverified Git Executable Path

**File:** `Sources/DevDiary/Services/GitService.swift`
**Lines:** 177-204
**Type:** Process Execution

**Description:** The `runGitCommand` method uses hardcoded git path `/usr/bin/git` but doesn't verify the file exists or hasn't been replaced.

**Risk:** An attacker with write access to /usr/bin could replace git. No code signing verification of the executable.

**Recommendation:**
- Verify the git executable path exists before running
- Consider using `xcrun git` (Xcode-managed git)
- Add validation that git executable exists

---

### 7. Lack of Database Integrity Checks

**File:** `Sources/DevDiary/Core/DatabaseManager.swift`
**Lines:** 51
**Type:** Data Integrity

**Description:** Database file is created in user's Application Support directory with default permissions. No integrity checking or corruption detection is implemented.

**Risk:** SQLite database can be corrupted by filesystem errors. No verification that database file is legitimate. Default file permissions may expose database to other user accounts.

**Recommendation:**
- Implement database integrity checks on startup
- Set restrictive file permissions (0600) on database file
- Add database validation and recovery mechanisms
- Implement regular integrity checks with `PRAGMA quick_check`

---

### 8. Information Disclosure - Git Command Arguments in Logs

**File:** `Sources/DevDiary/Services/GitService.swift`
**Lines:** 197
**Type:** Information Disclosure

**Description:** Failed git command details including full arguments are logged, potentially exposing sensitive path information.

**Vulnerable Code:**
```swift
logger.debug("Git command failed: git \(arguments.joined(separator: " ")) in \(directory)")
```

**Risk:** Logs contain full paths to user's repositories, revealing directory structure.

**Recommendation:**
- Redact paths from error messages
- Log only the git subcommand without directory paths
- Use generic error descriptions

---

### 9. Unencrypted Sensitive Data Storage

**File:** `Sources/DevDiary/Core/DatabaseManager.swift`
**Lines:** 73
**Type:** Cryptography / Data Storage

**Description:** SQLite database containing commit messages (potentially containing sensitive information) is stored in plaintext without encryption.

**Risk:** Commit messages could contain API keys, credentials, or sensitive information. Database file has default permissions. No encryption at rest.

**Recommendation:**
- Implement SQLite encryption (SQLCipher)
- Or rely on FileVault for encryption
- Document this limitation to users
- Provide secure data deletion option

---

## Low Severity Issues

### 10. Information Disclosure - Paths in Logs

**File:** `Sources/DevDiary/Core/RepositoryDiscovery.swift`
**Lines:** 38, 42
**Type:** Logging

**Description:** File paths (including full user directory structures) are logged at debug level.

**Vulnerable Code:**
```swift
logger.debug("Skipping non-existent directory: \(directory.path)")
logger.debug("Scanning: \(directory.path)")
```

**Risk:** Full paths to user home directory are exposed in logs. Could reveal iCloud drive usage patterns and folder structures.

**Recommendation:**
- Use relative path indicators or generic descriptions in logs
- Redact full paths from user-facing logs

---

### 11. Information Disclosure - Database Path

**File:** `Sources/DevDiary/Core/DatabaseManager.swift`
**Lines:** 49
**Type:** Logging

**Description:** Database file path is logged at info level, exposing the exact location of sensitive user data.

**Vulnerable Code:**
```swift
logger.info("Database path: \(dbPath)")
```

**Risk:** Direct path to user's application support directory is logged.

**Recommendation:**
- Remove or redact database path from log output
- Use generic log messages like "Database initialized"

---

### 12. Insecure Window State Storage

**File:** `Sources/DevDiary/UI/DashboardWindow.swift`
**Lines:** 45-46, 72
**Type:** Data Storage

**Description:** Window frame position is stored in UserDefaults without encryption. While window position itself isn't sensitive, this establishes a pattern of using unencrypted persistent storage.

**Vulnerable Code:**
```swift
if let frameString = UserDefaults.standard.string(forKey: windowFrameKey) {
    window?.setFrame(from: frameString)
}
```

**Risk:** UserDefaults on macOS is stored in plain text plist files. Future sensitive data stored here would be exposed.

**Recommendation:**
- Consider using Keychain for any future sensitive application state
- Add comments noting that only non-sensitive data should use UserDefaults

---

### 13. Unvalidated File Operations

**File:** `Sources/DevDiary/UI/ProjectsView.swift`
**Lines:** 287
**Type:** File Operations

**Description:** Using NSWorkspace to open Finder at arbitrary paths provided by database without validation.

**Vulnerable Code:**
```swift
NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
```

**Risk:** Assumes project.path is always valid. Could attempt to open suspicious or malicious paths.

**Recommendation:**
- Validate path exists before attempting to open
- Catch and handle errors from NSWorkspace operations

---

### 14. Missing Rate Limiting - Polling Operations

**File:** `Sources/DevDiary/Core/CommitPoller.swift`
**Lines:** 31-52
**Type:** Resource Exhaustion

**Description:** No rate limiting on git commands. A user with many repositories could create excessive system load.

**Risk:** Could lead to denial of service through system resource exhaustion. User can set polling interval as low as 30 seconds.

**Recommendation:**
- Implement minimum polling interval enforcement (e.g., 60 seconds)
- Add repository count limits or batching
- Monitor and limit number of concurrent git processes

---

## Informational

### 15. No Authentication Mechanism

**Type:** Access Control

**Description:** The application has no authentication mechanism. Any user account on the system can access the data and modify it.

**Risk:** Multi-user systems may have privacy concerns. No protection against accidental or malicious modification by other users. Data visible to all processes running as the same user.

**Recommendation:**
- Document that data is accessible to all user accounts
- Consider restricting file permissions to current user
- Add optional passphrase protection for data access

---

## Positive Security Findings

The following security best practices were observed:

1. **No Network Communication** - Application correctly implements "100% local" as advertised
2. **No Hardcoded Secrets** - No API keys, passwords, or credentials found
3. **SQL Injection Protection** - Uses SQLite ORM (SQLite.swift) which prevents SQL injection
4. **Memory Safety** - Swift's memory safety prevents buffer overflows
5. **No Third-party Code Execution** - Only uses standard libraries and safe dependencies
6. **Proper Error Handling** - Most error cases are caught and logged
7. **Foreign Key Constraints** - Database properly uses referential integrity
8. **Appropriate Logging Framework** - Uses os.log for secure system logging
9. **No Debug Code in Production** - Code is clean of development debug statements
10. **Minimal Attack Surface** - No web server, no IPC, no plugin system

---

## Dependencies Assessment

| Dependency | Version | Status |
|------------|---------|--------|
| SQLite.swift | 0.15.4 | Safe - Popular, actively maintained |
| swift-toolchain-sqlite | 1.0.4 | Safe - Official Swift package |

**Assessment:** Dependencies are minimal and from reputable sources. No known critical vulnerabilities.

---

## Recommendations Priority

### Immediate (High Priority)
1. Fix command injection vulnerability in GitService.swift

### Short-term (Medium Priority)
2. Implement path validation and canonicalization
3. Add input validation for user-provided paths
4. Fix forced unwrap crash risk
5. Validate git output before database storage
6. Verify git executable existence
7. Add database integrity checks
8. Reduce log verbosity for paths

### Long-term (Low Priority)
9. Consider database encryption
10. Review all logging for information disclosure
11. Add rate limiting for polling operations
12. Document security limitations for users
