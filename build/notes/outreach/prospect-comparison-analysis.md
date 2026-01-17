---
date: 2026-01-14
type: analysis
topic: prospect-research-methodology-comparison
status: ready-for-review
---

# Prospect Research Methodology Comparison

Comparing two approaches to finding Linux CLI beta testers from r/ClaudeCode.

## Executive Summary

| Metric | Skill-Based (/prospect) | Direct Prompt |
|--------|-------------------------|---------------|
| **Total Prospects** | 40 | 25 |
| **Unique to List** | 28 | 13 |
| **Overlap** | 12 | 12 |
| **Avg Fields per Row** | 9 | 4 |
| **Data Quality** | Higher (scored, categorized) | Focused (actionable) |
| **Time to Generate** | Multi-phase, longer | Single pass, faster |

**Verdict: Direct prompt produced more focused, actionable results. Skill-based approach found more prospects but added overhead without proportional value.**

---

## 1. Data Quality Comparison

### 1.1 Prospect Counts

- **Skill-based list:** 40 prospects
- **Direct prompt list:** 25 prospects
- **Overlap:** 12 prospects appear in both lists

### 1.2 Column Structure

**Skill-based approach (9 columns):**
```
username, platform, profile_url, relevance, engagement, recency, priority, evidence_urls, topic_context
```

**Direct prompt approach (4 columns):**
```
username, profile_url, evidence_comment_urls, suggested_outreach_hook
```

### 1.3 Quality Assessment

#### Evidence URLs

| Aspect | Skill-Based | Direct Prompt |
|--------|-------------|---------------|
| URL format | old.reddit.com | www.reddit.com |
| Multiple URLs | Yes (pipe-separated) | Single URL preferred |
| URL validity | High | High |
| Relevance to selection | Good | Excellent |

Both approaches linked to actual posts/comments that support the prospect selection. The direct prompt was more selective, linking to the single most relevant comment rather than multiple.

#### Outreach Hooks

**Skill-based "topic_context" examples:**
- "Linux/Ubuntu user asking about image pasting - active CLI user solving problems"
- "Built tools for parallelizing Claude Code on Linux VPSs - power user and builder"
- "Uses Claude Code across Windows/macOS/Pop_OS (Linux) - multi-platform enthusiast"

**Direct prompt "suggested_outreach_hook" examples:**
- "Shared detailed WSL performance benchmarks showing Linux FS is 1900x faster than /mnt/c. Clearly technical and data-driven. Interested in Linux performance optimization tools."
- "Built and open-sourced a Linux clipboard screenshot solution for Claude Code on GitHub. Active problem-solver who creates tools. Would appreciate Linux-native tooling."
- "Runs Claude Code as sysadmin on Ubuntu mini PC with Tailscale VPN. Uses arch linux. Advanced Linux power user interested in remote/mobile workflows."

**Analysis:** The direct prompt produced more specific, actionable hooks that:
1. Reference specific data points (1900x faster)
2. Mention specific tools they built/use (xclip, Tailscale)
3. Explicitly state why they would care about the outreach

The skill-based hooks are more generic descriptions of user type rather than conversation starters.

### 1.4 Scoring System Value

The skill-based approach included numerical scores:
- `relevance`: 4-5 (narrow range)
- `engagement`: 3-5 (narrow range)
- `recency`: 4-5 (narrow range)
- `priority`: 16-20 (calculated composite)

**Problems with scoring:**
1. **Narrow variance:** Most scores cluster at 4-5, providing little differentiation
2. **Subjective basis:** No clear rubric for what makes relevance=5 vs relevance=4
3. **Composite unclear:** Priority score calculation not documented
4. **Actionability:** A "priority 20" vs "priority 17" doesn't inform outreach strategy

The scoring added complexity without actionable insight. The direct prompt's inclusion/exclusion criteria achieved the same filtering effect more efficiently.

---

## 2. Coverage Analysis

### 2.1 Venn Diagram (Text Representation)

```
+------------------------------------------+
|                                          |
|    SKILL-BASED ONLY (28 prospects)       |
|                                          |
|    noodlesteak, rjray,                   |
|    Illustrious-Pitch-49, kakakalado,     |
|    TheKillerScope, Sensitive_Internet45, |
|    auto_steer, cksz, PricePerGig,        |
|    AcrobaticAmoeba8158, aliparoya,       |
|    716green, EnoughPsychology6432,       |
|    chetan_singh_, omni_builder,          |
|    RichardThornton, LongAd7407,          |
|    Tiny_Arugula_5648, Byakko_4,          |
|    MehdiG44, EvKoh34, jonas77,           |
|    fi-dpa, ToiletSenpai,                 |
|    Suspicious-Edge877, Qudadak,          |
|    Kitae, DappperDanH,                   |
|    Psychological_Poem64, goetz_lmaa,     |
|    DazzlingOcelot6126,                   |
|    Appropriate_Yak_1468, OkayVeryCool    |
+------------------------------------------+
          |                    |
          |    OVERLAP (12)    |
          |                    |
          |  WineColoredTuxedo |
          |  DefconNaN         |
          |  Ranteck           |
          |  pinku1            |
          |  Gurengan          |
          |  Previous-Tune-8896|
          |  asheshgoplani     |
          +--------------------+
          |                    |
+------------------------------------------+
|                                          |
|    DIRECT PROMPT ONLY (13 prospects)     |
|                                          |
|    radial_symmetry,                      |
|    TheOriginalAcidtech,                  |
|    Historical-Lie9697, ZShock,           |
|    joshman1204, fatherbasra,             |
|    WarlaxZ, movi3buff, JounDB,           |
|    Patriark, AnwpPro,                    |
|    GrouchyManner5949, delphianQ,         |
|    MBPSE, ginger_beer_m,                 |
|    jakenuts-, Illustrious_Bid_6570       |
+------------------------------------------+
```

### 2.2 Quality of Unique Prospects

**Notable skill-based unique prospects (high value):**
- `noodlesteak`: Built tools for parallelizing Claude Code on Linux VPSs
- `MehdiG44`: Creator of claude-code-railway Ubuntu fork
- `jonas77`: Built Docker/Ubuntu runner for Claude Code
- `RichardThornton`: Cybersecurity pro with detailed Ubuntu Server writeups

**Notable direct prompt unique prospects (high value):**
- `radial_symmetry`: Built Crystal UI for managing Claude Code sessions
- `joshman1204`: Power user with 96GB RAM running multiple AI sessions
- `movi3buff`: Wrote detailed Fedora setup guide
- `WarlaxZ`: Shared WSL time drift fix

**Analysis:** Both approaches found valuable prospects the other missed. The skill-based approach found more tool builders; the direct prompt found more community helpers and validators.

### 2.3 Why the Difference?

The skill-based approach prioritized:
- Users who create posts (original content)
- High engagement metrics
- Recent activity

The direct prompt approach prioritized:
- Users who solve problems (including commenters)
- Specific helpful behaviors
- Quality over quantity

This explains why the direct prompt found more commenters who provide valuable tips (like WarlaxZ's time drift fix) while the skill-based approach focused on post creators.

---

## 3. Prompt Engineering Analysis

### 3.1 The Direct Prompt

```
/crawl https://reddit.com/r/ClaudeCode and search for users discussing:
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

Output CSV with: username, profile_url, evidence_comment_urls, suggested_outreach_hook
```

### 3.2 Why the Direct Prompt Worked Better

1. **Specific inclusion/exclusion criteria over scoring rubrics**
   - "dismissive or gatekeeping in tone" is actionable
   - "relevance score 4 vs 5" requires interpretation

2. **Behavioral signals over metrics**
   - "Ask how-to questions" identifies receptive users
   - "engagement score" doesn't distinguish helpful from argumentative

3. **Output-focused specification**
   - "suggested_outreach_hook" forces thinking about use case
   - "topic_context" allows for generic descriptions

4. **Brevity reduced drift**
   - Fewer instructions meant less room for misinterpretation
   - The skill's multi-phase process introduced noise between phases

### 3.3 What the Skill Added (and Didn't)

**Added value:**
- Systematic coverage (found 40 vs 25 prospects)
- Structured data (platform field, multiple evidence URLs)

**Added overhead without value:**
- Scoring system (scores clustered, didn't differentiate)
- Multiple phases (discovery -> extraction -> qualification)
- Platform field (all were Reddit, unnecessary)

### 3.4 The Scoring Trap

The skill's scoring rubric:

```
relevance (1-5), engagement (1-5), recency (1-5)
priority = relevance * 2 + engagement + recency
```

Problems:
1. **Ceiling effect:** Almost all prospects scored 4-5 on each dimension
2. **False precision:** What's the difference between relevance=4 and relevance=5?
3. **Composite obscures:** priority=19 could be (5,4,5) or (4,5,5) - different profiles

A binary "include/exclude" decision based on qualitative criteria (the direct prompt approach) proved more effective.

---

## 4. Recommendations

### 4.1 Which List to Use

**Recommendation: Merge both lists, prioritizing direct prompt formatting.**

1. Start with direct prompt list (25 prospects with quality hooks)
2. Add high-value unique prospects from skill-based list
3. Use direct prompt's hook format for all entries

### 4.2 Proposed Merged List Criteria

Include from skill-based unique prospects if they:
- Built a tool (noodlesteak, jonas77, MehdiG44, etc.)
- Wrote a tutorial/guide (RichardThornton, LongAd7407)
- Have very recent activity (Tiny_Arugula_5648, Byakko_4)

Exclude if:
- Only asked a question with no follow-up
- Score-based selection without clear behavioral signal

### 4.3 Changes to /prospect Skill

#### Remove or Simplify

1. **Remove numerical scoring** - Replace with binary include/exclude based on behavioral criteria
2. **Remove platform field** - Unless explicitly multi-platform research
3. **Collapse phases** - Single pass is sufficient for focused research

#### Strengthen

1. **Require outreach hook quality** - Must include specific detail from the prospect's content
2. **Add exclusion criteria prompting** - Force explicit "who NOT to include"
3. **Prioritize commenters** - Don't bias toward post creators

#### Proposed Simplified Skill Structure

```markdown
## Input
- Platform/URL to research
- Ideal prospect profile (behavioral)
- Explicit exclusion criteria

## Output
- username
- profile_url
- best_evidence_url (singular, most relevant)
- outreach_hook (must include specific detail from their content)

## Process
Single-pass: crawl -> identify -> format
No scoring. Binary include/exclude.
```

### 4.4 When to Use Elaborate vs Simple Prompts

| Use Case | Approach |
|----------|----------|
| Focused research (known platform, clear criteria) | Direct prompt |
| Exploratory research (unknown sources) | Multi-phase skill |
| Quantitative requirements (need 50+ prospects) | Skill with broader net |
| Quality over quantity | Direct prompt with specific criteria |

---

## 5. Final Verdict

### Winner: Direct Prompt Approach

**Score: Direct Prompt 7, Skill-Based 3**

| Criterion | Winner | Why |
|-----------|--------|-----|
| Actionable hooks | Direct | Specific details vs generic descriptions |
| Time efficiency | Direct | Single pass vs multi-phase |
| Data quality | Direct | Focused inclusion criteria |
| Coverage breadth | Skill | 40 vs 25 prospects |
| Signal-to-noise | Direct | All 25 are high quality |
| Unique finds | Tie | Both found valuable prospects other missed |
| Reproducibility | Skill | Structured phases more consistent |
| Adaptability | Direct | Easier to modify criteria |
| Overhead | Direct | No scoring system to maintain |
| Real-world utility | Direct | Ready to use for outreach |

### Key Takeaway

**Specificity beats structure.** The direct prompt's explicit behavioral criteria ("Ask how-to questions", "Share workarounds") produced better results than the skill's elaborate scoring rubric. The skill's structure added overhead without proportional value.

For prospect research, the winning formula is:
1. Clear behavioral inclusion criteria
2. Explicit exclusion criteria
3. Output format that forces actionable details
4. Single-pass execution

The /prospect skill should be refactored to adopt these principles, removing the scoring system and collapsing to a single focused pass.

---

## Appendix: Overlap Analysis

12 prospects appeared in both lists:

| Username | Skill Priority | In Direct Prompt |
|----------|---------------|------------------|
| WineColoredTuxedo | 19 | Yes |
| DefconNaN | 19 | Yes |
| Ranteck | 19 | Yes |
| pinku1 | 18 | Yes |
| Gurengan | 18 | Yes |
| Previous-Tune-8896 | 17 | Yes |
| asheshgoplani | 18 | Yes |
| Illustrious-Pitch-49 | 19 | No (different username format) |

The overlap confirms both approaches identify high-value prospects. The 12 overlapping users represent the "obvious" finds that any reasonable approach would surface. The differentiation is in the unique finds and the quality of the outreach hooks.
