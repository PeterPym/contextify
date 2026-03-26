# Total Recall: Use Case Taxonomy

Preliminary taxonomy based on 12 proof points. Will be refined after the full usage analysis (54 invocations across 29 sessions) completes.

## Use Cases

| Category | Description | Frequency | Example |
|----------|-------------|-----------|---------|
| **Decision Recall** | "What did we decide about X?" | Common | Recalling a design decision from weeks ago |
| **Implementation Reference** | "How did we implement X?" | Common | Finding code patterns or approaches from past sessions |
| **Cross-Session Continuity** | Picking up where a previous session left off | Common | Loading context from an interrupted or exhausted session |
| **Knowledge Search** | "What do we know about X?" | Common | Searching for accumulated knowledge on a topic |
| **Debugging History** | "When did this break?" / "Did we see this before?" | Moderate | Tracing when a bug was introduced or previously analyzed |
| **Incident Forensics** | Tracing a chain of events across sessions | Moderate | Finding which command caused a destructive operation |
| **Counting/Audit** | "How many times did we X?" | Occasional | Frequency analysis, tracking patterns |
| **Cross-Project Search** | Finding info from a different project | Occasional | Searching consulting work from a personal project |
| **Negative Proof** | Confirming something was never discussed | Occasional | Proving a gap was an oversight, not a design choice |
| **Self-Referential** | Using Total Recall to improve Total Recall | Rare | Meta-usage for product development |
| **Proof Gathering** | Finding evidence/citations for a claim | Rare | Building proof points for docs, marketing |
| **Session Handoff** | Loading context for a new session/worktree | Common | Bootstrapping a new session with prior knowledge |

## Taxonomy Notes

- Categories are not mutually exclusive. An invocation can serve multiple purposes.
- "Common/Moderate/Occasional/Rare" is estimated from proof points. The full usage analysis will provide actual frequency data.
- Self-referential usage (improving Total Recall with Total Recall) is a unique category worth highlighting in marketing, even though it's rare.
