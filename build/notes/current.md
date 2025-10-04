# Current Work

## Status: Ready for Testing 🧪

### 2025-10-03 - iTerm2 Daemon Implementation

**Branch:** `feature/python-daemon`

**Goal:** Replace process-per-request model with long-running Python daemon for near-instantaneous iTerm2 content retrieval.

**Completed:**
- ✅ Python daemon with Unix socket IPC (length-prefixed JSON protocol)
- ✅ LaunchAgent manager for daemon lifecycle
- ✅ Swift daemon client with security validation
- ✅ Integration into TerminalContentReader with fallback chain
- ✅ Healthcheck script for diagnostics
- ✅ Build verification (compiles successfully)

**Architecture:**
```
Hotkey Press → Daemon Client → Unix Socket → Python Daemon → iTerm2 API
              (500ms timeout)   (persistent)  (10-20ms)

Fallback chain:
1. Daemon (fast path, <30ms)
2. Legacy Python reader (process-per-request, 200-500ms)
3. AppleScript (slowest, ~500ms+)
```

**Testing Required:**
1. Manual daemon startup and healthcheck
2. End-to-end hotkey flow (Cmd+Shift+K+K)
3. LaunchAgent installation and auto-start
4. Daemon recovery after iTerm2 restart
5. Performance benchmarking (expected P95 <30ms)

**Next Step:** User needs to add Swift files to Xcode project and test hotkey flow

**Files:**
- `scripts/iterm2_daemon.py` - Long-running daemon
- `scripts/test_daemon.py` - Test client
- `scripts/healthcheck.sh` - Diagnostics
- `Contextify/Contextify/LaunchAgentManager.swift` - LaunchAgent lifecycle
- `Contextify/Contextify/ITerm2DaemonClient.swift` - Unix socket client
- `Contextify/Contextify/TerminalContentReader.swift` - Integration (modified)

---

## Next Steps (Ideas)

Based on user needs, consider:

1. **History/Recovery Features** (see `future-compose-features.md`)
   - Undo cleared text
   - Draft history navigation
   - Auto-save on replace

2. **Restore Contextify Features** (selectively)
   - File ingestion (drag-and-drop)
   - Session/checkpoint management
   - As collapsible section or menu items

3. **Quality of Life**
   - Preferences panel
   - Custom keyboard shortcuts
   - Window position/size persistence
   - Always-on-top toggle

4. **Enhanced iTerm2 Integration**
   - Auto-refresh session name
   - Pin specific session
   - Multi-target send

See `future-compose-features.md` for comprehensive list of ideas.

---

_Ready for next feature branch!_
