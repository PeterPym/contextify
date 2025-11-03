#!/usr/bin/env python3
"""
generate_intent_improvements.py

Analyzes user messages with "infer from message" placeholders
and generates specific code improvements for classifyUserIntent().

Usage:
  python3 scripts/generate_intent_improvements.py <csv_file>

Input: CSV from analyze_intent_classification.sh
Output: Suggested pattern additions and code changes
"""

import csv
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


def extract_first_word(message: str) -> str:
    """Extract the first word from a message (lowercased)."""
    words = message.strip().split()
    return words[0].lower() if words else ""


def extract_imperative_verbs(message: str) -> list[str]:
    """Extract potential imperative verbs (first 1-2 words)."""
    words = message.strip().split()
    candidates = []
    if len(words) >= 1:
        candidates.append(words[0].lower())
    if len(words) >= 2:
        candidates.append(f"{words[0].lower()} {words[1].lower()}")
    return candidates


def has_question_marker(message: str) -> bool:
    """Check if message has question words or ends with '?'."""
    lower = message.lower()
    question_words = ['what', 'why', 'how', 'when', 'where', 'who', 'which', 'can', 'could', 'would', 'should']
    return any(lower.startswith(qw) for qw in question_words) or message.strip().endswith('?')


def classify_message_structure(message: str) -> dict:
    """Analyze the structure of a user message."""
    lower = message.lower().strip()

    return {
        'first_word': extract_first_word(message),
        'imperative_candidates': extract_imperative_verbs(message),
        'is_question': has_question_marker(message),
        'is_single_word': len(message.split()) == 1,
        'is_short': len(message.split()) <= 3,
        'starts_with_this': lower.startswith('this '),
        'starts_with_the': lower.startswith('the '),
        'contains_need': 'need to' in lower or 'need' in lower.split()[:3],
        'contains_should': 'should' in lower.split()[:3],
        'has_negation': any(neg in lower.split()[:5] for neg in ['not', 'dont', "don't", 'doesnt', "doesn't", 'cant', "can't"]),
        'length': len(message),
        'word_count': len(message.split()),
    }


def analyze_csv(csv_path: str) -> dict:
    """Analyze the CSV file and extract patterns."""
    messages = []

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            user_message = row.get('user_message', '').strip('"').replace('""', '"')
            if user_message:
                messages.append(user_message)

    # Analyze patterns
    first_words = Counter()
    imperative_verbs = Counter()
    question_msgs = []
    statement_msgs = []
    short_msgs = []
    single_word_msgs = []

    for msg in messages:
        analysis = classify_message_structure(msg)

        first_words[analysis['first_word']] += 1

        for verb in analysis['imperative_candidates']:
            imperative_verbs[verb] += 1

        if analysis['is_question']:
            question_msgs.append(msg)
        elif analysis['is_single_word']:
            single_word_msgs.append(msg)
        elif analysis['is_short']:
            short_msgs.append(msg)
        else:
            statement_msgs.append(msg)

    return {
        'total_count': len(messages),
        'messages': messages,
        'first_words': first_words,
        'imperative_verbs': imperative_verbs,
        'question_msgs': question_msgs,
        'statement_msgs': statement_msgs,
        'short_msgs': short_msgs,
        'single_word_msgs': single_word_msgs,
    }


def generate_swift_code_additions(analysis: dict) -> str:
    """Generate Swift code additions for classifyUserIntent()."""

    # Get top first words that could be imperative verbs
    top_first_words = [word for word, count in analysis['first_words'].most_common(30) if count >= 2]

    # Known existing verbs in the code (from TODOS.md analysis)
    existing_verbs = {
        'add', 'create', 'make', 'write', 'update', 'modify', 'delete',
        'remove', 'fix', 'change', 'show', 'display', 'list', 'get',
        'set', 'enable', 'disable', 'start', 'stop', 'run', 'execute',
        'install', 'configure', 'test', 'debug', 'check', 'verify',
        'search', 'find', 'open', 'close', 'can', 'could', 'please'
    }

    # Find new verbs to add
    new_verbs = [word for word in top_first_words if word not in existing_verbs and word.isalpha()]

    swift_code = []

    if new_verbs:
        swift_code.append("// Add these verbs to the imperativeVerbs set:")
        swift_code.append("let imperativeVerbs: Set<String> = [")
        swift_code.append("  // ... existing verbs ...")
        for verb in sorted(new_verbs):
            count = analysis['first_words'][verb]
            swift_code.append(f'  "{verb}",  // Found in {count} message(s)')
        swift_code.append("]")
        swift_code.append("")

    # Suggest statement patterns
    if analysis['statement_msgs']:
        swift_code.append("// Add statement pattern detection:")
        swift_code.append("// After directive and question checks, add:")
        swift_code.append("")
        swift_code.append("// Statement patterns (declarative sentences)")
        swift_code.append('if lowerFirst.hasPrefix("this ") || lowerFirst.hasPrefix("the ") {')
        swift_code.append('  return .directive  // Treat statements as directives')
        swift_code.append("}")
        swift_code.append("")
        swift_code.append('if lowerFirst.contains("need to") || lowerFirst.contains("should") {')
        swift_code.append('  return .directive')
        swift_code.append("}")
        swift_code.append("")

    # Suggest better UNKNOWN handling
    swift_code.append("// Better prompt for UNKNOWN intent:")
    swift_code.append("// In FoundationLLM.swift line ~1109, change:")
    swift_code.append("//   FROM: \"You requested \\(assistantName) to [infer from message]\"")
    swift_code.append("//   TO: \"You [concisely describe the action based on the MESSAGE]\"")
    swift_code.append("")

    return "\n".join(swift_code)


def generate_report(csv_path: str) -> str:
    """Generate a comprehensive improvement report."""
    analysis = analyze_csv(csv_path)

    report = []
    report.append("=" * 80)
    report.append("INTENT CLASSIFICATION IMPROVEMENT RECOMMENDATIONS")
    report.append("=" * 80)
    report.append("")
    report.append(f"Total messages analyzed: {analysis['total_count']}")
    report.append("")

    # Top first words
    report.append("TOP FIRST WORDS (potential missing verbs):")
    report.append("-" * 80)
    for word, count in analysis['first_words'].most_common(20):
        report.append(f"  {word:20} (appears {count} times)")
    report.append("")

    # Single-word commands
    if analysis['single_word_msgs']:
        report.append(f"SINGLE-WORD COMMANDS ({len(analysis['single_word_msgs'])}):")
        report.append("-" * 80)
        for msg in analysis['single_word_msgs'][:10]:
            report.append(f"  • {msg}")
        if len(analysis['single_word_msgs']) > 10:
            report.append(f"  ... and {len(analysis['single_word_msgs']) - 10} more")
        report.append("")

    # Short messages
    if analysis['short_msgs']:
        report.append(f"SHORT MESSAGES (2-3 words) ({len(analysis['short_msgs'])}):")
        report.append("-" * 80)
        for msg in analysis['short_msgs'][:10]:
            report.append(f"  • {msg}")
        if len(analysis['short_msgs']) > 10:
            report.append(f"  ... and {len(analysis['short_msgs']) - 10} more")
        report.append("")

    # Statement messages
    if analysis['statement_msgs']:
        report.append(f"STATEMENT PATTERNS ({len(analysis['statement_msgs'])}):")
        report.append("-" * 80)
        for msg in analysis['statement_msgs'][:10]:
            report.append(f"  • {msg}")
        if len(analysis['statement_msgs']) > 10:
            report.append(f"  ... and {len(analysis['statement_msgs']) - 10} more")
        report.append("")

    # Question messages
    if analysis['question_msgs']:
        report.append(f"QUESTION PATTERNS ({len(analysis['question_msgs'])}):")
        report.append("-" * 80)
        for msg in analysis['question_msgs'][:10]:
            report.append(f"  • {msg}")
        if len(analysis['question_msgs']) > 10:
            report.append(f"  ... and {len(analysis['question_msgs']) - 10} more")
        report.append("")

    # Code suggestions
    report.append("=" * 80)
    report.append("SUGGESTED CODE CHANGES")
    report.append("=" * 80)
    report.append("")
    report.append(generate_swift_code_additions(analysis))

    # Sample messages
    report.append("=" * 80)
    report.append("SAMPLE MESSAGES FOR MANUAL REVIEW")
    report.append("=" * 80)
    report.append("")
    for i, msg in enumerate(analysis['messages'][:20], 1):
        report.append(f"{i}. {msg}")

    if len(analysis['messages']) > 20:
        report.append(f"\n... and {len(analysis['messages']) - 20} more messages")

    return "\n".join(report)


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <csv_file>", file=sys.stderr)
        print("", file=sys.stderr)
        print("Generate this CSV by running:", file=sys.stderr)
        print("  scripts/analyze_intent_classification.sh", file=sys.stderr)
        sys.exit(1)

    csv_path = sys.argv[1]

    if not Path(csv_path).exists():
        print(f"❌ File not found: {csv_path}", file=sys.stderr)
        sys.exit(1)

    print(generate_report(csv_path))


if __name__ == "__main__":
    main()
