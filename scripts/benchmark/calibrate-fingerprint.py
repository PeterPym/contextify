#!/usr/bin/env python3
"""Calibration harness for check_fingerprint() in evaluate.sh.

Tests the fingerprint matching function against labeled pairs:
  - TRUE POSITIVES: AI responses that genuinely found the content
  - TRUE NEGATIVES: AI responses that did NOT find the content
  - EDGE CASES: near-boundary responses (paraphrased, partial, wrong topic)

Outputs: precision/recall at multiple thresholds, recommended threshold.
"""

import re
import sys
import json

# ---------------------------------------------------------------------------
# Exact copy of check_fingerprint() from evaluate.sh Python block
# ---------------------------------------------------------------------------
stopwords = {"the", "that", "this", "with", "from", "have",
             "been", "were", "will", "does", "about", "into",
             "what", "when", "where", "which", "their", "there",
             "some", "more", "also", "than", "other", "each"}

def strip_markdown(text):
    text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
    text = re.sub(r'\*(.+?)\*', r'\1', text)
    text = re.sub(r'__(.+?)__', r'\1', text)
    text = re.sub(r'_(.+?)_', r'\1', text)
    text = re.sub(r'`(.+?)`', r'\1', text)
    return text

NEGATION_SIGNALS = [
    "not found", "no results", "no conversation", "no discussion",
    "no record", "couldn't find", "could not find", "zero results",
    "no matches", "no relevant", "no evidence", "no mention",
    "nothing about", "didn't find", "did not find", "no references",
    "unable to find", "no information",
    "nothing specifically",
]

FINGERPRINT_THRESHOLD = 0.70
NEGATION_PENALTY = 0.25

def _get_words(fp_clean):
    """Extract qualifying words from fingerprint (matches evaluate.sh logic)."""
    return [w for w in re.findall(r'[a-z0-9]+', fp_clean)
            if (len(w) >= 4 and w not in stopwords) or (w.isdigit() and len(w) >= 3)]

def _stem_match_word(fp_word, clean_response, response_words):
    # Numeric tokens require exact word match (no stemming, no substring)
    if fp_word.isdigit():
        return fp_word in response_words
    if fp_word in clean_response:
        return True
    stem = fp_word[:min(len(fp_word), 5)] if len(fp_word) >= 5 else fp_word[:4]
    return any(rw.startswith(stem) for rw in response_words if len(rw) >= 4)

def check_fingerprint(fp_clean, clean_response, threshold=None):
    """Matches evaluate.sh check_fingerprint() with negation awareness."""
    if threshold is None:
        threshold = FINGERPRINT_THRESHOLD
    if not fp_clean:
        return False
    if fp_clean in clean_response:
        return True
    words = _get_words(fp_clean)
    if not words:
        return False
    response_words = set(re.findall(r'[a-z0-9]+', clean_response))
    matches = sum(1 for w in words if _stem_match_word(w, clean_response, response_words))
    ratio = matches / len(words)
    has_negation = any(sig in clean_response for sig in NEGATION_SIGNALS)
    effective_threshold = min(threshold + NEGATION_PENALTY, 1.0) if has_negation else threshold
    return ratio >= effective_threshold

def word_match_ratio(fp_clean, clean_response):
    """Return the raw match ratio (before negation adjustment)."""
    if not fp_clean:
        return 0.0
    if fp_clean in clean_response:
        return 1.0
    words = _get_words(fp_clean)
    if not words:
        return 0.0
    response_words = set(re.findall(r'[a-z0-9]+', clean_response))
    matches = sum(1 for w in words if _stem_match_word(w, clean_response, response_words))
    return matches / len(words)

# ---------------------------------------------------------------------------
# Labeled calibration pairs
# Each entry: (fingerprint, response, expected_label, description)
# expected_label: True = should match, False = should not match
# ---------------------------------------------------------------------------
CALIBRATION_PAIRS = [
    # ===== TRUE POSITIVES: AI found and quoted/paraphrased the content =====

    # TP-01: Exact quote embedded in AI response (gq-01 style)
    ("Fulton House Business Operations, Booking Systems, Google Workspace",
     "I found several conversations about the Fulton House. The property discussions cover "
     "Fulton House Business Operations, Booking Systems, Google Workspace setup and more. "
     "Rex Winder manages the property.",
     True, "TP-01: exact quote in response"),

    # TP-02: Paraphrased but all key terms present (gq-02 style)
    ("A Delaware C-corp (Perch Innovations Inc) has its own",
     "Yes, I found the Delaware franchise tax discussion. A Delaware C-corp, specifically "
     "Perch Innovations Inc, has its own set of recurring deadlines including the March 1 "
     "franchise tax filing.",
     True, "TP-02: paraphrased with all key terms"),

    # TP-03: Scientific name with markdown stripped (gq-03 style)
    ("Paperbark Maple (*Acer griseum*)",
     "The tree replacement discussion settled on the Paperbark Maple (Acer griseum) as the "
     "recommended species for the exception request.",
     True, "TP-03: scientific name, markdown stripped"),

    # TP-04: Multi-phrase fingerprint, some words reordered (gq-04 style)
    ("focus changes, focus should be intelligent, auto-advance focus wrong",
     "There was a design discussion about making focus management intelligent rather than "
     "mechanical. The conclusion was that auto-advance of focus would be wrong because "
     "focus changes should be context-aware.",
     True, "TP-04: reordered but all concepts present"),

    # TP-05: Technical terms in different sentence structure (gq-05 style)
    ("Cloud is separate Python FastAPI service with its own PostgreSQL",
     "Contextify Cloud is a separate backend service built with Python and FastAPI. It has "
     "its own PostgreSQL database with schema-per-tenant isolation.",
     True, "TP-05: technical terms restructured"),

    # TP-06: Version + issue ID (gq-06 style)
    ("Contextify 1.5.0 = Cloud Launch (`ct",
     "Version 1.5.0 is the Cloud Launch release, tracked as ct-389. Contextify 1.5.0 is "
     "described as a business release, not just a feature drop.",
     True, "TP-06: version and issue reference"),

    # TP-07: Environment variable (gq-07 style)
    ("SENTRY_ENVIRONMENT=production",
     "Sentry monitoring was set up for the cloud server. The configuration uses environment "
     "variables: SENTRY_DSN for the DSN, SENTRY_ENVIRONMENT=production for the environment.",
     True, "TP-07: env var exact match"),

    # TP-08: Infrastructure spec (gq-08 style)
    ("DigitalOcean droplet (s-2vcpu-4gb, NYC3 region)",
     "The cloud server runs on a DigitalOcean droplet, specifically the s-2vcpu-4gb plan "
     "in the NYC3 region, deployed via Docker Compose.",
     True, "TP-08: infra spec paraphrased"),

    # TP-09: Technical concept with tier reference (gq-09 style)
    ("Tier 1 + Tier 2: LLM fallback",
     "The patcher uses a tiered discovery approach. Tier 1 does mechanical pattern matching, "
     "and Tier 2 adds LLM fallback for cases where Tier 1 fails.",
     True, "TP-09: tiered concept paraphrased"),

    # TP-10: Branch name as fingerprint (gq-10 style)
    ("ct-287-cloud-worktree-grouping",
     "The ct-287 work on cloud worktree grouping was completed and merged. The branch "
     "ct-287-cloud-worktree-grouping consolidated git worktrees into logical projects.",
     True, "TP-10: branch name in response"),

    # TP-11: Informal project name (gq-11 style)
    ("dungeon crawler carl bootleg hats project",
     "I found references to a Dungeon Crawler Carl themed project. It appears to be about "
     "bootleg hats inspired by the Dungeon Crawler Carl series, marked as a personal project.",
     True, "TP-11: informal name paraphrased"),

    # TP-12: Short fingerprint, job title (gq-12 style)
    ("Quality Engineering Lead",
     "Yes, there was a conversation about renaming QA to Quality Engineering across the "
     "organization. Your title would become Quality Engineering Lead.",
     True, "TP-12: job title in response"),

    # TP-13: Names with roles (gq-13 style)
    ("Justin George (personal license), Noah Zoschke (team/cloud version)",
     "Two key prospects were discussed: Justin George who wanted a personal license for his "
     "company, and Noah Zoschke who was interested in a team/cloud version with central sync.",
     True, "TP-13: names with roles paraphrased"),

    # TP-14: Generic phrase that could false-match (gq-14 style)
    ("The work was planned and scoped",
     "The navigation UX upgrade was planned and scoped but never implemented. The work was "
     "started on wb3 via Codex but got sidetracked.",
     True, "TP-14: generic phrase in context"),

    # ===== HARDER TRUE POSITIVES: AI paraphrases heavily =====

    # HTP-01: AI uses synonyms for most terms
    ("Fulton House Business Operations, Booking Systems, Google Workspace",
     "The Fulton House is a B&B property. The operational details include their reservation "
     "management (Think Reservations platform) and Google Workspace for email and docs.",
     True, "HTP-01: synonyms + Fulton/House/Google/Workspace present"),

    # HTP-02: AI quotes only the key identifier
    ("A Delaware C-corp (Perch Innovations Inc) has its own",
     "Perch Innovations Inc was registered in Delaware as a C-corp. It has a separate set of "
     "annual obligations distinct from the personal filing requirements.",
     True, "HTP-02: key terms present but restructured"),

    # HTP-03: AI uses just the technical terms
    ("Cloud is separate Python FastAPI service with its own PostgreSQL",
     "The cloud component is a Python backend using FastAPI. It connects to its own "
     "PostgreSQL instance, isolated from the main app's SQLite.",
     True, "HTP-03: technical terms present, different sentence structure"),

    # HTP-04: Only partial fingerprint terms (6/8-ish)
    ("focus changes, focus should be intelligent, auto-advance focus wrong",
     "The discussion centered on making focus behavior smarter. The key takeaway was "
     "that auto-advancing focus was considered wrong and changes should be intelligent.",
     True, "HTP-04: 'focus','intelligent','auto','advance','wrong','changes' all present"),

    # HTP-05: Very loose paraphrase with proper nouns
    ("Justin George (personal license), Noah Zoschke (team/cloud version)",
     "Justin emailed about getting a personal license. Noah Zoschke wanted something more "
     "like a team cloud offering with centralized management.",
     True, "HTP-05: names present, roles loosely described"),

    # HTP-06: AI gives summary paragraph, fingerprint words scattered
    ("DigitalOcean droplet (s-2vcpu-4gb, NYC3 region)",
     "The server was provisioned as a small DigitalOcean droplet. It uses the s-2vcpu-4gb "
     "plan. Data is hosted in the NYC3 region for East Coast latency.",
     True, "HTP-06: all spec terms present across sentences"),

    # ===== TRUE NEGATIVES: AI did NOT find the content =====

    # TN-01: Completely wrong topic
    ("Fulton House Business Operations, Booking Systems, Google Workspace",
     "I searched for information about the Fulton House but couldn't find any relevant "
     "conversations. The search returned results about database migrations and CI builds.",
     False, "TN-01: wrong topic entirely"),

    # TN-02: Similar words but wrong meaning
    ("A Delaware C-corp (Perch Innovations Inc) has its own",
     "I found mentions of Delaware in the context of state regulations, but nothing about "
     "Perch or any corporation. The discussions were about Delaware state compliance.",
     False, "TN-02: Delaware present but wrong context"),

    # TN-03: Partial name match but different entity
    ("Paperbark Maple (*Acer griseum*)",
     "I found a conversation about maple trees in general, discussing sugar maples and "
     "red maples for a landscaping project. No mention of paperbark varieties.",
     False, "TN-03: maple present but wrong species"),

    # TN-04: Topic adjacent but content not found
    ("focus changes, focus should be intelligent, auto-advance focus wrong",
     "I found discussions about UI focus management and keyboard navigation, but they were "
     "about implementing tab order and accessibility labels, not about intelligent focus.",
     False, "TN-04: focus topic but different discussion"),

    # TN-05: Stack mentioned but no specific content
    ("Cloud is separate Python FastAPI service with its own PostgreSQL",
     "There are several conversations about cloud services and backend development, but "
     "I couldn't find specific details about the technology stack or database choices.",
     False, "TN-05: cloud mentioned generically"),

    # TN-06: "Not found" response
    ("Contextify 1.5.0 = Cloud Launch (`ct",
     "I couldn't find any conversations about version 1.5.0 or a cloud launch plan. "
     "The search returned no relevant results for this query.",
     False, "TN-06: explicit not-found"),

    # TN-07: Different monitoring tool
    ("SENTRY_ENVIRONMENT=production",
     "I found discussions about error monitoring, but they referenced Datadog and PagerDuty "
     "rather than Sentry. The production environment uses Datadog for alerting.",
     False, "TN-07: different monitoring tool"),

    # TN-08: Different cloud provider
    ("DigitalOcean droplet (s-2vcpu-4gb, NYC3 region)",
     "The cloud infrastructure discussion mentioned AWS EC2 instances in us-east-1 region. "
     "No references to DigitalOcean or NYC3 were found.",
     False, "TN-08: wrong cloud provider"),

    # TN-09: No tier reference
    ("Tier 1 + Tier 2: LLM fallback",
     "I found the patcher documentation which describes a pattern discovery engine, but "
     "the implementation details about tiering were not found in any conversations.",
     False, "TN-09: patcher mentioned but no tiers"),

    # TN-10: Different issue number
    ("ct-287-cloud-worktree-grouping",
     "I found cloud-related schema work tracked under ct-300 and ct-305, but nothing "
     "specifically about ct-287 or worktree grouping in the cloud context.",
     False, "TN-10: different issue numbers"),

    # TN-11: Numeric substring collision (E1 regression test)
    # "287" must not match "1287" as a substring
    ("ct-287-cloud-worktree-grouping",
     "I could not find any results for that issue. The closest match was ct-1287 which "
     "dealt with cloud worktree grouping but is a different issue entirely.",
     False, "TN-11: numeric substring collision (287 vs 1287)"),

    # ===== EDGE CASES: near-boundary =====

    # EC-01: Heavy paraphrase, only 2/5 key words match
    ("Fulton House Business Operations, Booking Systems, Google Workspace",
     "The property management discussion covered the Fulton House bed and breakfast, "
     "including their reservation platform and email setup.",
     None, "EC-01: heavy paraphrase (fulton, house match; booking/systems/google/workspace miss)"),

    # EC-02: AI summarizes without using fingerprint words
    ("A Delaware C-corp (Perch Innovations Inc) has its own",
     "I found the franchise tax discussion. The company incorporated in the first state "
     "and has annual filing obligations including a March deadline.",
     None, "EC-02: completely reworded summary"),

    # EC-03: Stemmed words match (innovations -> innovat*, operations -> operat*)
    ("Fulton House Business Operations, Booking Systems, Google Workspace",
     "I found the Fulton House operational details. The booking system integrates with "
     "Google's workspace tools for managing reservations.",
     None, "EC-03: stemmed forms present"),

    # EC-04: Most words match but critical identifier missing
    ("Justin George (personal license), Noah Zoschke (team/cloud version)",
     "Two early users discussed licensing. One wanted a personal license for company use, "
     "and another asked about a team version with cloud capabilities.",
     None, "EC-04: roles match but names missing"),

    # EC-05: All technical terms match from fingerprint but in wrong context
    ("Cloud is separate Python FastAPI service with its own PostgreSQL",
     "We discussed building a Python FastAPI service with PostgreSQL for the analytics "
     "dashboard. This would be separate from the main cloud backend.",
     None, "EC-05: all tech terms present, different project"),
]


def has_negation(clean_response):
    return any(sig in clean_response for sig in NEGATION_SIGNALS)


def run_calibration():
    thresholds = [0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90]

    print("=" * 80)
    print("FINGERPRINT CALIBRATION REPORT")
    print("=" * 80)

    # First: show per-pair match ratios
    print("\n## Per-pair match ratios\n")
    print(f"{'Label':<8} {'Ratio':>6}  {'Description'}")
    print("-" * 80)

    labeled_ratios = []
    for fp_raw, response_raw, expected, desc in CALIBRATION_PAIRS:
        fp_clean = strip_markdown(fp_raw).lower()
        clean_response = strip_markdown(response_raw).lower()
        ratio = word_match_ratio(fp_clean, clean_response)
        label = "TP" if expected is True else ("TN" if expected is False else "EC")
        labeled_ratios.append((label, ratio, expected, desc))
        print(f"{label:<8} {ratio:>5.2f}   {desc}")

    # Threshold sweep
    print(f"\n\n## Threshold sensitivity analysis\n")
    print(f"{'Thresh':>7} {'TP_corr':>8} {'TP_tot':>7} {'TN_corr':>8} {'TN_tot':>7} {'Prec':>6} {'Recall':>7} {'F1':>6}")
    print("-" * 65)

    tp_pairs = [(r, e) for (l, r, e, d) in labeled_ratios if e is True]
    tn_pairs = [(r, e) for (l, r, e, d) in labeled_ratios if e is False]
    ec_pairs = [(r, e, d) for (l, r, e, d) in labeled_ratios if e is None]

    best_f1 = 0
    best_threshold = 0.70

    for t in thresholds:
        # True positives: should match (ratio >= threshold)
        tp_correct = sum(1 for r, _ in tp_pairs if r >= t)
        tp_total = len(tp_pairs)

        # True negatives: should NOT match (ratio < threshold)
        tn_correct = sum(1 for r, _ in tn_pairs if r < t)
        tn_total = len(tn_pairs)

        # Precision: of things we call positive, how many are actually positive
        predicted_positive = tp_correct + (tn_total - tn_correct)
        precision = tp_correct / predicted_positive if predicted_positive > 0 else 0

        # Recall: of actual positives, how many did we find
        recall = tp_correct / tp_total if tp_total > 0 else 0

        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0

        if f1 > best_f1:
            best_f1 = f1
            best_threshold = t

        print(f"{t:>7.2f} {tp_correct:>8}/{tp_total:<7} {tn_correct:>7}/{tn_total:<7} {precision:>5.2f}  {recall:>6.2f}  {f1:>5.2f}")

    print(f"\nBest F1: {best_f1:.3f} at threshold {best_threshold:.2f}")

    # Edge case analysis
    print(f"\n\n## Edge case analysis\n")
    for ratio, expected, desc in ec_pairs:
        matches_at_70 = "PASS" if ratio >= 0.70 else "FAIL"
        matches_at_best = "PASS" if ratio >= best_threshold else "FAIL"
        print(f"  {ratio:.2f}  @0.70={matches_at_70}  @{best_threshold:.2f}={matches_at_best}  {desc}")

    # Separation analysis
    print(f"\n\n## Distribution analysis\n")
    tp_ratios = sorted([r for r, _ in tp_pairs])
    tn_ratios = sorted([r for r, _ in tn_pairs])
    print(f"  TP ratios: min={min(tp_ratios):.2f}  max={max(tp_ratios):.2f}  "
          f"median={tp_ratios[len(tp_ratios)//2]:.2f}")
    print(f"  TN ratios: min={min(tn_ratios):.2f}  max={max(tn_ratios):.2f}  "
          f"median={tn_ratios[len(tn_ratios)//2]:.2f}")

    gap = min(tp_ratios) - max(tn_ratios)
    print(f"  Separation gap: {gap:.2f} (positive = clean separation)")

    if gap > 0:
        optimal_boundary = (min(tp_ratios) + max(tn_ratios)) / 2
        print(f"  Optimal boundary (midpoint of gap): {optimal_boundary:.2f}")

    # Negation + numeric token analysis (now the default in evaluate.sh)
    print(f"\n\n## Calibrated evaluator analysis (negation-aware + numeric tokens)\n")
    print(f"Threshold=0.70, +0.25 penalty on negation, numeric tokens >= 3 chars qualify.\n")
    print(f"{'Label':<8} {'Ratio':>6} {'Neg?':>5} {'Result':>7}  {'Description'}")
    print("-" * 90)

    cal_tp_correct = 0
    cal_tn_correct = 0
    for fp_raw, response_raw, expected, desc in CALIBRATION_PAIRS:
        fp_clean = strip_markdown(fp_raw).lower()
        clean_response = strip_markdown(response_raw).lower()
        ratio = word_match_ratio(fp_clean, clean_response)
        result = check_fingerprint(fp_clean, clean_response)
        label = "TP" if expected is True else ("TN" if expected is False else "EC")
        neg_flag = "NEG" if has_negation(clean_response) else ""
        result_str = "PASS" if result else "FAIL"

        if expected is True:
            if result:
                cal_tp_correct += 1
        elif expected is False:
            if not result:
                cal_tn_correct += 1

        print(f"{label:<8} {ratio:>5.2f} {neg_flag:>5} {result_str:>7}  {desc}")

    tp_total = sum(1 for _, _, e, _ in CALIBRATION_PAIRS if e is True)
    tn_total = sum(1 for _, _, e, _ in CALIBRATION_PAIRS if e is False)
    print(f"\n  Calibrated: TP={cal_tp_correct}/{tp_total}  TN={cal_tn_correct}/{tn_total}")

    cal_pred_pos = cal_tp_correct + (tn_total - cal_tn_correct)
    cal_precision = cal_tp_correct / cal_pred_pos if cal_pred_pos > 0 else 0
    cal_recall = cal_tp_correct / tp_total if tp_total > 0 else 0
    cal_f1 = 2 * cal_precision * cal_recall / (cal_precision + cal_recall) if (cal_precision + cal_recall) > 0 else 0
    print(f"  Precision={cal_precision:.2f}  Recall={cal_recall:.2f}  F1={cal_f1:.3f}")

    # Final recommendation
    print(f"\n\n## Recommendation\n")
    if gap > 0.05:
        print(f"  Clean separation exists. Any threshold in [{max(tn_ratios):.2f}, {min(tp_ratios):.2f}] works.")
        print(f"  Current threshold (0.70) is {'WITHIN' if max(tn_ratios) < 0.70 < min(tp_ratios) else 'OUTSIDE'} the safe range.")
    else:
        print(f"  Overlap detected between TP and TN distributions.")
        print(f"  Best F1 threshold: {best_threshold:.2f}")

    print(f"\n  Plain threshold sweep best: @{best_threshold:.2f} F1={best_f1:.3f}")
    print(f"  Calibrated evaluator: F1={cal_f1:.3f}")
    print(f"\n  Status: FROZEN. Calibrated evaluator deployed to evaluate.sh.")

    return best_threshold, best_f1


if __name__ == "__main__":
    run_calibration()
