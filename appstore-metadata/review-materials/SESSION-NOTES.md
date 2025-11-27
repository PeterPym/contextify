# App Store Resubmission Session - Nov 27, 2025

## Context

Initial App Store submission (v1.0) was rejected with Guideline 2.1 - Information Needed:
1. Need sample Claude project files for Apple to test summarize feature
2. Need demo video showing app on physical macOS device

## Branch

`chore/appstore-resubmission` (created from main)

## Committed Work

```
3cb97758 docs(appstore): add session notes for resubmission workflow
deacd47d feat(appstore): add review materials for App Store resubmission
```

**Session notes also in repo:** `appstore-metadata/review-materials/SESSION-NOTES.md`

## Work Completed

### 1. Created Response Plan
- `/private/tmp/app-store-rejection-response-plan.md` - overall strategy
- Copied to repo: `appstore-metadata/review-materials/REJECTION-RESPONSE-PLAN.md`

### 2. Created Sample Transcript Plan
- `/private/tmp/sample-transcript-plan.md` - detailed conversation scripts
- Copied to repo: `appstore-metadata/review-materials/SAMPLE-TRANSCRIPT-PLAN.md`
- Covers 3 fictional projects: TaskFlow, Weatherly, RecipeBox
- Both Claude Code and Codex CLI sessions planned

### 3. Created Transcript Generator Script
- `appstore-metadata/review-materials/generate-transcripts.sh`
- Uses real Claude/Codex CLIs to generate valid transcripts
- Multi-turn conversations using `--output-format json` + `--resume <session_id>`
- Projects created in `~/code/sample-projects/` (not /tmp due to macOS path issues)

### 4. Tested Script Components
- Session ID capture: WORKS (`claude -p --output-format json` returns session_id)
- Resume: WORKS (`claude --resume <id> -p` continues conversation)
- Transcript creation: WORKS (creates valid JSONL in `~/.claude/projects/`)
- macOS path issue: FIXED (updated to use `~/code/sample-projects/` instead of `/tmp`)

## Files in Repo

```
appstore-metadata/review-materials/
├── REJECTION-RESPONSE-PLAN.md      # Overall response strategy
├── SAMPLE-TRANSCRIPT-PLAN.md       # Conversation scripts for 3 projects
├── generate-transcripts.sh         # Automated transcript generator
└── sample-transcripts/             # Output directory (empty until script runs)
```

## Session 2 - Nov 27, 2025 (Continued)

### Work Completed This Session

1. **Cleaned up test transcripts** - Removed old test data from previous session

2. **Generated full transcript set** - Ran `generate-transcripts.sh`
   - 4 Claude Code sessions (54 transcripts total)
   - 3 Codex CLI sessions
   - Projects: taskflow, weatherly, recipebox
   - Transcripts in `~/.claude/projects/-Users-rob-code-sample-projects-*/`

3. **Tested with Contextify**
   - Cleaned database with `./scripts/db_manager.sh clean --force`
   - Built and launched app: `bash scripts/xc.sh build`
   - Verified:
     - 3 sample projects detected in database
     - 54 transcripts discovered and being processed
     - 2136 total entries ingested
     - LLM summarization working (11 cache entries)

4. **Created sample data package**
   - `appstore-metadata/review-materials/sample-data.zip` (100KB)
   - Contains 57 transcript files + README.txt

5. **Created website review directory**
   - `website/review/index.html` - Instructions page for Apple reviewers
   - `website/review/sample-data.zip` - Sample data package

### Files Created

```
website/review/
├── index.html              # Instructions for Apple reviewers
└── sample-data.zip         # Sample transcript files (100KB)

appstore-metadata/review-materials/
├── sample-data.zip         # Copy of sample data
└── sample-transcripts/     # Raw transcript files (57 files)
```

## Next Steps (Human Required)

1. **Upload to website** - Deploy review materials
   ```bash
   ./scripts/deploy-website.sh
   ```
   This will upload `website/review/` to `https://contextify.sh/review/`

2. **Record demo video** - Screen recording showing:
   - First launch and permissions grant
   - Project detection (sample projects appearing)
   - Timeline view with conversations
   - LLM summaries generating
   - Search functionality
   - Project switching

3. **Upload demo video** - Add to `website/review/demo-video.mp4`

4. **Update App Store Connect** - Add to App Review Notes:
   ```
   DEMO VIDEO:
   https://contextify.sh/review/demo-video.mp4

   SAMPLE DATA:
   https://contextify.sh/review/sample-data.zip

   SETUP INSTRUCTIONS:
   https://contextify.sh/review/
   ```

5. **Resubmit** - Reply to rejection in App Store Connect

## Technical Notes

### Claude Code CLI for Multi-Turn
```bash
# First turn - capture session ID
session_id=$(claude -p --output-format json --dangerously-skip-permissions "prompt" | jq -r '.session_id')

# Subsequent turns - resume session
claude --resume "$session_id" -p --dangerously-skip-permissions "follow-up"
```

### Codex CLI for Multi-Turn
```bash
# First turn
codex exec -C /path/to/project --dangerously-bypass-approvals-and-sandbox "prompt"
# Capture session ID from "codex resume <id>" in output

# Resume
codex exec resume <session_id> --dangerously-bypass-approvals-and-sandbox "follow-up"
```

### Transcript Locations
- Claude Code: `~/.claude/projects/-Users-<user>-code-sample-projects-<project>/`
- Codex: `~/.codex/sessions/YYYY/MM/DD/<session>.jsonl`

## Test Transcripts Created

During testing, created transcripts in:
- `~/.claude/projects/-private-tmp-taskflow/` (old /tmp path)
- Multiple sessions with 2+2 and 3+3 test prompts

These should be cleaned up before running the full script.

## Cleanup Before Full Run

```bash
# Remove test transcripts
rm -rf ~/.claude/projects/-private-tmp-*
rm -rf /tmp/taskflow /tmp/weatherly /tmp/recipebox
```

## Documentation Updates Needed

After successful transcript generation:
1. Update `scripts/RELEASE.md` - Add App Review materials section
2. Update `build/docs/guides/APP-STORE-SUBMISSION.md` - Add demo video/sample data requirements
3. Update `appstore-metadata/README.md` - Add to submission checklist
