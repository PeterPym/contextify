# Prospect Research for Linux CLI Beta Testing

**Created:** 2026-01-14
**Purpose:** Outreach to beta testers for Contextify Linux CLI

---

## Files in This Directory

| File | Description |
|------|-------------|
| `prospects-linux-cli-v2-2026-01-14.csv` | Reddit prospects (r/ClaudeCode) - verified Linux users |
| `prospects-contextify-hn-2026-01-14.csv` | Hacker News prospects - includes contact info |
| `prospects-linux-cli-beta-2026-01-14-summary.md` | Reddit research summary with outreach templates |
| `prospects-contextify-hn-2026-01-14-summary.md` | HN research summary with tiered prospect segments |
| `prospect-comparison-analysis.md` | Methodology comparison (skill-based vs direct prompt) |

---

## Prospect List Comparison

### Reddit List (20 prospects)
- **Source:** r/ClaudeCode posts and comments
- **Methodology:** `/prospect` skill with behavioral criteria
- **Strength:** Verified Linux users (evidence of Linux/Ubuntu/WSL usage in posts)
- **Contact method:** Reddit DM only
- **Best for:** Users with proven Linux experience

### Hacker News List (21 prospects)
- **Source:** HN comments on Claude Code threads via Algolia API search
- **Methodology:** Direct prompt approach with specific inclusion/exclusion criteria
- **Strength:** Many have contact info (6 emails, 5 websites)
- **Weakness:** OS not verified (general Claude Code users, not Linux-specific)
- **Best for:** Broader outreach, includes influencers (simonw, swyx, tptacek)

### Key Insight

The Reddit list has **verified Linux users** but no contact info (must DM).
The HN list has **contact info** but unverified OS (may not use Linux).

**Recommended approach:** Start with Reddit list for Linux CLI specifically, use HN list for general Contextify outreach or when seeking public feedback/coverage.

---

## How to Get More Prospects

### Reddit (r/ClaudeCode)

Use the `/prospect` skill or direct crawl prompt:

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

Output CSV with: username, profile_url, evidence_url, outreach_hook
```

**Search queries that worked:**
- `linux` (in r/ClaudeCode)
- `ubuntu`
- `wsl`
- `terminal workflow`

### Hacker News

Use Algolia API search:

```
Search URL: https://hn.algolia.com/api/v1/search?query=claude+code+memory&tags=comment
```

Then check HN profiles for contact info (email field, "about" with website).

**Keywords that found engaged users:**
- `claude code memory`
- `claude code session`
- `claude code context`
- `claude code transcript`

---

## Outreach Tips

1. **Personalize the hook** - Reference their specific post/project
2. **Lead with their problem** - "I saw you built X to solve Y..."
3. **Offer value, not asks** - "Would you be interested in trying..." not "Can you test..."
4. **Keep it short** - 3-4 sentences max for initial outreach
5. **Include the link** - Always include contextify.sh

See the summary files for ready-to-use outreach templates tailored to each prospect segment.

---

## Methodology Notes

The `prospect-comparison-analysis.md` file compares two approaches:
1. **Skill-based** (`/prospect`) - More prospects (40), includes scoring, multi-phase
2. **Direct prompt** - Fewer prospects (25), better outreach hooks, single-pass

**Verdict:** Direct prompt with behavioral criteria produced more actionable results. The skill's scoring system added overhead without proportional value. See the analysis for recommendations on when to use each approach.
