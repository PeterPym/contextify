---
todo_id: P1-HELP-DOCUMENTATION
title: Help Documentation Research
type: research
date: 2025-11-27
status: reference
description: Research on help documentation best practices from major apps. Reference for implementing contextify.sh/help/ pages.
---

# Help Documentation Research

**Date:** November 27, 2025
**Purpose:** Best practices for help documentation from major macOS apps

---

## Industry Examples

### 1Password (support.1password.com)

**Structure:** 8 tile-based categories on hub page

| Category | Purpose |
|----------|---------|
| Get Started | Setup and first use |
| Using 1Password | Core features |
| Families | Multi-user scenarios |
| Billing and Subscriptions | Account management |
| Teams and Business | Enterprise features |
| Managed Service Providers | MSP-specific |
| Troubleshooting | Common issues |
| Security | Trust and privacy |

**Patterns:**
- Tile-based hub → category → articles (2-3 levels)
- Platform-specific guides (Mac, iOS, Windows, Android, Linux, CLI)
- Featured articles for common questions
- Community forum link for peer support
- Quick access callouts for: Secret Key, lost passwords, browser issues

---

### Raycast (manual.raycast.com)

**Structure:** Platform-based manuals + FAQ

| Section | Content |
|---------|---------|
| Raycast Mac Manual | Core documentation |
| Raycast Windows Beta Manual | Platform-specific |
| Raycast iOS Manual | Mobile companion |
| Community Guidelines | User conduct |
| Extensions Guidelines | Developer docs |
| AI Privacy + Security | Trust documentation |

**Patterns:**
- Notion-based (easy to update, familiar UI)
- Expandable toggle sections
- Direct URL copy for sharing specific sections
- FAQ at bottom for common questions
- Light/dark theme support

---

### Bear (bear.app/faq/)

**Structure:** 10 topic groups on single page

| Group | Topics |
|-------|--------|
| Get Started | What's New, Markdown basics |
| Edit and Format | Typography, emojis, code, math |
| Web Clip and Links | Wiki links, backlinks |
| Images and Files | Attachments, photos, sketches |
| Organize with Tags | Nested tags, customization |
| Info and Navigation | TOC, sidebars, history |
| Search | Search and replace |
| Extra | Watch, widgets, Siri, shortcuts |
| Note Safety | Encryption, backup, app lock |
| Import/Migrate | Evernote, Obsidian migration |

**Patterns:**
- Single long page with anchor links (simple)
- Newsletter signup embedded
- Support contact at bottom
- Migration guides for competitive apps (acquisition)

---

## Common Patterns Across All

### Information Architecture

1. **"Get Started" always first** - New user quick win
2. **Troubleshooting is prominent** - Don't bury it
3. **Flat hierarchy** - 1-2 levels max, avoid deep nesting
4. **Platform-specific when needed** - Separate guides per OS
5. **Security/Privacy section** - Trust building, especially for data apps
6. **Search is essential** - All major help sites have search

### User Experience

1. **Hub page** - Central entry point with clear categories
2. **Anchor links** - Deep linking to specific sections
3. **Copy URL buttons** - Easy sharing for support
4. **Dark mode support** - Match app aesthetic
5. **Mobile responsive** - Users may check help on phone

### Growth Opportunities

1. **Newsletter signup** - Bear embeds in help pages
2. **Community links** - 1Password promotes forum
3. **Feature discovery** - Help pages surface lesser-known features
4. **Migration guides** - Capture users from competitors
5. **Feedback loops** - "Was this helpful?" prompts

---

## Recommended Structure for Contextify

### URL Structure

```
contextify.sh/
├── /help                    → Hub page (all sections)
├── /help/getting-started    → Quick setup (5 min)
├── /help/features           → Feature overview
├── /help/keyboard-shortcuts → Reference table
├── /help/troubleshooting    → Common issues
├── /help/privacy            → Data handling
└── /support                 → Contact form/email
```

### Help Menu Mapping

| Menu Item | URL | Purpose |
|-----------|-----|---------|
| Contextify Help | /help | Hub page |
| Getting Started | /help/getting-started | Onboarding |
| Keyboard Shortcuts | /help/keyboard-shortcuts | Reference |
| Troubleshooting | /help/troubleshooting | Self-service |
| Contact Support... | mailto: | Human help |

### Content Priority (P0 for launch)

1. **Getting Started** - Essential for new users
2. **Keyboard Shortcuts** - Quick reference
3. **Troubleshooting** - Reduce support load

### Content Priority (P1 post-launch)

4. **Features** - Discovery and education
5. **Privacy** - Trust building
6. **FAQ** - Common questions

---

## Engagement & Growth Opportunities

### Reengagement Points

| Location | Mechanism | Goal |
|----------|-----------|------|
| Help hub footer | Newsletter signup | Updates, tips |
| Troubleshooting pages | "Still stuck? Email us" | Support funnel |
| Feature pages | "Try it now" deep links | Feature adoption |
| Getting started | Progress checklist | Onboarding completion |

### Feedback Loops

| Location | Mechanism | Data Captured |
|----------|-----------|---------------|
| Every help page | "Was this helpful? Yes/No" | Content quality |
| Troubleshooting | "Did this solve your problem?" | Issue resolution |
| Contact form | Category dropdown | Issue categorization |
| 404 pages | "What were you looking for?" | Content gaps |

### User Growth Flywheels

1. **Help → Feature Discovery → Usage → Referral**
   - Help pages expose features users didn't know existed
   - Increased usage → more value → more likely to recommend

2. **Troubleshooting → Resolution → Trust → Review**
   - Self-service problem solving builds confidence
   - Confident users leave positive reviews

3. **Migration Guides → Acquisition**
   - "Coming from [Competitor]?" pages
   - Reduce friction for switching users

4. **Keyboard Shortcuts → Power Users → Advocates**
   - Power users become vocal advocates
   - Shortcut mastery = deep product investment

5. **Newsletter → Tips → Engagement → Retention**
   - Regular tips keep app top-of-mind
   - Reduce churn from "forgot I had this"

---

## Analytics to Implement

### Page-Level Metrics

- Page views per help article
- Time on page (engagement)
- Bounce rate (content quality)
- Exit pages (where users give up)

### Funnel Metrics

- Help → Support contact rate (lower = better self-service)
- Help → App deep link clicks (feature adoption)
- Newsletter signup conversion rate

### Search Metrics (if implemented)

- Top search queries (content gaps)
- Zero-result searches (missing content)
- Search → article → success rate

---

## Technical Implementation Notes

### For Static Site (contextify.sh)

- Use anchor IDs for deep linking
- Add `?ref=app-help-menu` UTM for analytics
- Implement simple "Was this helpful?" with POST to analytics endpoint
- Consider Plausible or Fathom for privacy-respecting analytics

### For Help Menu (ContextifyApp.swift)

```swift
enum HelpTopic {
  case hub, gettingStarted, shortcuts, troubleshooting

  var url: URL {
    let base = "https://contextify.sh/help"
    let path = switch self {
      case .hub: ""
      case .gettingStarted: "/getting-started"
      case .shortcuts: "/keyboard-shortcuts"
      case .troubleshooting: "/troubleshooting"
    }
    return URL(string: "\(base)\(path)?ref=app-help-menu")!
  }
}
```

---

## Sources

- [1Password Support](https://support.1password.com) - Enterprise-grade help structure
- [Raycast Manual](https://manual.raycast.com) - Developer tool documentation
- [Bear FAQ](https://bear.app/faq/) - Indie app single-page approach
- [MacMost: Use the Help Menu](https://macmost.com/use-the-help-menu-to-get-to-app-documentation.html) - User perspective
- [Apple Help Programming Guide](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/ProvidingUserAssitAppleHelp/user_help_intro/user_assistance_intro.html) - Apple's guidance
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) - Design principles
