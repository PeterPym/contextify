---
todo_id: SWIFTPM-LINUX-WARNINGS
title: SwiftPM Linux Warning Cleanup
type: reference
date: 2026-01-11
status: reference
description: Track P3 tech debt for SwiftPM unhandled file warnings in Linux builds
tags:
  - token-burner
---

# SwiftPM Linux Warning Cleanup

## Summary

Linux SwiftPM builds emit warnings about unhandled source files under `app/Sources/ContextifyCore`. The Linux targets point at this directory with explicit `sources` lists, so SwiftPM reports any files not listed as `sources` or `exclude`.

## Impact

- Warnings are noisy but do not fail the build.
- New files added under `app/Sources/ContextifyCore` re-trigger warnings.

## Root Cause

Linux targets use `path: "app/Sources/ContextifyCore"` with minimal `sources` lists. SwiftPM scans the target path and warns about any files not included as sources or resources.

## Options

1. Add `exclude` lists to Linux targets in `Package.swift` (quick but brittle).
2. Split Linux-only sources into dedicated directories (durable, larger refactor).

## Recommendation

Plan a source layout split for Linux-specific targets to eliminate warnings permanently.
