Contextify Sample Data for App Store Review
============================================

WHAT THIS IS:
These are sample Claude Code and Codex CLI transcript files that demonstrate
the type of data Contextify reads and summarizes.

SETUP INSTRUCTIONS:
1. Close Contextify if running
2. Create directories and copy transcript files:

   # Create directories (needed if Claude Code/Codex CLI not installed)
   mkdir -p ~/.claude/projects
   mkdir -p ~/.codex/sessions

   # Copy Claude Code transcripts
   cp -r claude/projects/* ~/.claude/projects/

   # (Optional) Copy Codex CLI sessions
   cp -r codex/sessions/* ~/.codex/sessions/

3. Launch Contextify
4. The sample projects will appear in the project switcher:
   - taskflow (CLI task manager)
   - weatherly (weather dashboard)
   - recipebox (recipe manager)

WHAT TO TEST:
- Projects appear in project switcher tab bar
- Timeline shows conversation history
- LLM summaries generate automatically for each entry
- Search works (Cmd+F for quick search)
- Can switch between projects

CONTENTS:
- claude/projects/        Claude Code transcript files (54 files)
- codex/sessions/         Codex CLI session files (3 files)

NOTE:
These transcripts were generated using real Claude Code and Codex CLI sessions
with fictional software development projects. They demonstrate the natural
conversation flow that Contextify monitors and summarizes.
