# CLI Conversation Resumption Guide

Quick reference for resuming/continuing conversations in Codex CLI and Claude Code.

**Related Documentation:**
- **Transcript Formats:** `claude-code-transcript-format.md` - Detailed format specifications
- **Converter Script:** `../../scripts/TRANSCRIPT_CONVERTER_README.md` - Conversion tool usage
- **This Guide:** How to resume converted sessions in each CLI

## Codex CLI

### Resume Command
```bash
codex resume [session-id]
```

**Interactive Picker (Recommended):**
```bash
codex resume
# Shows interactive picker with recent sessions
# Select session from list
```

**Direct Resume with Session ID:**
```bash
codex resume a7b199c5-8f5b-48eb-b5fa-b65b072961a3
```

**Resume Most Recent:**
```bash
codex resume --last
```

### Session ID Location
- Session ID is in the filename: `rollout-YYYY-MM-DDTHH-MM-SS-<session-id>.jsonl`
- Example: `rollout-2025-10-24T09-44-46-3f993b19-fbab-4f00-8751-eed0c61da9db.jsonl`
- Session ID: `3f993b19-fbab-4f00-8751-eed0c61da9db`

### Session Storage
- Location: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
- Format: JSONL (one JSON object per line)

## Claude Code

### Resume Command
```bash
claude --resume [sessionId]
claude -r [sessionId]
```

**Interactive Picker:**
```bash
claude --resume
# OR
claude -r
# Shows interactive picker with recent sessions
```

**Direct Resume with Session ID:**
```bash
claude --resume a7b199c5-8f5b-48eb-b5fa-b65b072961a3
# OR
claude -r a7b199c5-8f5b-48eb-b5fa-b65b072961a3
```

**Continue Most Recent:**
```bash
claude --continue
# OR
claude -c
```

### Session ID Location
- Session ID is the filename without `.jsonl` extension
- Example: `a7b199c5-8f5b-48eb-b5fa-b65b072961a3.jsonl`
- Session ID: `a7b199c5-8f5b-48eb-b5fa-b65b072961a3`

### Session Storage
- Location: `~/.claude/projects/-<project-path>/<session-id>.jsonl`
- Format: JSONL (one JSON object per line)

## Converter Output Instructions

When the converter completes, it shows you the exact command to resume:

### Claude Code → Codex Example
```
============================================================
📋 How to Resume This Conversation
============================================================

1. Navigate to the project directory:
   cd /Users/rob/code/projects/contextify

2. Resume the conversation with Codex CLI:
   codex resume 3f993b19-fbab-4f00-8751-eed0c61da9db
   # OR use the picker:
   codex resume

📍 Transcript location: ~/.codex/sessions/2025/10/24/rollout-2025-10-24T09-44-46-3f993b19-fbab-4f00-8751-eed0c61da9db.jsonl
🆔 Session ID: 3f993b19-fbab-4f00-8751-eed0c61da9db
📁 Project directory: /Users/rob/code/projects/contextify
============================================================
```

### Codex → Claude Code Example
```
============================================================
📋 How to Resume This Conversation
============================================================

1. Navigate to the project directory:
   cd /Users/rob/code/projects/contextify

2. Resume the conversation with Claude Code:
   claude --resume imported-session

📍 Transcript location: ~/.claude/projects/-Users-rob-code-projects-contextify/imported-session.jsonl
🆔 Session ID: imported-session
📁 Project directory: /Users/rob/code/projects/contextify
============================================================
```

## Verification Checklist

When testing converter output:

1. **Navigate to project directory** (as shown in resume instructions)
2. **Run resume command** (copy/paste from converter output)
3. **Verify conversation loads:**
   - CLI shows history loading message
   - Previous context is available (ask "What have we been working on?")
   - Can continue conversation naturally
4. **Check for issues:**
   - Missing messages?
   - Context loss?
   - Errors on resume?

## Common Issues

### Codex: Session Not Found
- **Cause:** File not in `~/.codex/sessions/YYYY/MM/DD/` directory
- **Fix:** Copy file to correct location or use picker (`codex resume`)

### Claude Code: Session Not Found
- **Cause:** File not in correct project directory
- **Fix:** Ensure file is in `~/.claude/projects/-<project-path>/`

### Both: Empty/Corrupted Session
- **Cause:** Converter created file with no messages
- **Symptom:** CLI loads but has no history
- **Check:** `wc -l <session-file>` (should be >0)

### Permission Issues
- **Cause:** Session file not readable
- **Fix:** `chmod 644 <session-file>`
