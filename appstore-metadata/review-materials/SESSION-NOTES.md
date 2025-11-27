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

## Next Steps (To Resume)

1. **Cleanup test transcripts** (from earlier testing)
   ```bash
   rm -rf ~/.claude/projects/-private-tmp-*
   rm -rf /tmp/taskflow /tmp/weatherly /tmp/recipebox
   ```

2. **Run generate-transcripts.sh** - Creates real Claude/Codex sessions
   ```bash
   cd ~/code/projects/contextify-worker-bee/appstore-metadata/review-materials
   ./generate-transcripts.sh
   ```
   - Creates projects in `~/code/sample-projects/`
   - Generates 4 Claude Code sessions + 3 Codex sessions
   - Takes ~10-15 minutes

3. **Test with Contextify** - Clean DB, verify projects appear, summaries generate

4. **Record demo video** - Screen recording showing full app workflow

5. **Upload materials** - Deploy to contextify.sh/review/

6. **Update App Store Connect** - Add URLs to App Review Notes

7. **Resubmit** - Reply to rejection with materials ready

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
