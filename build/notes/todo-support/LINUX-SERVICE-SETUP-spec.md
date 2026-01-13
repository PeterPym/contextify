---
todo_id: LINUX-SERVICE-SETUP
title: Linux Background Service for Automatic Ingestion
type: spec
date: 2026-01-12
status: draft
description: systemd user service setup for automatic periodic transcript ingestion on Linux
---

# Linux Background Service for Automatic Ingestion

## Problem Statement

The Linux CLI (`contextify-ingest`) currently requires manual invocation. Users must remember to run it periodically to keep their database updated with new transcripts. Without automatic ingestion, the Linux experience is incomplete compared to macOS where the app monitors transcripts in real-time.

This is blocking Linux from being a complete product (currently labeled Beta).

## Goal

Provide a single command that sets up automatic periodic ingestion:

```bash
contextify-ingest install-service
```

After running this, transcripts are automatically ingested every 15 minutes without user intervention.

## Design

### systemd User Service (Modern Linux Standard)

systemd user services are the modern standard for user-space daemons on Linux:
- No root required
- Survives logout (with `loginctl enable-linger`)
- Integrated logging via `journalctl --user`
- Timer units for scheduling (preferred over cron)

### Files to Generate

**Service unit:** `~/.config/systemd/user/contextify-ingest.service`
```ini
[Unit]
Description=Contextify transcript ingestion
Documentation=https://contextify.sh/docs/

[Service]
Type=oneshot
ExecStart=%h/.local/bin/contextify-ingest ingest --quiet
# %h expands to $HOME

[Install]
WantedBy=default.target
```

**Timer unit:** `~/.config/systemd/user/contextify-ingest.timer`
```ini
[Unit]
Description=Run Contextify ingestion periodically
Documentation=https://contextify.sh/docs/

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
```

### CLI Commands

**Install:**
```bash
contextify-ingest install-service [--interval 15m]
```
1. Write service and timer files to `~/.config/systemd/user/`
2. Run `systemctl --user daemon-reload`
3. Run `systemctl --user enable --now contextify-ingest.timer`
4. Print status and instructions

**Uninstall:**
```bash
contextify-ingest uninstall-service
```
1. Run `systemctl --user stop contextify-ingest.timer`
2. Run `systemctl --user disable contextify-ingest.timer`
3. Remove service and timer files
4. Run `systemctl --user daemon-reload`

**Status:**
```bash
contextify-ingest service-status
```
- Show timer status, next run time, last run result
- Wrapper around `systemctl --user status contextify-ingest.timer`

### Fallback: cron

For systems without systemd (rare but possible), provide manual cron instructions in docs:

```bash
# Add to crontab -e
*/15 * * * * ~/.local/bin/contextify-ingest ingest --quiet
```

## Implementation Notes

### Swift Implementation

The CLI already uses Swift Argument Parser. Add new subcommands:

```swift
struct InstallService: ParsableCommand {
    @Option(name: .long, help: "Ingestion interval")
    var interval: String = "15m"

    func run() throws {
        // 1. Check systemd availability
        // 2. Create ~/.config/systemd/user/ if needed
        // 3. Write service file
        // 4. Write timer file
        // 5. Shell out to systemctl commands
        // 6. Print success message
    }
}
```

### Error Handling

- Check if systemd is available (`which systemctl`)
- Check if user services are supported (`systemctl --user status`)
- Provide clear error messages with fallback instructions

### Idempotency

- `install-service` should be safe to run multiple times
- Update files if they exist, don't fail
- Only restart timer if config changed

## Testing

1. **Unit tests:** File generation produces valid systemd syntax
2. **Integration test:** Docker container with systemd, full install/uninstall cycle
3. **Manual QA:** Test on Ubuntu, Fedora, Arch

## Documentation

Update `/docs/` page with:
- Installation instructions including service setup
- How to check status (`contextify-ingest service-status`)
- How to view logs (`journalctl --user -u contextify-ingest`)
- Troubleshooting common issues

## References

- [systemd user units](https://wiki.archlinux.org/title/Systemd/User)
- [systemd timers](https://wiki.archlinux.org/title/Systemd/Timers)
- Cross-platform roadmap: `build/notes/todo-support/CROSS-PLATFORM-INGESTION-investigation.md` (Scheduling section)

## Effort Estimate

2-4 hours total:
- 30 min: Research/validate systemd patterns
- 1 hr: Implement install-service command
- 30 min: Implement uninstall-service command
- 30 min: Implement service-status command
- 30 min: Documentation updates
- 30 min: Testing
