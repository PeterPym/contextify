# Example Monitoring Scripts

These are **reference implementations** showing how to create feature-specific monitoring scripts.

## Purpose

Use these as templates when creating custom monitors for specific features or subsystems. They demonstrate:
- Subsystem/category configuration for specific features
- Custom color-coding for different event types
- Tag filtering for domain-specific workflows

## Scripts

### monitor-cache-generation.sh
Monitors the timeline cache miss generator and LLM summarization flow.

**Use when:** Debugging timeline summary generation, LLM performance, cache misses

**Subsystem:** `dev.contextify.timeline`
**Categories:** `ConversationMonitor`, `CacheMissGenerator`

### monitor-summarization-flow.sh
Monitors the full summarization pipeline from viewport changes to LLM completion.

**Use when:** Debugging summarization delays, tracking present/past form generation

**Subsystem:** `dev.contextify.timeline`
**Categories:** `ConversationMonitor`, `CacheMissGenerator`

### monitor-ui-performance.sh
Monitors UI rendering performance, viewport updates, and user interactions.

**Use when:** Debugging UI lag, scroll performance, render bottlenecks

**Subsystem:** `dev.contextify`
**Categories:** `ConversationMonitor`, `UIRender`, `EntryRow`

## Creating Your Own

For most debugging tasks, use the **core templates** in the parent directory:
- `monitor-interactive.sh` - Real-time observation with color coding
- `monitor-automated-test.sh` - Self-validating test harness
- `monitor-pipeline-check.sh` - Pipeline completeness verification

Only create custom monitors when you need:
- Feature-specific tag combinations not covered by templates
- Custom color-coding for domain-specific workflows
- Permanent monitoring scripts for frequently-debugged features

See the main `README.md` for the recommended debugging workflow.
