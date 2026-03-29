# Total Recall Benchmark

Automated evaluation framework for the Total Recall skill and `contextify` CLI search quality. Uses a frozen database snapshot with 34 gold queries scored on Recall@k, MRR, and fingerprint matching.

## Quick Start

```bash
# Run CLI benchmark (baseline: 100.0, ~4 seconds)
bash scripts/benchmark/evaluate.sh --verbose

# Run with per-query traces for debugging
bash scripts/benchmark/evaluate.sh --verbose --trace
# Traces: /tmp/benchmark-traces/{gq-01..gq-34}.json

# Run skill benchmark (headless Claude Code, ~15 minutes)
bash scripts/benchmark/evaluate.sh --mode skill --verbose --trace

# Median-of-3 for stochastic variance reduction (skill mode)
bash scripts/benchmark/evaluate.sh --mode skill --runs 3

# A/B comparison with confidence intervals
bash scripts/benchmark/evaluate.sh --mode cli --compare snapshot-a.db snapshot-b.db

# Ratchet loop: edit SKILL.md, run benchmark, keep if improved
bash scripts/benchmark/ratchet.sh --iterations 5
```

## Modes

### CLI Mode (default)

Runs gold-query search terms directly against the `contextify` CLI. Deterministic: same snapshot always produces the same results. Use this for evaluating CLI code changes, tokenizer changes, and FTS5 configuration.

```bash
bash scripts/benchmark/evaluate.sh --mode cli --verbose
```

### Skill Mode

Runs each gold query's natural-language question through headless Claude Code with the Total Recall SKILL.md loaded. Non-deterministic due to LLM variance. Use this for evaluating SKILL.md changes.

```bash
bash scripts/benchmark/evaluate.sh --mode skill --verbose --trace
```

Budget caps (skill mode only):
- `--max-turns 10` (default): Maximum search turns per trial
- `--max-wall-clock 180` (default): Maximum seconds per trial
- `--max-tokens N`: Placeholder, logged but not enforced

## Scoring Metrics

### Primary Metrics (v2)

**Recall@k**: Fraction of ground-truth entries (`relevant_entry_ids`) that appear in the CLI search results. Measures completeness of retrieval. A query with 6 relevant entries where 4 are found scores 0.667.

**MRR (Mean Reciprocal Rank)**: 1/rank of the first relevant entry in the result list. Measures ranking quality. MRR=1.0 means the first result is relevant. MRR=0.2 means the first relevant result is at rank 5.

Both metrics are averaged across all 34 queries to produce aggregate scores.

### Sentinel Metric (v1, retained)

**Fingerprint matching**: Each query has a content fingerprint (substring). Results are checked for this substring using word-level matching with a 70% threshold, negation awareness, and numeric exact-match. This was the primary metric in v1 and is retained as a regression sentinel. If a fingerprint that previously matched stops matching, something broke.

### Final Score (Legacy)

The final score (0-100) is `found_rate * efficiency_factor * 100`. This saturated at 100.0 in v1. With v2, use Recall@k and MRR as the primary optimization targets.

## Gold Queries

34 queries covering 6 categories:

| Category | Count | Description |
|----------|-------|-------------|
| decision-archaeology | 9 | Finding past decisions and their reasoning |
| implementation-reference | 10 | Locating technical implementation details |
| debugging | 6 | Finding bug reports and resolution details |
| session-opener | 5 | "Remind me where we are with X" |
| cross-session-continuity | 4 | Finding work across multiple sessions |

### Morphology Diagnostic Slice

5 queries (gq-28, gq-29, gq-30, gq-32, gq-33) are tagged `"diagnostic": "morphology"`. These use search terms with inflected forms (e.g., "deploying", "configuring", "hallucinating") that require porter stemming to match the stored content. They produce zero results on unicode61 tokenization and serve as a regression gate for stemming support.

### Adding New Gold Queries

1. Find a real question that the database can answer
2. Run `contextify search "<terms>" --db-path <snapshot>` to verify results exist
3. Identify the relevant entry IDs from the search results
4. Add to `gold-queries.json`:

```json
{
  "id": "gq-35",
  "category": "debugging",
  "natural_question": "What was the user's actual question?",
  "search_terms": "distinctive search terms",
  "content_fingerprint": "substring that must appear in results",
  "efficiency_budget": 2,
  "difficulty": "medium",
  "verified": true,
  "relevant_entry_ids": ["uuid-1", "uuid-2"]
}
```

5. For morphology diagnostics, add `"diagnostic": "morphology"` and use inflected search terms
6. Run `bash scripts/benchmark/evaluate.sh --verbose` to confirm the query passes

## A/B Testing

Compare two snapshots (or the same snapshot with different CLI builds) using hierarchical bootstrap confidence intervals.

```bash
# Compare porter vs unicode61 tokenizers
bash scripts/benchmark/evaluate.sh --mode cli \
  --compare ~/Library/Application\ Support/Contextify/benchmark/contextify-benchmark-v1.db \
  /tmp/benchmark-snap-unicode61.db
```

Output includes:
- Per-snapshot Recall@k and MRR
- Delta with 95% confidence interval (1000 bootstrap samples)
- JSON summary on stdout

For skill-mode A/B tests, use `--runs N` for multiple trials per snapshot:

```bash
bash scripts/benchmark/evaluate.sh --mode skill \
  --compare snapshot-a.db snapshot-b.db --runs 5
```

The hierarchical bootstrap resamples at two levels:
1. **Queries** (level 1): resamples which queries are included
2. **Runs** (level 2, skill mode): resamples across multiple LLM runs per query

This accounts for both query selection variance and LLM non-determinism.

## Ratchet Loop

The ratchet loop iteratively edits an artifact (usually SKILL.md), runs the benchmark, and keeps changes that improve the score.

```bash
# CLI mode ratchet (uses Recall@k/MRR, auto-accept/reject)
bash scripts/benchmark/ratchet.sh --iterations 5 --mode cli

# Skill mode ratchet (ADVISORY ONLY, does not auto-accept/reject)
bash scripts/benchmark/ratchet.sh --iterations 5 --mode skill
```

**Ratchet policy (ct-779)**:
- **CLI ratchet**: Automated. Uses Recall@k/MRR as the non-saturated metric. The legacy found-rate score saturated at 100.0, making it useless for ratcheting.
- **Skill ratchet**: Advisory only. Prints results but does not auto-accept/reject. Experience shows that automated ratchet iterations produce zero lasting SKILL.md improvements (see BENCHMARK-HISTORY.md Phases 3 and 7). Targeted manual edits based on `--trace` failure analysis are far more effective.

## Snapshot Management

The benchmark uses a frozen database snapshot for reproducibility.

**Default location**: `~/Library/Application Support/Contextify/benchmark/contextify-benchmark-v1.db`

**Manifest**: `scripts/benchmark/snapshot-manifest.json` records the expected hash, entry count, and creation date. The evaluator verifies the hash on every run (unless `--snapshot` is used explicitly).

**Creating a new snapshot**:

```bash
bash scripts/benchmark/prepare-snapshot.sh
```

This copies the current production database and updates the manifest. When rebuilding the snapshot (e.g., after a tokenizer change), all gold queries must be re-verified.

**Creating a comparison snapshot** (e.g., with a different tokenizer):

1. Build the app with the alternative tokenizer
2. Let it rebuild the FTS index
3. Copy the database: `cp ~/Library/Application\ Support/Contextify/contextify.db /tmp/benchmark-snap-alternative.db`
4. Run A/B comparison: `bash scripts/benchmark/evaluate.sh --mode cli --compare default.db /tmp/benchmark-snap-alternative.db`

## File Reference

| File | Purpose |
|------|---------|
| `evaluate.sh` | Evaluator (scoring logic, `--trace`, `--runs N`, `--compare`) |
| `gold-queries.json` | 34 gold queries with fingerprints and entry IDs |
| `ratchet.sh` | AutoResearch ratchet loop wrapper |
| `run-skill-query.sh` | Skill runner (headless Claude Code) |
| `prepare-snapshot.sh` | Snapshot creation |
| `snapshot-manifest.json` | Snapshot metadata + hash |
| `calibrate-fingerprint.py` | Calibration harness (36 labeled pairs, F1=0.900) |
| `results.tsv` | Score history (annotated) |
| `BENCHMARK-HISTORY.md` | Full development history and lessons learned |

## Protocol Version History

**v2 (ct-779, March 2026)**: Current protocol. 34 gold queries, Recall@k/MRR, hierarchical bootstrap, structured evidence, budget caps.

**v1 (ct-727/ct-728/ct-729, March 2026)**: Original protocol. 14 gold queries, binary fingerprint hit scoring, found_rate * efficiency_factor.

### Breaking Changes (v1 to v2)

- **gq-13 replaced**: v1's gq-13 tested pricing prospects (Justin George / Noah Zoschke); v2's gq-13 tests approved pricing tiers (ct-525). These are different queries sharing the same ID. **Do not compare v1 and v2 results for gq-13.** The replacement was necessary because the original query had inadequate corpus coverage and failed across all configurations.
- **gq-14 calibration fix**: The query itself (search terms, fingerprint) is unchanged. Only the labeled pair in `calibrate-fingerprint.py` was corrected to match the actual fingerprint. v1/v2 results for gq-14 are comparable.
- **gq-15 through gq-34 are new**: No v1 baseline exists for these queries.
- **Scoring metrics changed**: v1 used `found_rate * efficiency_factor * 100`. v2 uses Recall@k and MRR as primary metrics. The v1 score is still computed for backward compatibility but is saturated at 100.0 and uninformative.

Ratchet history (`results.tsv`) from v1 runs should not be directly compared with v2 runs. The benchmark versions measure different things.

## Current Baselines (2026-03-29)

| Mode | Score | Recall@k | MRR | Queries |
|------|-------|----------|-----|---------|
| CLI (porter) | 100.0 | 0.914 | 0.865 | 34/34 found |
| CLI (unicode61) | 76.5 | 0.711 | 0.722 | 26/34 found |
| Skill (last verified) | ~46.5 | -- | -- | 13/14 (pre-v2) |
