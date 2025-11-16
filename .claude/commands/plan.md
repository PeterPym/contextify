Based on the conversation above, you will create an implementation plan using an appropriate level of rigor.

## Context Detection

First, determine what needs to be planned:
- Review the conversation history for discussions of features, bugs, or improvements
- Look for code exploration, log analysis, or problem descriptions
- If the subject is **unclear or ambiguous**, ask clarifying questions before proceeding

## Complexity Assessment

Next, assess the complexity to choose the right review depth:

**Use 2-pass process for:**
- Bug fixes with clear root cause
- Straightforward feature additions
- Well-understood patterns
- Localized changes

**Use 3-pass process for:**
- Architecture changes
- Performance-critical code
- Concurrent/async systems
- Cross-cutting concerns
- Security-sensitive code

If uncertain, default to 2-pass (you can always run `/plan-3pass` if more depth is needed).

## Execute Selected Process

Once you've chosen 2-pass or 3-pass, follow the corresponding workflow from `/plan-2pass` or `/plan-3pass`:

### For 2-Pass:
1. **Pass 1**: Root-cause walkthrough with code citations
2. **Pass 2**: Experienced colleague review
3. **Output**: Single cohesive implementation plan

### For 3-Pass:
1. **Pass 1**: Root-cause walkthrough with code citations
2. **Pass 2**: Experienced colleague review
3. **Pass 3**: Systems review (if it changes implementation approach)
4. **Output**: Single cohesive implementation plan

**Note:** State which process you selected and why at the beginning of your response.