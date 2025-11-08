# Intent Classification Analysis Workflow

**Problem:** Timeline summaries sometimes show "infer from message" placeholder text instead of proper summaries.

**Root Cause:** The `classifyUserIntent()` function in `FoundationLLM.swift` uses pattern matching to classify user messages. When no patterns match, it returns `.unknown`, which leads to a prompt template that contains a placeholder the LLM should replace but sometimes doesn't.

This document describes the database-driven analysis workflow to identify missing patterns and improve classification accuracy.

---

## Quick Start

```bash
# 1. Analyze your database for placeholder instances
./scripts/analyze_intent_classification.sh

# 2. Generate improvement recommendations
python3 scripts/generate_intent_improvements.py build/analysis/intent-classification-data-TIMESTAMP.csv

# 3. Review recommendations and update FoundationLLM.swift
```

---

## Analysis Workflow

### Step 1: Survey the Database

The analysis script queries the database to find all timeline cache entries where summaries contain the "infer from message" placeholder:

```sql
SELECT
  tc.entry_id,
  te.content AS user_message,
  tc.present_form,
  tc.past_form,
  tc.disposition,
  tc.generated_at,
  te.timestamp,
  te.session_id,
  p.root_path AS project_path
FROM timeline_cache tc
INNER JOIN transcript_entries te ON tc.entry_id = te.id
INNER JOIN projects p ON te.project_id = p.id
WHERE
  te.kind = 'user'
  AND (
    tc.present_form LIKE '%infer from message%'
    OR tc.past_form LIKE '%infer from message%'
  )
ORDER BY tc.generated_at DESC;
```

**Key Tables:**
- `timeline_cache` - Stores LLM-generated summaries (present_form, past_form)
- `transcript_entries` - Contains original user messages (content column)
- `projects` - Project metadata for context

**Output:**
- Human-readable report: `build/analysis/intent-classification-analysis-TIMESTAMP.txt`
- Machine-readable CSV: `build/analysis/intent-classification-data-TIMESTAMP.csv`

### Step 2: Pattern Extraction

The Python analysis script processes the CSV and extracts:

1. **First word frequency** - Identifies potential imperative verbs
2. **Single-word commands** - Terse commands that need special handling
3. **Short messages (2-3 words)** - Phrases that may lack clear patterns
4. **Statement patterns** - Declarative sentences ("this broke X", "the Y is Z")
5. **Question patterns** - Questions that should be classified differently

**Analysis Categories:**

| Category | Description | Example |
|----------|-------------|---------|
| **Imperative Verbs** | First word is a command verb | "investigate the bug" |
| **Single-Word** | One-word commands | "revert" |
| **Statement** | Declarative sentences | "this broke the build" |
| **Question** | Interrogative sentences | "what caused this?" |
| **Short Phrase** | 2-3 words, unclear intent | "the project tab issue" |

### Step 3: Generate Recommendations

The script outputs:

1. **Missing verbs** - Imperative verbs not in the current `imperativeVerbs` set
2. **Pattern additions** - New heuristics to add to `classifyUserIntent()`
3. **Prompt improvements** - Better LLM templates to avoid placeholders
4. **Sample messages** - Real examples for manual review

---

## Code Improvements

### Current Implementation

**File:** `Contextify/Contextify/FoundationLLM.swift:282-375`

```swift
private func classifyUserIntent(message: String) -> UserIntent {
  let lowerFirst = message.lowercased()

  // Directive patterns
  let imperativeVerbs: Set<String> = [
    "add", "create", "make", "write", "update", "modify", "delete",
    "remove", "fix", "change", "show", "display", "list", "get",
    "set", "enable", "disable", "start", "stop", "run", "execute",
    "install", "configure", "test", "debug", "check", "verify",
    "search", "find", "open", "close"
  ]

  let firstWord = lowerFirst.split(separator: " ").first.map(String.init) ?? ""
  if imperativeVerbs.contains(firstWord) {
    return .directive
  }

  // Check for directive phrases
  if lowerFirst.hasPrefix("can you") || lowerFirst.hasPrefix("could you") ||
     lowerFirst.hasPrefix("please") {
    return .directive
  }

  // Question patterns
  if lowerFirst.hasPrefix("what") || lowerFirst.hasPrefix("why") ||
     lowerFirst.hasPrefix("how") || lowerFirst.hasSuffix("?") {
    return .question
  }

  // ... more patterns ...

  // Default to unknown
  return .unknown
}
```

### Recommended Improvements

#### 1. Add Missing Verbs

Based on your analysis output, add frequently occurring verbs:

```swift
let imperativeVerbs: Set<String> = [
  // ... existing verbs ...
  "investigate", "revert", "verify", "confirm", "try",
  "deploy", "build", "restore", "reset", "undo",
  "analyze", "review", "explain", "describe"
]
```

#### 2. Add Statement Pattern Detection

Many user messages are declarative statements:

```swift
// Statement patterns (after directive/question checks)
if lowerFirst.hasPrefix("this ") || lowerFirst.hasPrefix("the ") {
  return .directive  // Treat statements as implicit directives
}

if lowerFirst.contains("need to") || lowerFirst.contains("should") ||
   lowerFirst.contains("gotta") || lowerFirst.contains("lemme") {
  return .directive
}

// Negation patterns
if lowerFirst.contains("doesn't work") || lowerFirst.contains("doesn't") ||
   lowerFirst.contains("not working") || lowerFirst.contains("broke") {
  return .directive
}
```

#### 3. Fix the LLM Prompt Template

**Current (line ~1109):**
```swift
case .unknown:
  return "You requested \(assistantName) to [infer from message]"
```

**Improved Option A (remove placeholder):**
```swift
case .unknown:
  return "You [concisely describe the action based on the MESSAGE]"
```

**Improved Option B (let LLM decide):**
```swift
case .unknown:
  return nil  // Don't provide a template, let LLM use generic format
```

**Improved Option C (better instruction):**
```swift
case .unknown:
  return "Infer the user's intent and describe it as: \"You [action verb] [object]\""
```

---

## Expected Improvements

After implementing recommendations:

| Metric | Before | Target After |
|--------|--------|--------------|
| `.unknown` classification rate | ~15-30% | <5% |
| Placeholder in summaries | Variable | 0% |
| User-facing quality | Inconsistent | Consistent |

---

## Testing Workflow

### 1. Before Changes

```bash
# Capture baseline
./scripts/analyze_intent_classification.sh > baseline-report.txt
```

### 2. Make Code Changes

Update `Contextify/Contextify/FoundationLLM.swift`:
- Add new verbs to `imperativeVerbs`
- Add statement pattern detection
- Update `.unknown` prompt template

### 3. Invalidate Cache (Force Regeneration)

```sql
-- Clear timeline cache to force LLM re-generation
DELETE FROM timeline_cache
WHERE disposition = 'user_request'
  AND (present_form LIKE '%infer from message%' OR past_form LIKE '%infer from message%');
```

Or use the database manager:
```bash
./scripts/db_manager.sh exec "DELETE FROM timeline_cache WHERE present_form LIKE '%infer from message%'"
```

### 4. Rebuild and Test

```bash
make build
# Use the app and trigger timeline summary generation
```

### 5. Re-analyze

```bash
./scripts/analyze_intent_classification.sh
# Should show 0 instances or significantly reduced count
```

---

## Database Schema Reference

### timeline_cache Table

```sql
CREATE TABLE timeline_cache (
  content_sha256 TEXT NOT NULL,        -- Hash of entry content
  window_sha256 TEXT NOT NULL,         -- Hash of context window
  entry_id TEXT NOT NULL,              -- References transcript_entries(id)
  generator_signature TEXT NOT NULL,   -- LLM generator version
  disposition TEXT NOT NULL,           -- Entry type (user_request, etc.)
  present_form TEXT NOT NULL,          -- "You request..."
  past_form TEXT NOT NULL,             -- "You requested..."
  selected_form TEXT NOT NULL,         -- 'present' or 'past'
  verb_lemma TEXT,                     -- Extracted verb
  generated_at INTEGER NOT NULL,       -- Unix timestamp
  user_edited INTEGER NOT NULL DEFAULT 0,
  user_text TEXT,
  edited_at INTEGER,
  request_id TEXT,
  duration REAL,
  PRIMARY KEY (content_sha256, window_sha256)
) WITHOUT ROWID;
```

### transcript_entries Table

```sql
CREATE TABLE transcript_entries (
  id TEXT PRIMARY KEY,
  transcript_id TEXT NOT NULL,
  project_id TEXT NOT NULL,
  session_id TEXT,
  provider TEXT NOT NULL,              -- 'claude.code' or 'codex.cli'
  kind TEXT NOT NULL,                  -- 'user', 'assistant', 'system'
  timestamp INTEGER NOT NULL,
  content TEXT NOT NULL,               -- Original user message
  content_sha256 TEXT NOT NULL,
  display_in_timeline INTEGER NOT NULL DEFAULT 1,
  -- ... more fields ...
);
```

---

## Troubleshooting

### No Placeholder Instances Found

If the analysis returns 0 results:
- ✅ **Good news!** Intent classification is working well
- Check if timeline cache was recently cleared
- Verify database has timeline entries: `SELECT COUNT(*) FROM timeline_cache;`

### High Placeholder Count (>20%)

This indicates significant classification gaps:
1. Run the Python analysis script for detailed patterns
2. Focus on top 10 first words - these are likely missing verbs
3. Review "statement patterns" section for declarative sentences
4. Consider implementing **Option B** (better prompt) as a quick fix

### LLM Not Replacing Placeholder

If the LLM receives the placeholder but doesn't replace it:
- This is a prompt engineering issue, not a classification issue
- Use **Option A** or **Option B** prompt improvements
- Consider adding more explicit instructions in the prompt

### Inconsistent Results Across Sessions

Timeline cache is keyed by content + window hash:
- Same message in different contexts may get different classifications
- This is expected behavior (context-aware summarization)
- Focus on reducing placeholders, not enforcing exact consistency

---

## Scripts Reference

### analyze_intent_classification.sh

**Location:** `scripts/analyze_intent_classification.sh`

**Purpose:** Survey database for placeholder instances

**Output:**
- `build/analysis/intent-classification-analysis-TIMESTAMP.txt` (human-readable)
- `build/analysis/intent-classification-data-TIMESTAMP.csv` (machine-readable)

**Runtime:** <5 seconds (depends on database size)

### generate_intent_improvements.py

**Location:** `scripts/generate_intent_improvements.py`

**Purpose:** Extract patterns and generate code recommendations

**Input:** CSV file from analysis script

**Output:** Structured report with:
- Top first words (potential verbs)
- Pattern frequency analysis
- Swift code snippets to add
- Sample messages for review

**Runtime:** <1 second

---

## Future Enhancements

### Machine Learning Approach

Instead of heuristic pattern matching, train a classifier:
1. Export labeled examples from database (known good summaries)
2. Train a small BERT/DistilBERT model for intent classification
3. Replace `classifyUserIntent()` with ML inference
4. **Trade-off:** Adds dependency, increases binary size

### Two-Pass Classification

If heuristic returns `.unknown`:
1. Make a lightweight LLM call to classify intent
2. Cache the result (add `intent_classification_cache` table)
3. Use cached intent for summary generation
4. **Trade-off:** Slower first-time, doubles LLM calls

### Confidence Scoring

Add confidence scores to heuristic matches:
- High confidence: exact verb match
- Medium confidence: pattern match
- Low confidence: default to `.unknown` but with better prompt
- **Trade-off:** More complex logic

---

## References

- **Issue:** TODOS.md:24-107 (Timeline Summaries Show "infer from message" Placeholder)
- **Implementation:** Contextify/Contextify/FoundationLLM.swift:282-375, 1109
- **Database Schema:** app/Sources/ContextifyCore/Database/DatabaseSchema.swift:366-449
- **LLM Architecture:** build/notes/technical-reference/llm-processing-architecture.md
