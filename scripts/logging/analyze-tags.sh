#!/bin/bash

set -euo pipefail

python3 - "$@" <<'PY'
import argparse
import glob
import os
import re
import sys
from collections import Counter
from typing import List, Optional

START_SUFFIXES = (
    "START",
    "BEGIN",
    "REQUEST",
    "INIT",
    "OPEN",
)

END_SUFFIXES = (
    "DONE",
    "STOP",
    "END",
    "COMPLETE",
    "SUCCESS",
    "FINISH",
    "FINISHED",
    "CLOSE",
    "CLOSED",
    "RESPONSE",
)

LONG_LIVED_HINTS = (
    "WATCH",
    "MONITOR",
    "INIT",
    "LISTEN",
    "KEEPALIVE",
    "HEARTBEAT",
)

TAG_PATTERN = re.compile(r"\[([A-Z0-9-]+)\]")
TIMESTAMP_PATTERN = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{3})?)")


def human_size(num_bytes: int) -> str:
    units = ["B", "KB", "MB", "GB"]
    size = float(num_bytes)
    for unit in units:
        if size < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{int(size)} {unit}"
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def expand_paths(patterns: List[str]):
    resolved = []
    for pattern in patterns:
        matches = glob.glob(pattern)
        if matches:
            resolved.extend(sorted(matches))
        else:
            resolved.append(pattern)
    return resolved


def sanitize_component(value: Optional[str]) -> Optional[str]:
    if not value:
        return None
    cleaned = value.strip().strip("[]")
    return cleaned.upper()


def extract_timestamp(line: str) -> str:
    match = TIMESTAMP_PATTERN.match(line)
    if match:
        return match.group(1)
    return "n/a"


def track_pair(tag: str, start_counts: Counter, end_counts: Counter) -> str:
    upper_tag = tag.upper()
    for suffix in START_SUFFIXES:
        needle = f"-{suffix}"
        if upper_tag.endswith(needle):
            base = upper_tag[: -len(needle)]
            start_counts[base] += 1
            return "start"
    for suffix in END_SUFFIXES:
        needle = f"-{suffix}"
        if upper_tag.endswith(needle):
            base = upper_tag[: -len(needle)]
            end_counts[base] += 1
            return "end"
    return "none"


def analyze_logs(paths, component_filter):
    counts: Counter[str] = Counter()
    component_counts: Counter[str] = Counter()
    start_counts: Counter[str] = Counter()
    end_counts: Counter[str] = Counter()
    first_occurrence = {}
    last_occurrence = {}
    action_counts: Counter[str] = Counter()
    per_file = []
    total_tagged_entries = 0

    for path in paths:
        if not os.path.exists(path):
            raise FileNotFoundError(f"File not found: {path}")
        matches_in_file = 0
        total_lines = 0
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for line_no, raw_line in enumerate(handle, start=1):
                total_lines = line_no
                has_match = False
                for match in TAG_PATTERN.finditer(raw_line):
                    tag = match.group(1)
                    upper_tag = tag.upper()
                    if component_filter and not (
                        upper_tag == component_filter
                        or upper_tag.startswith(f"{component_filter}-")
                    ):
                        continue
                    has_match = True
                    counts[upper_tag] += 1
                    matches_in_file += 1
                    timestamp = extract_timestamp(raw_line)
                    context = {
                        "file": path,
                        "line": line_no,
                        "timestamp": timestamp,
                    }
                    if upper_tag not in first_occurrence:
                        first_occurrence[upper_tag] = context
                    last_occurrence[upper_tag] = context
                    component = upper_tag.split("-", 1)[0]
                    component_counts[component] += 1
                    match_type = track_pair(upper_tag, start_counts, end_counts)
                    if match_type == "none":
                        action_counts[upper_tag] += 1
                if has_match:
                    total_tagged_entries += 1
        per_file.append(
            {
                "path": path,
                "lines": total_lines,
                "size": os.path.getsize(path),
                "matches": matches_in_file,
            }
        )

    return {
        "counts": counts,
        "first": first_occurrence,
        "last": last_occurrence,
        "per_file": per_file,
        "component_counts": component_counts,
        "start_counts": start_counts,
        "end_counts": end_counts,
        "action_counts": action_counts,
        "total_tagged_entries": sum(counts.values()),
        "lines_with_tags": total_tagged_entries,
    }


def format_context(context):
    if not context:
        return "-"
    filename = os.path.basename(context["file"])
    timestamp = context["timestamp"]
    return f"{filename}:{context['line']} @ {timestamp}"


def print_header(paths_info, component_filter):
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  TAG DISCOVERY")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    for info in paths_info:
        summary = f"{info['path']} ({human_size(info['size'])}, {info['lines']} lines, {info['matches']} tags)"
        print(f"• {summary}")
    if component_filter:
        print(f"Component filter: {component_filter}")
    print("")


def print_summary(analysis):
    counts = analysis["counts"]
    print(f"Unique tags: {len(counts)}")
    print(f"Total tagged entries: {analysis['total_tagged_entries']}")
    print("")


def print_tag_table(analysis, top_n):
    counts = analysis["counts"]
    if not counts:
        print("No tags found with the current filters.")
        return
    sorted_tags = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    if top_n > 0:
        sorted_tags = sorted_tags[:top_n]

    print("Tag                                 Count  First Seen                          Last Seen")
    print("---------------------------------------------------------------------------------------")
    for tag, count in sorted_tags:
        first_label = format_context(analysis["first"].get(tag))
        last_label = format_context(analysis["last"].get(tag))
        print(f"[{tag:<30}] {count:6d}  {first_label:<35}  {last_label}")
    print("")


def print_component_summary(component_counts):
    if not component_counts:
        return
    print("Top components by tag volume:")
    for component, count in sorted(
        component_counts.items(), key=lambda item: (-item[1], item[0])
    )[:10]:
        print(f"  - {component:<15} {count:6d} entries")
    print("")


def print_mismatches(start_counts, end_counts, action_counts, full_counts):
    mismatch_rows = []
    for base in sorted(set(start_counts.keys()) | set(end_counts.keys())):
        start = start_counts.get(base, 0)
        end = end_counts.get(base, 0)
        if start == 0 and end > 0:
            fallback = action_counts.get(base, 0)
            if fallback:
                start = fallback
            else:
                done_variant = f"{base}-DONE"
                base_occurrence = full_counts.get(base, 0)
                if base_occurrence and full_counts.get(done_variant, 0):
                    start = base_occurrence
        if start != end:
            mismatch_rows.append((base, start, end))
    if not mismatch_rows:
        print("All START/END pairs balanced for tracked components.")
        return
    print("Potential mismatched operations:")
    for base, start, end in sorted(
        mismatch_rows, key=lambda item: abs(item[1] - item[2]), reverse=True
    ):
        delta = start - end
        expected = False
        if delta > 0:
            for hint in LONG_LIVED_HINTS:
                if hint in base:
                    expected = True
                    break
        if expected:
            state = "long-lived resource (expected)"
            marker = "  - "
        elif delta > 0:
            state = "missing completions"
            marker = "  ⚠️ - "
        else:
            state = "extra completions"
            marker = "  ⚠️ - "
        print(f"{marker}{base:<25} start={start:<5} end={end:<5} (Δ {delta:+}) {state}")


def print_comparison(primary_counts, compare_counts):
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  COUNT COMPARISON (primary vs --compare)")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    deltas = []
    for tag in set(primary_counts.keys()) | set(compare_counts.keys()):
        diff = compare_counts.get(tag, 0) - primary_counts.get(tag, 0)
        if diff != 0:
            deltas.append((tag, diff, primary_counts.get(tag, 0), compare_counts.get(tag, 0)))

    if not deltas:
        print("No differences detected between the provided logs.")
        return

    print("Tag                                 Primary  Compare  Δ")
    print("--------------------------------------------------------")
    for tag, diff, primary_value, compare_value in sorted(
        deltas, key=lambda item: (-abs(item[1]), item[0])
    ):
        indicator = "↑" if diff > 0 else "↓"
        print(
            f"[{tag:<30}] {primary_value:7d} {compare_value:8d}  {diff:+4d} {indicator}"
        )


def main():
    parser = argparse.ArgumentParser(
        description="Discover and summarize log tags inside monitor-transcript log files."
    )
    parser.add_argument("logfiles", nargs="+", help="Log file(s) or glob patterns to analyze")
    parser.add_argument(
        "--component",
        help="Only include tags that start with the provided component prefix",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=0,
        help="Limit output to the top N tags by occurrence",
    )
    parser.add_argument(
        "--compare",
        help="Optional secondary log (or glob) to diff counts against",
    )

    args = parser.parse_args()
    component_filter = sanitize_component(args.component)

    primary_paths = expand_paths(args.logfiles)
    if not primary_paths:
        parser.error("No log files matched the provided pattern.")

    analysis = analyze_logs(primary_paths, component_filter)
    print_header(analysis["per_file"], component_filter)
    print_summary(analysis)
    print_tag_table(analysis, args.top)
    print_component_summary(analysis["component_counts"])
    print("START/DONE validation:")
    print_mismatches(
        analysis["start_counts"],
        analysis["end_counts"],
        analysis["action_counts"],
        analysis["counts"],
    )

    if args.compare:
        compare_paths = expand_paths([args.compare])
        if not compare_paths:
            parser.error("--compare pattern did not match any files")
        compare_analysis = analyze_logs(compare_paths, component_filter)
        print("")
        print_comparison(analysis["counts"], compare_analysis["counts"])


if __name__ == "__main__":
    try:
        main()
    except FileNotFoundError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

PY
