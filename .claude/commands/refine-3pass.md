You will perform a three-pass refinement of a document, considering the conversation context.

## Input Detection

First, determine what document to refine:

**If a file path is provided as an argument:**
- Use that file path directly

**If no argument is provided:**
- Review the conversation for recently mentioned files or analyses
- Look for documents in `/tmp/` that were discussed
- If **unclear which file** to refine, ask:
  - "I see references to file X and file Y. Which should I refine?"
  - "Should I refine the bug analysis or the architecture document?"
  - Or list the candidate files and ask the user to specify

**Only proceed once you have a clear file path.**

## Efficiency Guidelines
- **Incremental improvements**: Make targeted edits rather than full rewrites when possible
- **Growth budget**: Target 1.5-2x original length; avoid exceeding 3x
- **Separate concerns**: Review notes go in separate files to keep main document clean
- **Pass 3 selectivity**: Systems review should add strategic value, not bulk

## When to Use 3-Pass vs 2-Pass
- ✅ **Use 3-pass for**: Architecture decisions, post-mortems, scaling plans, security audits
- ⚠️ **Consider 2-pass for**: Bug analyses, feature specs, code reviews, straightforward docs

## Process

### Pass 1: Technical Deep Dive

Review the document as a domain expert. Focus on:
- **Technical accuracy**: Are the conclusions correct? Any logical errors?
- **Evidence quality**: Is the evidence sufficient and properly cited?
- **Root cause analysis**: Is the causal chain complete and sound?
- **Gaps**: What's missing? What assumptions need validation?

Consider the conversation context for additional context about what needs improvement.

**Deliverables:**
1. `/tmp/<original-basename>-pass1.md` - Improved document with corrections and additions
2. `/tmp/<original-basename>-pass1-notes.md` - Review notes explaining what changed and why

**Approach:**
- Copy the original to pass1.md as your starting point
- Use the Edit tool to make targeted improvements where possible
- Add new sections only where critical gaps exist
- Keep improvements focused on accuracy and evidence

### Pass 2: Experienced Colleague Critique

Review the Pass 1 output with fresh eyes. Focus on:
- **Completeness**: Are there missing perspectives or edge cases?
- **Organization**: Is the structure logical? Does it flow well?
- **Clarity**: Will a teammate understand this in 6 months?
- **Actionability**: Are next steps clear and specific?

**Deliverables:**
1. `/tmp/<original-basename>-pass2.md` - Further improved document
2. `/tmp/<original-basename>-pass2-notes.md` - Review notes for this pass

**Approach:**
- Copy pass1.md to pass2.md as your starting point
- Use Edit tool to reorganize, clarify, and enhance actionability
- Add metrics, examples, or test plans where they add decision-making value
- Avoid adding content that's "nice to have" vs "need to have"

### Pass 3: Systems Reviewer

**IMPORTANT**: Before starting Pass 3, assess if it's needed:
- If this is a bug fix or straightforward analysis, consider skipping to Final
- If this requires architecture/scale/observability thinking, proceed with Pass 3

Review the Pass 2 output from a systems perspective. Focus on:
- **Integration**: How does this fit into the broader system architecture?
- **Performance & Scale**: Are there performance implications? Concurrency issues?
- **Observability**: Are there sufficient telemetry/logging recommendations?
- **Risk assessment**: What could go wrong? What are the failure modes?
- **Long-term maintenance**: Will this age well? Technical debt concerns?

**Deliverables:**
1. `/tmp/<original-basename>-pass3.md` - Systems-enhanced document
2. `/tmp/<original-basename>-pass3-notes.md` - Review notes for this pass

**Approach:**
- Copy pass2.md to pass3.md as your starting point
- Use Edit tool to add systems perspective
- Add ONLY content that informs strategic decisions (avoid aspirational lists)
- If adding observability/metrics, ensure they're actionable and prioritized
- Target growth: If pass3 would be >2x pass2 length, consolidate instead of expanding

### Final: Reflowed Document

Create a polished final version at `/tmp/<original-basename>-final.md`:
- Start from pass3.md (or pass2.md if Pass 3 was skipped) as the base
- Make final polish edits for tone and flow
- Ensure consistent structure throughout
- Add a version footer: `---\n*Document refined through 3-pass review process*`

**Note:** Do NOT write a completely new document. The final version should be pass3.md with minimal polish edits.

## Output Format

After completing all passes, provide the user with:
1. Summary of key improvements made across all passes (be specific and concise)
2. Paths to all generated files (pass1, pass2, pass3, final, and all -notes files)
3. Document growth metrics:
   - "Original: X lines → Pass 1: Y lines → Pass 2: Z lines → Final: W lines"
   - "Growth factor: A.Bx"
4. Assessment: Which pass added the most value?
5. Any remaining concerns or areas that may need human judgment