---
title: Product Roadmap & Research
type: exploratory
related: TODOS.md
description: Ideas, research questions, future possibilities. P4-P5 priority.
promotes_to: TODOS.md (once actionable)
priority_levels:
  P4: Future considerations - good ideas needing research/design before implementation
  P5: Research/exploratory - questions to investigate, no commitment to build
---

# Product Roadmap & Research

> **Exploratory ideas, research questions, and future possibilities.** Once scoped and actionable, items promote to [TODOS.md](TODOS.md).

---

## P4 (Future Considerations)

### P4-AUTONOMOUS-DEVELOPMENT: Self-Managing Development Pipeline

**Status:** Vision/concept
**Priority:** P4 (far future, research needed)
**Effort:** Very Large (multi-month initiative)

- [ ] Design and implement autonomous development agent for TODO management and execution

**Grand Vision:**
Owner only needs to review progress. Agent handles:
- TODO priority updates based on market signals
- Automatic task execution where safe/feasible
- Integration of external monitoring data

**Inputs:**
- Market research watchers (competitive analysis, feature trends)
- Transcript format watchers (upstream CLI changes)
- Customer support data (stubbed in `app/Sources/ContextifyCore/CustomerSupport/`)
- Build/test results
- Repository activity

**Agent Capabilities:**
1. **Priority Management**
   - Review TODOS.md regularly
   - Adjust priorities based on market signals, user feedback, technical dependencies
   - Flag stale items, suggest consolidation

2. **Autonomous Execution** (where safe)
   - Documentation updates
   - Test fixes
   - Dependency updates
   - Low-risk refactoring

3. **Human-in-Loop for Critical Work**
   - Submit PRs for review
   - Flag breaking changes
   - Request approval for architectural decisions

**Key Challenges:**
- Safety boundaries (what can agent change autonomously?)
- Quality assurance (how to validate agent work?)
- Cost management (LLM API usage)
- Error recovery (agent introduces bugs)

**Research Questions:**
1. What percentage of TODOs are "safe" for autonomous execution?
2. How to validate agent work without human review bottleneck?
3. What approval workflows enable speed without sacrificing safety?
4. How to integrate with existing git workflows (branch naming, PR templates)?

**Related Work:**
- TODOS.md#P2-TODOS-AGENT (intelligent TODO management - **promoted to P2**)
- TODOS.md#P3-AGENTIC-DEVOPS (transcript monitoring, conformance testing)
- Customer support stub (`CustomerSupport/` module)

---

## P5 (Research / Exploratory)

### P5-INVESTIGATE-TRANSCRIPT-PROVIDERS: Other AI Tool Transcript Support

**Status:** Not started
**Priority:** P5 (exploratory, no current demand)
**Effort:** Low (initial survey), Variable (per-provider integration)

- [ ] Research transcript formats from other AI coding tools

**Candidates:** Cursor, Windsurf, Gemini CLI, Warp, Aider, Continue.dev

**Research Questions:**
1. Where stored? (local files, cloud, proprietary DB)
2. What format? (JSONL, SQLite, proprietary)
3. Documented/stable?
4. User demand?

**Potential Outcomes:**
- "Multi-provider" value prop for Contextify
- Broader market for the app
- Insights into transcript format best practices

---

**End of Roadmap**
