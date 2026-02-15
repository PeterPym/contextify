# Nightly E2E Test Schedule

> **Status: DISABLED (Jan 2026)**
> Nightly runs are currently disabled. The E2E tests need maintenance before re-enabling.
> Run tests manually with `./scripts/qa/run-all-tests.sh` when needed.

~~Automated nightly runs of the E2E test suite at 4am.~~

## Re-enable (when tests are fixed)

1. **Copy the plist to LaunchAgents:**
   ```bash
   cp scripts/qa/schedule/dev.contextify.qa-nightly.plist ~/Library/LaunchAgents/
   ```

2. **Load the agent:**
   ```bash
   launchctl load ~/Library/LaunchAgents/dev.contextify.qa-nightly.plist
   ```

3. **Schedule wake at 3:55am (requires sudo):**
   ```bash
   sudo pmset repeat wake MTWRFSU 03:55:00
   ```

## Verify

```bash
# Check agent is loaded
launchctl list | grep contextify

# Check wake schedule
pmset -g sched
```

## Disable

```bash
launchctl unload ~/Library/LaunchAgents/dev.contextify.qa-nightly.plist
sudo pmset repeat cancel
```

## Files

| File | Purpose |
|------|---------|
| `run-nightly.sh` | Wrapper script that runs tests and handles notifications |
| `dev.contextify.qa-nightly.plist` | launchd agent config (copy to ~/Library/LaunchAgents/) |
| `history.log` | Pass/fail history (one line per run) |
| `logs/` | Nightly run logs (gitignored, kept 30 days) |

## Failure Notification

On failure:
- `~/Desktop/QA-FAILED-YYYYMMDD.txt` created with failure details
- Silent macOS notification shown
- Entry logged to `history.log`

On success:
- Old failure markers removed
- Entry logged to `history.log`

## History Log Format

```
2025-12-11 04:00:00 PASS
2025-12-12 04:00:00 FAIL /path/to/log
```

## Requirements

- Laptop must be open (not clamshell) OR connected to external display + power
- If machine is closed/off at 4am, the run is skipped
