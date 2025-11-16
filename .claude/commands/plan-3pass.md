Based on the conversation above, you will perform a three-pass planning process to create an implementation plan.

## Context Detection

First, determine what needs to be planned:
- Review the conversation history for discussions of features, bugs, or improvements
- Look for code exploration, log analysis, or problem descriptions
- If the subject is **unclear or ambiguous**, ask clarifying questions before proceeding:
  - "I see discussion of X and Y. Which should I plan for?"
  - "Should I focus on the bug fix or the performance improvement?"
  - "What's the scope: just the mtime issue, or the entire discovery pipeline?"

**Only proceed once you clearly understand what to plan.**

## Efficiency Guidelines
- **Incremental refinement**: Build on previous pass rather than restarting from scratch
- **Focused additions**: Add only what's missing or incorrect, not redundant detail
- **Concise output**: Target a clear, actionable plan; avoid unnecessary elaboration
- **Pass 3 selectivity**: Add systems perspective only when it changes implementation decisions

## When to Use 3-Pass vs 2-Pass
- ✅ **Use 3-pass for**: Complex features, architectural changes, performance-critical code, concurrent systems
- ⚠️ **Consider 2-pass for**: Bug fixes, straightforward features, well-understood patterns

## Pass 1: Root-Cause Walkthrough

Conduct a root-cause walkthrough of the current system:
- Follow the relevant control flow from entry point to effect
- Cite the files/lines along the way
- Call out any assumptions you're making
- Describe implementation steps, referencing exact places in the code where those steps will integrate

**Output:** Present your analysis and initial implementation plan.

## Pass 2: Experienced Colleague Review

Take the role of a more experienced colleague and cross-examine your Pass 1 plan:
- Re-check the cited files and assumptions
- Look for architectural mismatches or missing steps
- Identify edge cases or failure modes
- Assess if the plan is over-engineered or under-specified

**Output:** Refine the Pass 1 plan by:
- Editing or correcting sections that need improvement
- Adding missing considerations (not rewriting correct sections)
- Maintaining a single cohesive implementation plan

## Pass 3: Systems Reviewer

**IMPORTANT**: Before starting Pass 3, assess if it's needed:
- Will systems thinking (performance, scale, observability) change the implementation approach?
- If the answer is "no" or "minor", present the Pass 2 plan as final

If proceeding, adopt a broader system perspective:
- **Performance & Concurrency:** Will this scale? Any threading issues?
- **Integration:** Does this cleanly integrate with adjacent components? Any hidden coupling?
- **Telemetry & Validation:** Are there sufficient logs, tests, and validation steps?
- **Error Handling:** What can go wrong and how will it be detected?

**Output:** Refine the Pass 2 plan by:
- Incorporating system-level concerns that affect implementation
- Adding observability/testing steps only if they're critical (avoid "nice to have" lists)
- Keeping the plan focused and actionable

**Important:** After all passes, present the final plan as a single cohesive implementation document. The plan should incorporate all feedback smoothly rather than listing separate review sections or accumulating redundant detail.