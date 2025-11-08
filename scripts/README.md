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

### `analyze_intent_classification.sh`
Survey database for timeline summaries with "infer from message" placeholder.

**Usage:**
```bash
./scripts/analyze_intent_classification.sh
```

**What it does:**
1. Queries `timeline_cache` table for entries with placeholder text
2. Extracts original user messages from `transcript_entries`
3. Generates human-readable report and machine-readable CSV
4. Outputs to `build/analysis/intent-classification-analysis-TIMESTAMP.txt`

**When to use:**
- Timeline summaries show "infer from message" placeholder
- Want to understand which user messages trigger `.unknown` intent classification
- Need data-driven insights for improving pattern matching

**Related:**
- Follow-up script: `generate_intent_improvements.py`
- Documentation: `build/docs/archive/investigations/2025-11-03-intent-classification.md`
- Issue: `TODOS.md` #1 (Timeline Summaries Placeholder)

---

### `generate_intent_improvements.py`
Analyze user messages and generate code recommendations for intent classification.

**Usage:**
```bash
python3 scripts/generate_intent_improvements.py <csv_file>
```

**Example:**
```bash
# Run analysis first
./scripts/analyze_intent_classification.sh

# Then generate recommendations
python3 scripts/generate_intent_improvements.py build/analysis/intent-classification-data-20250102-143022.csv
```

**What it does:**
1. Extracts pattern frequency from user messages (first words, imperatives, statements)
2. Identifies missing verbs not in `classifyUserIntent()`
3. Suggests Swift code additions for `FoundationLLM.swift`
4. Provides before/after metrics for validation

**Output:**
- Top first words (potential missing verbs)
- Single-word commands analysis
- Statement pattern detection
- Swift code snippets to add

**When to use:**
- After running `analyze_intent_classification.sh`
- Before modifying `FoundationLLM.swift:classifyUserIntent()`
- Need specific code recommendations based on real data

**Related:**
- Input: CSV from `analyze_intent_classification.sh`
- Target file: `Contextify/Contextify/FoundationLLM.swift:282-375`

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
