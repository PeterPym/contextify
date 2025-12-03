# Tech Brief: macOS App Sandbox, Database Storage, and User Data Guidelines

**Date:** December 2025
**Context:** Contextify App Store rejection under Guideline 2.4.5(i)
**Research scope:** Official Apple documentation, developer forums, Stack Overflow (2024-2025)

---

## Executive Summary

Apple's App Sandbox creates a complex distinction between "app data" and "user data" that is not always clear-cut. While Apple's own documentation states that containers are appropriate for "databases, caches, and other app-specific data," App Review may classify databases containing user-generated content as "user data" requiring user-accessible storage.

**Key finding:** The distinction hinges on whether the data is:
- **App-internal** (caches, preferences, indexes) → Container is appropriate
- **User-owned content** (documents the user creates/edits) → User-selected location required

---

## 1. App Sandbox Architecture

### 1.1 Container Structure

When a sandboxed app runs, macOS creates a container at:
```
~/Library/Containers/<bundle-id>/Data/
```

This container mirrors a home directory structure:
```
Data/
├── Documents/
├── Library/
│   ├── Application Support/
│   ├── Caches/
│   └── Preferences/
└── ...
```

**Source:** [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)

### 1.2 Container Access Rules

- The container is **hidden** from users (not visible in Finder by default)
- Only the owning app can access its container (enforced via ACL tied to code signature)
- macOS Sonoma (14.0) and Sequoia (15.0) added additional protections requiring user consent for cross-app container access

**Source:** [What are all those Containers? – MacMegasite (2024)](https://macmegasite.com/2024/08/05/what-are-all-those-containers/)

### 1.3 What Apple Says Belongs in the Container

From Apple's App Sandbox Design Guide:

> "The container is in a hidden location, and so users do not interact with it directly. Specifically, **the container is not for user documents**. It is for files that your app uses, along with **databases, caches, and other app-specific data**."

**Source:** [App Sandbox Design Guide - About App Sandbox](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/AboutAppSandbox/AboutAppSandbox.html)

---

## 2. The User Data vs App Data Distinction

### 2.1 Apple's Classification

| Category | Examples | Storage Location |
|----------|----------|------------------|
| **User Documents** | Files user creates, edits, exports | User-selected via Save Panel |
| **App Data** | Databases, caches, preferences, indexes | Container (Application Support) |

### 2.2 The Gray Area: Databases with User Content

The confusion arises when an app's database contains user-generated content:

**Arguments for "App Data" (Container OK):**
- It's a SQLite database, fitting Apple's explicit mention of "databases"
- Users don't directly edit the database
- It's an internal representation, not a document format
- Core Data apps routinely store in Application Support

**Arguments for "User Data" (User location required):**
- Contains user's content (conversations, photos, notes, etc.)
- User may want to back up, export, or move the data
- User has ownership interest in the content
- Data loss would be unacceptable to user

### 2.3 The "Shoebox App" Pattern

Apple defines a "shoebox app" (or "library-style app") as a single-window application managing a collection of user content - like Photos, Music, or Notes.

From Apple's Mac App Programming Guide:

> "For a shoebox-style app, in which you provide the only user interface to the user's content, **that content goes in the container** and your app has full access to it."

**Source:** [The Core App Design - Apple Developer Archive](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/CoreAppDesign/CoreAppDesign.html)

This suggests that apps like Photos (which store user photos in a library within the container) are explicitly permitted to use container storage for user content.

**However:** This guidance predates recent App Review enforcement patterns. Modern App Review may apply stricter interpretations.

---

## 3. App Review Guideline 2.4.5

### 3.1 The Guideline Text

> **2.4.5 Apps distributed via the Mac App Store have some additional requirements:**
> (i) They must be appropriately sandboxed, and follow macOS File System Documentation.

**Source:** [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

### 3.2 Interpretation Challenges

The guideline references "macOS File System Documentation" but doesn't specify which behavior triggers rejection. App Review's interpretation appears to be:

- If data is "user data," it must be accessible to the user
- Hidden container locations are not "user accessible"
- Therefore, user data must use Save Panel or documented locations

### 3.3 Recent Enforcement Patterns (2024-2025)

Based on developer reports, App Review has become stricter about:

1. **Data accessibility** - Users must be able to find/backup their data
2. **Export capabilities** - Apps should allow data export
3. **Transparency** - Users should know where their data is stored

No specific guideline updates in 2024 address this directly, but enforcement appears stricter.

---

## 4. Technical Considerations for SQLite/GRDB

### 4.1 Standard Core Data/GRDB Location

Most Core Data and GRDB apps store databases in:
```
~/Library/Application Support/<AppName>/
```

Which, in a sandboxed app, becomes:
```
~/Library/Containers/<bundle-id>/Data/Library/Application Support/<AppName>/
```

This is the `NSPersistentContainer.defaultDirectoryURL()` location and is explicitly supported.

### 4.2 SQLite Journal Files

SQLite creates auxiliary files alongside the database:
- `database.db-journal` (rollback journal)
- `database.db-wal` (write-ahead log)
- `database.db-shm` (shared memory)

**Important:** If a user selects a database location via Open/Save Panel, the sandbox automatically grants access to these related files (as of macOS 10.8.2).

**Source:** [Sandbox and SQLite - Apple Developer Forums](https://developer.apple.com/forums/thread/13691)

### 4.3 User-Selected Locations

If storing in a user-selected location:

```swift
// Present NSSavePanel
let panel = NSSavePanel()
panel.allowedContentTypes = [.folder]
panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

if panel.runModal() == .OK, let url = panel.url {
    // Store security-scoped bookmark for persistent access
    let bookmark = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )
    UserDefaults.standard.set(bookmark, forKey: "databaseLocationBookmark")
}
```

**Source:** [Stack Overflow - Where to store user data in sandboxed Mac app](https://stackoverflow.com/questions/19948605/where-to-store-user-data-in-a-sandboxed-mac-app-container-or-in-home-documents)

---

## 5. Case Studies

### 5.1 Apps That Store in Container (Approved)

- **Apple Photos** - Library in `~/Pictures/Photos Library.photoslibrary` (actually outside container, user-visible)
- **Apple Notes** - SQLite in container, but syncs to iCloud
- **Bear** - SQLite in container, but offers export
- **Day One** - SQLite in container, syncs to cloud

### 5.2 Apps That Use User-Selected Locations

- **DEVONthink** - Databases in user-selected locations
- **Ulysses** - Library in user-visible location with iCloud sync
- **Obsidian** - Vaults in user-selected folders

### 5.3 Common Pattern for Approval

Apps that store user content in containers typically offer:
1. **Cloud sync** (iCloud, proprietary cloud) - so data isn't "trapped"
2. **Export functionality** - users can get their data out
3. **Clear documentation** - users know where data lives

---

## 6. Analysis: Contextify's Situation

### 6.1 Current Architecture

- Database: `~/Library/Application Support/Contextify/contextify.db`
- Sandboxed: `~/Library/Containers/.../Application Support/Contextify/contextify.db`
- Contains: Transcript index, LLM summaries, user preferences

### 6.2 Arguments for Appeal

1. **Database is explicitly permitted** in containers per Apple's own documentation
2. **Source data is user-accessible** - Transcripts live in `~/.claude/projects/`
3. **Database is reconstructable** - Can be rebuilt from transcript files
4. **LLM summaries are app-generated** - Not user-created content
5. **Custom location already supported** - Users who want control have it

### 6.3 Arguments Against Appeal

1. **Conversation history is "user data"** - Users have ownership interest
2. **Container is hidden** - Users can't easily backup the database
3. **Recent enforcement trend** - App Review appears stricter on this
4. **Summaries have value** - Regenerating them costs API calls/time

### 6.4 Recommendation

**Option A: Appeal** (Medium risk)
- Cite Apple's documentation on containers being for "databases"
- Emphasize that source data (transcripts) is already user-accessible
- Note existing custom location feature for users who want control
- Risk: Appeal may fail, delaying release further

**Option B: Comply** (Low risk, more work)
- Add first-run prompt asking user where to store database
- Default suggestion: `~/Documents/Contextify/` or similar
- Leverage existing custom location code
- Ensures approval, improves user control

**Option C: Hybrid** (Balanced)
- Keep container as default for simplicity
- Add prominent "Database Location" in onboarding
- Make export functionality more visible
- May or may not satisfy App Review

---

## 7. Implementation Guidance (If Complying)

### 7.1 First-Run Database Location Selection

```swift
func promptForDatabaseLocation() async -> URL? {
    let panel = NSOpenPanel()
    panel.message = "Choose where to store your Contextify database"
    panel.prompt = "Select Folder"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

    guard panel.runModal() == .OK, let url = panel.url else {
        return nil
    }

    // Create security-scoped bookmark for persistent access
    let bookmark = try? url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )

    if let bookmark {
        UserDefaults.standard.set(bookmark, forKey: "customDatabaseLocation")
    }

    return url
}
```

### 7.2 Suggested Default Locations

| Location | Pros | Cons |
|----------|------|------|
| `~/Documents/Contextify/` | Very visible, backed up | Clutters Documents |
| `~/Library/Contextify/` | Clean, still accessible | Less discoverable |
| User's choice | Maximum flexibility | Adds friction |

### 7.3 Migration Path

For existing users:
1. Detect existing database in container
2. Offer to migrate to user-accessible location
3. Preserve option to keep in container (for DMG users)

---

## 8. References

### Official Apple Documentation
- [App Sandbox Design Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/AboutAppSandbox/AboutAppSandbox.html)
- [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Protecting User Data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- [Mac App Programming Guide - Core App Design](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/CoreAppDesign/CoreAppDesign.html)

### Developer Forums & Stack Overflow
- [Where to store user data: Container or Documents?](https://stackoverflow.com/questions/19948605/where-to-store-user-data-in-a-sandboxed-mac-app-container-or-in-home-documents)
- [What is a shoebox app?](https://stackoverflow.com/questions/11929686/what-is-a-shoebox-app)
- [Sandbox and SQLite](https://developer.apple.com/forums/thread/13691)
- [SQLite temp file rejection](https://stackoverflow.com/questions/59690221/macos-app-with-user-selected-file-read-write-entitlement-rejected-from-mac-app-s)

### Community Resources
- [What are all those Containers? (2024)](https://macmegasite.com/2024/08/05/what-are-all-those-containers/)
- [The app sandbox and how it protects](https://eclecticlight.co/2016/08/29/the-app-sandbox-and-how-it-protects/)
- [Cocoacasts - Application Sandboxing](https://cocoacasts.com/what-is-application-sandboxing)
- [App Store Review Guidelines History](http://www.appstorereviewguidelineshistory.com/)

---

## 9. Conclusion

Apple's documentation explicitly permits databases in the container, but App Review's interpretation of "user data" can override this. The safest path for approval is to give users explicit control over database location via Save Panel, while the appeal path has merit based on Apple's own documentation.

**For Contextify specifically:** Given that:
1. The source data (transcripts) is already user-accessible
2. The database is primarily an index/cache
3. Custom location support already exists

An appeal is defensible, but compliance (first-run location prompt) is the lower-risk path to approval.
