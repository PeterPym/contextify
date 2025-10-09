# Contextify Scripts

Utility scripts for Contextify development and maintenance.

## Available Scripts

### `migrate-transcripts.sh`
Migrate Claude Code transcripts when project directory changes.

**Usage:**
```bash
./scripts/migrate-transcripts.sh <old-path> <new-path>
```

**Example:**
```bash
./scripts/migrate-transcripts.sh /Users/rob/code/contextify /Users/rob/code/projects/contextify
```

**What it does:**
1. Creates timestamped backup of original transcripts
2. Copies transcripts from old location to new location
3. Replaces all instances of old path with new path in JSONL content
4. Preserves JSONL structure, UUIDs, and timestamps

**Safety:**
- Always creates backup before modifying anything
- Non-destructive (keeps originals)
- Prompts for confirmation if destination exists
- Validates source directory has transcripts

**When to use:**
- You moved your project to a new directory
- Old transcripts show outdated file paths
- You want consolidated transcript history at current location

**Related:** See `TODOS.md` for planned UI wrapper (backlog)

---

### `xc.sh`
Build script that auto-detects Xcode/Xcode-beta.

**Usage:**
```bash
bash scripts/xc.sh build
bash scripts/xc.sh test
bash scripts/xc.sh clean
```

See file header for full documentation.
