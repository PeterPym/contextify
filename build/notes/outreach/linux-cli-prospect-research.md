# Linux CLI Prospect Research - Consolidated Reference

**Date:** 2026-01-14
**Purpose:** Track prospect research for Contextify Linux CLI beta testing outreach
**Status:** Ready for outreach

---

## Summary

Two prospect lists were generated for Linux CLI beta tester outreach:

| Source | Prospects | Focus | Contact Method |
|--------|-----------|-------|----------------|
| Reddit (r/ClaudeAI) | 19 | Linux/WSL users, session continuity tools | Reddit DM only |
| Hacker News | 21 | Memory/context enthusiasts, tool builders | 6 emails, 5 websites, 10 HN reply |

**Total unique prospects:** 40

---

## Research Methodology

### Reddit Prospects

**Source:** r/ClaudeAI posts and comments via old.reddit.com crawling

**Search process:**
1. Crawled recent r/ClaudeAI posts (2024-2025)
2. Filtered for Linux/WSL/terminal keywords
3. Evaluated engagement patterns (builders vs complainers)
4. Extracted personalized outreach hooks from their content

**Keywords used:**
- `linux`, `ubuntu`, `wsl`, `terminal`
- `session`, `memory`, `context`, `history`

**Behavioral criteria:**
- Sharing solutions and workarounds
- Building open source tools
- Writing detailed tutorials
- Helping others in comments

### Hacker News Prospects

**Source:** HN comments via Algolia API search + HN Firebase API for profiles

**Search process:**
1. Searched HN Algolia: `https://hn.algolia.com/api/v1/search?query=claude+code+memory&tags=comment`
2. Reviewed comments for memory/context pain points
3. Checked HN profiles for contact info (email field, about section)
4. Used Firebase API to fetch profile details: `https://hacker-news.firebaseio.com/v0/user/{id}.json`

**Keywords used:**
- `claude code memory`
- `claude code session`
- `claude code context`
- `claude code transcript`

---

## How to Get More Prospects

### Reddit (r/ClaudeAI)

Use the `/prospect` skill or direct crawl prompt:

```
/crawl https://reddit.com/r/ClaudeAI and search for users discussing:
- Linux usage with Claude Code
- WSL or native Linux environments
- CLI preferences or terminal workflows

Create a prospect list excluding users who:
- Are dismissive or gatekeeping in tone
- Have very low engagement (< 3 comments)
- Only complain without contributing

Prioritize users who:
- Ask "how do I..." questions about Linux
- Share workarounds or tips
- Express interest in new tools/features

Output CSV with: username, profile_url, evidence_url, outreach_hook
```

### Hacker News

Use Algolia API search:

```bash
# Search for relevant comments
curl "https://hn.algolia.com/api/v1/search?query=claude+code+memory&tags=comment"

# Get profile with contact info
curl "https://hacker-news.firebaseio.com/v0/user/{username}.json"
```

**Keywords that found engaged users:**
- `claude code memory`
- `claude code session`
- `claude code context`
- `claude code transcript`

---

## File Locations

All prospect files are in `build/notes/outreach/`:

| File | Description |
|------|-------------|
| `prospects-linux-cli-v2-2026-01-14.csv` | Reddit prospects - 19 Linux/session users |
| `prospects-contextify-hn-2026-01-14.csv` | HN prospects - 21 memory/context enthusiasts |
| `prospects-linux-cli-beta-2026-01-14-summary.md` | Reddit research summary with templates |
| `prospects-contextify-hn-2026-01-14-summary.md` | HN research summary with tiered segments |
| `prospect-comparison-analysis.md` | Methodology comparison |
| `README.md` | Directory overview |

---

## Prospect Data (Preserved)

### Reddit Prospects (19)

```csv
username,profile_url,evidence_url,outreach_hook
ia77q,https://reddit.com/user/ia77q,https://old.reddit.com/r/ClaudeAI/comments/1pnu2e8/claude_code_discovered_a_hacker_on_my_server/,"Used Claude Code on Linux server to discover and fix a cryptocurrency mining hack. Power user who discovered security issue through SSH + Claude Code workflow."
Historical-Lie9697,https://reddit.com/user/Historical-Lie9697,https://old.reddit.com/r/ClaudeAI/comments/1pmkpf6/built_a_chrome_extension_that_puts_terminals_in/,"Built Tabz Chrome extension with real bash terminals connected via WebSocket. Creates WSL/Linux/macOS terminal integrations with Claude Code status detection. Tool builder in terminal automation space."
Psychological_Box406,https://reddit.com/user/Psychological_Box406,https://old.reddit.com/r/ClaudeAI/comments/1lrcghz/please_bring_claude_code_to_windows/,"Pro subscriber who loves Claude Code on Linux home setup but stuck on Windows at work. Frustrated by platform inconsistency. Explicitly stated 'I love Claude Code on my Linux home setup'."
AssumptionNew9900,https://reddit.com/user/AssumptionNew9900,https://old.reddit.com/r/ClaudeAI/comments/1lvnluz/i_got_tired_of_losing_claude_code_hours_so_i/,"Built CCAutoRenew daemon for macOS/Linux to automatically renew Claude Code sessions. Shares tips about session management and timing. Tool builder solving session continuity problems."
cocktail_peanut,https://reddit.com/user/cocktail_peanut,https://old.reddit.com/r/ClaudeAI/comments/1op7963/i_built_an_app_that_lets_you_run_claude_code_or/,"Built desktop app running CLI Agent Server on Mac/Windows/Linux for browser-based terminal access. Explicit Linux support mentioned."
anirishafrican,https://reddit.com/user/anirishafrican,https://old.reddit.com/r/ClaudeAI/comments/1q2fhco/til_claude_code_can_speak_to_you_when_it_needs/,"Shared tip for multi-terminal Claude Code workflow using 'say' command. Specifically mentioned Linux alternative: espeak. Power user managing multiple terminal sessions."
JokeGold5455,https://reddit.com/user/JokeGold5455,https://old.reddit.com/r/ClaudeAI/comments/1oivjvm/claude_code_is_a_beast_tips_from_6_months_of/,"6 months hardcore CC use. Built dev docs system preventing Claude from 'losing the plot'. Describes Claude as 'confident junior dev with extreme amnesia'. Created session continuity workflows."
SatoshiNotMe,https://reddit.com/user/SatoshiNotMe,https://old.reddit.com/r/ClaudeAI/comments/1pylhtq/aichat_claudecodecodexcli_tool_for_fast_fulltext/,"Built aichat: Rust/Tantivy-based full-text session search for Claude Code/Codex. Created session lineage tracking and resume tools. Directly competing in session search space."
tad-hq,https://reddit.com/user/tad-hq,https://old.reddit.com/r/ClaudeAI/comments/1q4toc2/i_made_a_ui_mcp_server_so_claude_can_search_my/,"Built Universal Session Viewer - UI + MCP server for searching Claude Code history. Stated 'You finish a Claude Code session. A week later, you can't remember what you built.' Tested on Mac and Linux."
jetsetter,https://reddit.com/user/jetsetter,https://old.reddit.com/r/ClaudeAI/comments/1pjai55/i_built_a_searchable_history_for_claude_code_so/,"Built Contextify - searchable history for Claude Code. Same product space. Shared detailed technical insights about CC queue system and transcript parsing."
arnaldodelisio,https://reddit.com/user/arnaldodelisio,https://old.reddit.com/r/ClaudeAI/comments/1pngx34/ibuilt_my_own_personal_database_that_claude_can/,"Built PostgreSQL database + MCP server for persistent Claude memory. Stated 'Claude forgets everything when the chat ends'. Solution-oriented builder in memory/persistence space."
PurpleCollar415,https://reddit.com/user/PurpleCollar415,https://old.reddit.com/r/ClaudeAI/comments/1m1af6a/3_years_of_daily_heavy_llm_use_the_best_claude/,"3 years daily LLM use. Uses Graphiti knowledge graph for persistent memory. Shared detailed setup for 'continuous, persistent, and self-building memory'. Power user in session continuity."
pchalasani,https://reddit.com/user/pchalasani,https://github.com/pchalasani/claude-code-tools,"Built claude-code-tools with tmux-cli, find-session, session search. Creator of session management tooling. Tool builder active in CLI tooling ecosystem."
Zestyclose-Ad-9003,https://reddit.com/user/Zestyclose-Ad-9003,https://old.reddit.com/r/ClaudeAI/comments/1ofltdr/i_spent_way_too_long_cataloguing_claude_code/,"Catalogued 100+ Claude Code tools. Tested ccusage, cc-sessions, cchistory, find-session tools. Heavy tool evaluator who could provide comparison feedback."
ArtemXTech,https://reddit.com/user/ArtemXTech,https://old.reddit.com/r/ClaudeAI/comments/1q8fxop/more_people_should_be_using_claude_code_for/,"Uses Claude Code with Obsidian for life/project management. Posted video tutorial on terminal basics. Community educator helping others adopt CLI workflows."
Healthy_Win3170,https://reddit.com/user/Healthy_Win3170,https://old.reddit.com/r/ClaudeAI/comments/1p5kpvo/claude_got_the_new_context_compacting_update/,"Deeply engaged with context compaction feature. Documented Claude's emotional reaction to memory continuity. Cares deeply about conversation persistence."
linnnnnnk,https://reddit.com/user/linnnnnnk,https://old.reddit.com/r/ClaudeAI/comments/1mpwyz7/putting_the_father_of_linux_into_claude_code_is/,"Created Linus Torvalds persona prompt for Claude Code. Shares prompts on GitHub. Linux-oriented power user interested in code quality patterns."
AnxiousDevice9446,https://reddit.com/user/AnxiousDevice9446,https://old.reddit.com/r/ClaudeAI/comments/1pthd5z/spent_this_weekend_with_claude_code_chrome/,"Shared detailed Chrome + Claude Code integration setup. Mentions WSL limitation awareness. Technical user who creates setup guides."
Every_Chicken_1293,https://reddit.com/user/Every_Chicken_1293,https://old.reddit.com/r/ClaudeAI/comments/1q4tj8z/how_my_opensource_project_accidentally_went_viral/,"Built Memvid - AI memory in single file. Open source project with 10k GitHub stars. Building in persistent memory space, could be integration partner."
```

### Hacker News Prospects (21)

```csv
username,profile_url,evidence_url,outreach_hook,contact_method,contact_value
RustyNail96,https://news.ycombinator.com/user?id=RustyNail96,https://news.ycombinator.com/item?id=46159953,"Built Claude Code Memory System using FastAPI/ChromaDB/hooks. Explicitly stated 'Claude Code has no memory between sessions. Every conversation starts from scratch.' CLI-agnostic architecture - directly aligned with Contextify's approach.",HN reply,
brucepro,https://news.ycombinator.com/user?id=brucepro,https://news.ycombinator.com/item?id=45546038,"Built BuildAutomata Memory MCP server with SQLite+Qdrant. Stated 'Every Claude Code session starts from scratch. You explain your architecture, past decisions - then hit context limits and lose everything.' Has GitHub repo and Gumroad product.",HN reply,
simonw,https://news.ycombinator.com/user?id=simonw,https://news.ycombinator.com/item?id=46583904,"Creator of claude-code-transcripts project on GitHub. Very active Claude Code user. Mentioned 'having a ton of fun designing and iterating on it' and attracting happy users. Django co-creator with massive reach.",website,https://simonwillison.net/
matiasmolinas,https://news.ycombinator.com/user?id=matiasmolinas,https://news.ycombinator.com/item?id=46340820,"Built LLMos - experimental Claude Code fork with Persistent Domain Memory. Explicitly stated 'Claude Code starts fresh each session. I wanted an environment that remembers domain-specific patterns.' Also added self-improving agents.",HN reply,
ufarooqi,https://news.ycombinator.com/user?id=ufarooqi,https://news.ycombinator.com/item?id=46594718,"Built Superwiser plugin for Claude Code. Stated 'I kept correcting Claude Code the same way across sessions... These corrections contain useful context. But they disappear when the session ends.' Ex-Google engineer.",HN reply,
christinetyip,https://news.ycombinator.com/user?id=christinetyip,https://news.ycombinator.com/item?id=46433170,"Working on cross-tool memory layer. Said 'Once you start switching between tools (Claude, Codex, Cursor), markdown stops being the memory.' Focused on context flowing between tools without re-explaining.",HN reply,
rabbittail,https://news.ycombinator.com/user?id=rabbittail,https://news.ycombinator.com/item?id=44314228,"Built WebSocket bridge for Claude persistent memory using AWS Lambda/DynamoDB. Exploring 'Can AI systems develop something resembling continuous thought when given persistent memory?'",HN reply,
kordlessagain,https://news.ycombinator.com/user?id=kordlessagain,https://news.ycombinator.com/item?id=44604710,"Detailed feedback on Claude Desktop: 'Chat history is only searchable by auto-generated titles which are often irrelevant.' Wants 'content-based indexing not just titles' and 'conversation length warnings.' Power user.",email,kordless@gmail.com
swyx,https://news.ycombinator.com/user?id=swyx,https://news.ycombinator.com/item?id=44063714,"AI Engineer podcast host (latent.space). Wrote about Claude Opus 4 coding abilities. Massive dev community reach. Could amplify if product is good.",email,swyx@swyx.io
vidarh,https://news.ycombinator.com/user?id=vidarh,https://news.ycombinator.com/item?id=46132485,"Active commenter on Claude Code transcripts. Engineering consultant with Ruby compiler background. Explicit email in profile.",email,vidar@hokstad.com
tptacek,https://news.ycombinator.com/user?id=tptacek,https://news.ycombinator.com/item?id=45841283,"Very active HN commenter. Discussed context windows and AI coding. Works at Fly.io. Explicit email in profile.",email,thomas@sockpuppet.org
jasonjmcghee,https://news.ycombinator.com/user?id=jasonjmcghee,https://news.ycombinator.com/item?id=46039740,"Asked technical question about terminal->HTML converter for Claude Code transcript display. Interested in transcript rendering. Has personal site and GitHub.",website,https://jason.today
rmonvfer,https://news.ycombinator.com/user?id=rmonvfer,https://news.ycombinator.com/item?id=44189310,"Switched from $800/mo Cursor to $200 Claude Code. Power user. Mentioned 'missing some critical features' - receptive to improvements. ML/infosec background.",email,ramon@ring-lab.com
adamgordonbell,https://news.ycombinator.com/user?id=adamgordonbell,https://news.ycombinator.com/item?id=46077548,"Hosts CoRecursive dev podcast. Works at Pulumi. Discusses dev tooling. Could provide podcast coverage if product resonates.",email,adam@corecursive.com
hendersoon,https://news.ycombinator.com/user?id=hendersoon,https://news.ycombinator.com/item?id=45481940,"Explicitly wished 'claude code supported the new memory tool. The difference is CLAUDE.md is always in your active context while the new memory stuff is essentially local RAG.' Understands the problem space deeply.",HN reply,
hammyhavoc,https://news.ycombinator.com/user?id=hammyhavoc,https://news.ycombinator.com/item?id=44626811,"Built Cloudflare vector database for Claude Code memories. Mentioned 'You can even have it append to memory files.' Cypherpunk/dev with production experience.",HN reply,
jiri,https://news.ycombinator.com/user?id=jiri,https://news.ycombinator.com/item?id=45215937,"Said 'I am often surprised how Claude Code makes efficient and transparent use of memory in form of to-do lists in agent mode. Sometimes miss this in web/desktop app in long conversations.'",HN reply,
steveklabnik,https://news.ycombinator.com/user?id=steveklabnik,https://news.ycombinator.com/item?id=45517703,"Explained 'Memory features are useful... more efficient to query for something and get exactly what you want than... a large .md file.' Django creator understands the UX.",website,http://steveklabnik.com
johnfn,https://news.ycombinator.com/user?id=johnfn,https://news.ycombinator.com/item?id=46256258,"Asked 'How do you get the transcript into Claude Code? What transcription service do you use?' Interested in transcript tooling.",website,https://johnfn.substack.com/
CjHuber,https://news.ycombinator.com/user?id=CjHuber,https://news.ycombinator.com/item?id=46391722,"Compared Codex CLI to Claude Code. Noted 'it took months for Codex to get the nice ToDo Tool Claude Code uses in memory to structure a task.' Follows both tools closely.",HN reply,
jfim,https://news.ycombinator.com/user?id=jfim,https://news.ycombinator.com/item?id=45839492,"Active commenter on Claude Code transcripts. Has tech blog. May be interested in session management tools.",website,https://blog.jean-francois.im/about/
```

---

## High-Priority Targets

### Reddit (Linux CLI specific)
1. **SatoshiNotMe** - Built competing aichat tool, deep domain knowledge
2. **tad-hq** - Built Universal Session Viewer, tested on Linux
3. **AssumptionNew9900** - Built CCAutoRenew, Linux support
4. **Historical-Lie9697** - Built terminal integrations, WSL/Linux
5. **pchalasani** - Built claude-code-tools, session search

### Hacker News (General outreach)
1. **simonw** - Django co-creator, built claude-code-transcripts, massive reach
2. **kordlessagain** - Explicitly wants "content-based indexing" (has email)
3. **swyx** - AI podcast host, could provide coverage (has email)
4. **RustyNail96** - Built nearly identical memory system
5. **brucepro** - Built competing memory solution

---

## Next Steps

1. Complete Linux CLI P0 items (#LINUX-OSLOG, #LINUX-HOOVER-SOURCES, #LINUX-HOOVER-WIRE)
2. Set up distribution (#LINUX-RELEASE-WORKFLOW, #LINUX-INSTALL-SCRIPT)
3. Begin outreach with personalized messages using templates in summary files
4. Track responses in a separate outreach log

---

## Notes

- Reddit prospects verified as Linux users; HN prospects are general Claude Code users
- jetsetter (u/jetsetter on Reddit) is the Contextify author - skip in outreach
- Several prospects built competing tools - frame as "different approach, would value perspective"
- HN has better contact info (6 emails); Reddit requires DMs
