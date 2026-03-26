# Cloud Sync: Value Propositions

Source: ct-390 product brief (attachment 388d619e) and deployed page at website/cloud/index.html.

## One-liner

Your AI conversation history, searchable from every machine you work on.

## Elevator pitch

Contextify Cloud syncs your Claude Code and Codex conversation history across all your machines into one searchable record. Local-first: the app works offline, cloud adds cross-device search, backup, and team features on top. Set it up in Settings, everything else is automatic.

## Core value propositions

### For individuals

#### 1. Never lose a conversation again
Your AI history survives machine changes, disk failures, OS reinstalls, and Claude Code's 30-day auto-delete. Backed up continuously in the background.

#### 2. Search from any machine
Find that fix you wrote on your work laptop from your personal Mac. Or open cloud.contextify.sh in a browser and search there.

#### 3. Linux + Mac, one history
The Linux CLI pushes sessions to the same cloud. SSH into a server, use Claude Code, search the session from your Mac later. Everything ends up in the same index.

### For teams

#### 4. Shared searchable history
On Team plans, your engineers' AI sessions become searchable across the group. Someone solved this three months ago? Anyone on the team can find that conversation.

#### 5. Understand AI adoption
Usage analytics show conversations per day, active projects, and per-user activity. Real data for understanding adoption, not surveys.

#### 6. Onboard with context
New hires can search past AI conversations to understand how things were built, what was considered and rejected, and why the code looks the way it does.

### Universal

#### 7. Local-first, cloud-additive
The app works fully offline with all core features. Cloud adds capabilities on top without changing the local experience. Your local SQLite database is always the primary copy.

#### 8. Per-project sync control
Choose which projects sync on each device. Admins can set a server-side allowlist to restrict what the cloud accepts. Two independent layers.

## Target audiences

| Audience | Primary pain | What resonates |
|----------|-------------|---------------|
| Solo dev, multiple machines | "I solved this on my other laptop" | Cross-device search, backup |
| Solo dev, Linux servers | SSH sessions lost after disconnect | Linux + Mac unified history |
| Team lead | No visibility into AI adoption | Analytics, shared search |
| New hire | No context on how things were built | Onboarding with search |
| Security-conscious dev | "Where does my data go?" | Opt-in, local-first, per-project control |

## What it is NOT

- Not file sync (Dropbox). Syncs structured, parsed data with deduplication.
- Not a replacement for the local app. Cloud is additive.
- Not always-on. Opt-in, can be disabled at any time.
- Not AI processing in the cloud. LLM summaries run locally on your Mac.

## Competitive positioning

| Competitor approach | What Contextify Cloud does differently |
|--------------------|-----------------------------------------|
| Dropbox/iCloud sync of DB files | Structured sync with dedup, concurrent multi-device access |
| Notion/Obsidian cloud | Purpose-built for AI conversation history, not generic docs |
| AI tool built-in history | Cross-tool (Claude Code + Codex), persists beyond tool deletion |

## Known limitations (for honest copy)

- No end-to-end encryption (TLS in transit, not at rest)
- Self-hosted option not yet documented for general use
- Team search is web-dashboard only (not yet in CLI Total Recall)
- Total Recall across team history is future work
