# Rejection #2 Deliberation: Guideline 2.4.5(i)

**Date:** 2025-12-03
**Build:** 10
**Guideline:** 2.4.5(i) - Performance

## Apple's Rejection

> "Your app saves user data to the app's container, which is not user accessible."

Apple cited the App Sandbox Design Guide:
> "The container is in a hidden location, and so users do not interact with it directly. Specifically, the container is not for user documents. It is for files that your app uses, along with databases, caches, and other app-specific data."

**Next Steps from Apple:** Save user files to a location selected by or available to users, using standard Save dialogs.

## Initial Confusion

Apple's own documentation says containers ARE for "databases, caches, and other app-specific data." So why is our SQLite database being rejected?

## Key Insight: Content Determines Classification

Apple distinguishes between:

| Term | Meaning | Container OK? |
|------|---------|---------------|
| **App data** | Data the *app* needs to function | Yes |
| **User data** | Data the *user* owns/created | No |

**The file format doesn't matter.** A database containing user content is "user data," not "app data."

## Why Contextify's Database is "User Data"

The database isn't just a behind-the-scenes cache. Users actively:
- Search across their conversations
- Browse their history
- View and read summaries
- Retrieve past content

**The test:** If the database disappeared, would the user lose something they care about?
- The summaries took time/compute to generate
- The organized conversation history has value
- Users would reasonably want to back this up

**Apple's implicit logic:** If users interact with data stored there, they should be able to access where it's stored.

## Considered Options

### Option A: Appeal
**Arguments:**
1. Apple's docs explicitly list "databases" as container-appropriate
2. Source data (transcripts) is already user-accessible in `~/.claude/projects/`
3. Database is technically reconstructable from transcript files
4. "Shoebox app" pattern (like Photos) stores user content in container

**Risk:** Medium - enforcement has tightened, appeal may fail

### Option B: Comply
**Approach:** Add first-run prompt asking user where to store database using NSSavePanel

**Risk:** Low - ensures approval, improves user control

**Note:** Custom database location code already exists in Settings > Database tab. This would make it the default flow rather than optional.

### Option C: Hybrid
Keep container default but make location selection more prominent in onboarding.

**Risk:** May not satisfy App Review

## Decision

[TO BE FILLED IN]

## References

- `macos-sandbox-database-storage-tech-brief.md` - Full research brief
- `messages.md` - Original rejection text from Apple
- `rejection-history.json` - Structured rejection data
