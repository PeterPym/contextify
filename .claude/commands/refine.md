You will refine a document using an appropriate level of rigor based on the document type and purpose.

## Input Detection

First, determine what document to refine:

**If a file path is provided as an argument:**
- Use that file path directly

**If no argument is provided:**
- Review the conversation for recently mentioned files or analyses
- Look for documents in `/tmp/` that were discussed
- If **unclear which file** to refine, ask the user to specify

## Document Type Assessment

Next, assess the document type to choose the right review depth:

**Use 2-pass process for:**
- Bug analyses
- Feature specifications
- Code review summaries
- Straightforward technical docs
- Implementation plans

**Use 3-pass process for:**
- Architecture decision records
- Post-incident reviews
- Scaling/performance plans
- Security audits
- Cross-system integration docs

If uncertain, default to 2-pass (you can always run `/refine-3pass` if more depth is needed).

## Execute Selected Process

Once you've chosen 2-pass or 3-pass, follow the corresponding workflow from `/refine-2pass` or `/refine-3pass`:

### For 2-Pass:
1. **Pass 1**: Technical deep dive (accuracy, evidence, gaps)
2. **Pass 2**: Colleague critique (completeness, clarity, actionability)
3. **Output**: Final polished document + separate review notes

**Files created:**
- `/tmp/<basename>-pass1.md` + `-pass1-notes.md`
- `/tmp/<basename>-pass2.md` + `-pass2-notes.md`
- `/tmp/<basename>-final.md`

### For 3-Pass:
1. **Pass 1**: Technical deep dive
2. **Pass 2**: Colleague critique
3. **Pass 3**: Systems review (if it adds strategic value)
4. **Output**: Final polished document + separate review notes

**Files created:**
- `/tmp/<basename>-pass1.md` + `-pass1-notes.md`
- `/tmp/<basename>-pass2.md` + `-pass2-notes.md`
- `/tmp/<basename>-pass3.md` + `-pass3-notes.md`
- `/tmp/<basename>-final.md`

**Note:** State which process you selected and why at the beginning of your response, along with document growth metrics.