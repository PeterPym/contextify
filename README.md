# Contextify

**macOS companion for Claude Code and Codex CLI**

Monitor your AI coding sessions with real-time timeline and LLM-powered summaries.

## Features

- **Real-time timeline** of your AI coding sessions
- **Local database backup** of all conversations
- **LLM-generated summaries** using macOS on-device intelligence
- **Always-on-top window** to monitor sessions while you work
- **Project-centric view** across multiple sessions
- **Search** across all your AI conversations
- **Total Recall** - teach your AI to search your conversation history
- **Companion CLI** for macOS and Linux

## Download

### macOS App
- [Direct Download (DMG)](https://github.com/PeterPym/contextify/releases/latest)
- [Mac App Store](https://apps.apple.com/us/app/contextify/id6753190666?mt=12)

### CLI (macOS)
```bash
brew tap peterpym/contextify && brew install contextify-query
contextify install-plugin
```

### CLI (Linux)
```bash
curl -fsSL https://contextify.sh/install.sh | sh
```

The CLI enables [Total Recall](https://contextify.sh/docs/cli) - semantic search of your conversation history from Claude Code or Codex CLI.

## System Requirements

- macOS 15 (Sequoia) or later
- AI summaries require macOS 26 (Tahoe). On Sequoia, Lite Mode provides timeline and search.
- Works with Claude Code and Codex CLI
- Linux CLI requires a shared database (Dropbox, iCloud Drive) from a Mac with Contextify

## Documentation

Visit [contextify.sh](https://contextify.sh) for documentation and support.

## Support

- [Report a Bug](https://github.com/PeterPym/contextify/issues/new?template=bug_report.md)
- [Request a Feature](https://github.com/PeterPym/contextify/issues/new?template=feature_request.md)
- [Contact Support](mailto:support@contextify.sh)

## Privacy

Contextify stores all data locally on your Mac. No cloud services, no tracking, no analytics. Your conversations stay on your device.

See our [Privacy Policy](https://contextify.sh/privacy.html) for details.

## License

Copyright 2025 Contextify. All rights reserved.
