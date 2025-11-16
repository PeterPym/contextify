Based on the conversation above, you will perform a two-pass planning process to create an implementation plan.

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

**Important:** Present the refined plan as a single document, not as "Pass 1 output + Pass 2 changes". Integrate feedback smoothly rather than listing separate review sections.