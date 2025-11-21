# Customer Support Operations

**Last Updated:** 2025-11-19
**Contact:** support@contextify.sh
**Status:** Pre-launch setup

---

## Purpose

Document workflows for handling inbound customer support requests, triaging issues, and routing actionable items to development TODOs.

---

## Contact Information

**Email Addresses:**
- **support@contextify.sh** - Primary customer support (public-facing)
  - Listed on website, App Store, documentation
  - For user questions, bug reports, feature requests
  - Response SLA: <24 hours on weekdays

- **rob@contextify.sh** - Personal contact (semi-public)
  - For business inquiries, partnerships, press
  - Alternative for users who prefer direct contact
  - Response SLA: Best effort

**Coverage:** Manual monitoring (no automation initially)

**Secondary Channels (Future):**
- GitHub Issues (for bug reports from power users)
- Twitter/X @contextify (community questions)
- In-app feedback form (post-launch feature)

---

## Email Setup

**Provider:** Apple Custom Email (via iCloud+)
**Domain:** contextify.sh (DNS at DigitalOcean)

### DNS Records Required

Apple will provide these during setup:

```
Type: MX
Priority: 10
Value: mx01.mail.icloud.com.

Type: MX
Priority: 10
Value: mx02.mail.icloud.com.

Type: TXT
Name: @
Value: v=spf1 include:icloud.com ~all

Type: TXT (DKIM)
Name: sig1._domainkey
Value: [Apple provides during setup]
```

### Setup Checklist

- [ ] Add contextify.sh to iCloud+ Custom Email
- [ ] Add DNS records at DigitalOcean
- [ ] Create support@contextify.sh address
- [ ] Create rob@contextify.sh address
- [ ] Test sending/receiving from both addresses
- [ ] Update website support.html with support@ address
- [ ] Update TODOS.md item #2 as complete

---

## Support Request Workflow

### 1. Initial Triage (5-10 minutes per request)

**Categorize incoming emails:**

| Category | Description | Priority | Action |
|----------|-------------|----------|--------|
| **Bug Report** | App crashes, data loss, broken features | P0-P1 | Create TODO, request logs/steps |
| **Feature Request** | User wants new functionality | P2-P3 | Add to feature backlog |
| **How-To Question** | User needs help using existing features | Low | Respond with instructions |
| **Account/License** | Purchase issues, refunds, licensing | High | Handle directly, escalate if needed |
| **Spam/Invalid** | Junk, unrelated | N/A | Archive/delete |

### 2. Response Templates

#### Bug Report Response
```
Subject: Re: [Original Subject]

Hi [Name],

Thanks for reporting this issue. I've created a tracking item and will investigate.

To help diagnose this, could you provide:
- macOS version (About This Mac → Overview)
- Contextify version (App menu → About Contextify)
- Steps to reproduce the issue
- Any error messages you saw

Optional but helpful:
- Console.app logs (see: https://contextify.sh/support.html#logs)
- Screenshot of the issue

I'll follow up once I have more information.

Best,
Rob
Contextify Support
```

#### Feature Request Response
```
Subject: Re: [Feature Request Subject]

Hi [Name],

Thanks for the suggestion! I've added this to the feature backlog for consideration.

I can't promise a timeline, but I track all feature requests and prioritize based on user demand and technical feasibility.

If you have additional context on how this would help your workflow, feel free to share—it helps with prioritization.

Best,
Rob
```

#### How-To Response
```
Subject: Re: [Question Subject]

Hi [Name],

[Specific instructions for their question]

You can find more information in our support docs: https://contextify.sh/support.html

Let me know if you need further clarification!

Best,
Rob
```

### 3. Create TODO Items

**For bugs and feature requests that warrant development work:**

1. Open `build/notes/TODOS.md`
2. Add item to appropriate priority section:
   - **P0:** App crashes, data loss, blocks core functionality
   - **P1:** Significant UX issues, frequently requested features
   - **P2:** Nice-to-have improvements, edge case bugs
   - **P3:** Low-impact enhancements

3. Include in TODO entry:
   - Brief description
   - Link to support email (Gmail search link or email archive)
   - User's email (for follow-up when fixed)
   - Steps to reproduce (if bug)
   - Estimated effort

**Example TODO entry:**
```markdown
### Customer-Reported Bugs (2 items)

- [ ] #120: Fix timeline not loading after OS sleep/wake (support@: user@example.com, 2025-11-20)

**Problem:** Timeline shows empty after Mac wakes from sleep. Requires app restart.

**Steps to Reproduce:**
1. Open Contextify with active project
2. Put Mac to sleep (close lid)
3. Wake Mac after 1+ hour
4. Timeline is blank, project still shows in tab bar

**Files:** Likely `ConversationMonitor.swift` (wake notification handling)
**Effort:** 2-3 hours
**User Impact:** High (breaks core functionality)
```

### 4. Follow-Up When Fixed

When a TODO is completed:

1. Find original support email
2. Send follow-up notification:

```
Subject: Re: [Original Issue]

Hi [Name],

Good news! I've fixed the issue you reported in version [X.Y.Z].

[Brief description of the fix]

The update is available now via [App Store / DMG download].

Thanks again for reporting this—your feedback helps make Contextify better.

Best,
Rob
```

---

## Support Request Tracking

### Email Organization (Gmail/iCloud Mail)

**Labels/Folders:**
- `Contextify/Open` - Awaiting response or action
- `Contextify/Waiting` - Waiting on user for more info
- `Contextify/Fixed` - Issue resolved, user notified
- `Contextify/Archived` - Closed/resolved

**Search Queries:**
```
# Find all open support requests
label:contextify-open is:unread

# Find specific user's requests
from:user@example.com label:contextify

# Find bug reports needing follow-up
label:contextify-waiting-fix
```

### Support Metrics (Optional, Post-Launch)

Track in simple spreadsheet or notes:
- **Volume:** Requests per week
- **Response time:** Hours to first response
- **Resolution time:** Days to close ticket
- **Top issues:** Most common questions/bugs
- **Feature requests:** Tally votes for popular features

**Review quarterly** to identify:
- Documentation gaps (frequent how-to questions → add to docs)
- Bug patterns (multiple reports of same issue → prioritize fix)
- Feature validation (high demand → move to P1)

---

## Escalation & Edge Cases

### Refund Requests

**Policy:** 30-day money-back guarantee (standard App Store policy applies)

**Process:**
1. Respond within 24 hours
2. Ask for feedback on what didn't work
3. For App Store purchases: Direct user to App Store refund request process
4. For direct sales (future): Process via payment provider

### Data Loss / Critical Bugs

**Priority:** P0 - Drop everything

**Process:**
1. Respond immediately (within 2 hours if possible)
2. Request database file + logs via secure method (not email)
3. Investigate with highest priority
4. Offer workaround if available
5. Ship hotfix within 48 hours if confirmed critical

### Angry/Frustrated Users

**Guidelines:**
- Stay professional and empathetic
- Acknowledge their frustration
- Focus on solutions, not excuses
- Offer refund if app isn't meeting their needs
- Don't take it personally

**Template:**
```
Hi [Name],

I'm really sorry you've had this experience with Contextify. That's not the quality I aim for.

[Acknowledge specific issue]

Here's what I'm going to do:
[Specific action plan]

If you'd prefer a refund while I work on this, I completely understand. Let me know how you'd like to proceed.

Best,
Rob
```

---

## Knowledge Base (Future)

As support volume grows, consider:

### FAQ Expansion
- Migrate common questions to support.html
- Add troubleshooting section
- Link to specific docs for complex issues

### Video Tutorials
- Screen recordings for common workflows
- Host on Vimeo/YouTube (privacy-friendly)
- Embed on support page

### Community Forum (Maybe)
- GitHub Discussions (free, integrated with repo)
- Allows users to help each other
- Reduces support burden

---

## Tools & Resources

### Current (Manual)
- Email: support@contextify.sh (iCloud Mail)
- TODO tracking: `build/notes/TODOS.md`
- Issue tracking: GitHub Issues (optional for power users)

### Future Considerations (If Volume Grows)
- **Help Scout** - Simple support ticket system ($20/month)
- **Linear** - Issue tracking with email integration ($8/user/month)
- **GitHub Issues** - Free, version control integrated
- **Notion** - Knowledge base + ticket tracking (free tier available)

**Decision point:** If receiving >10 support requests/week, consider dedicated tooling.

---

## Privacy & Data Handling

**Important:** Support requests may contain:
- User's project paths (potentially sensitive)
- Transcript contents (code, conversations)
- Database files (user's full activity history)

**Guidelines:**
- Never share user data publicly (sanitize examples in TODOs)
- Delete database files after investigation
- Use encrypted channels for sensitive data transfers
- Respect user privacy in bug reports

**User Data Request Process:**
If user sends logs/database for debugging:
1. Store locally in `/tmp/support-cases/[ticket-id]/`
2. Investigate and document findings
3. Delete files when case closed
4. Never commit user data to git repo

---

## Website Integration

**Update Required:**
- Update `website/src/support.html` to show `support@contextify.sh`
- Update `website/src/privacy.html` if collecting support request data
- Add "Contact Support" section with email and response time expectations

**Deployment:**
```bash
./scripts/deploy-website.sh
```

---

## Getting Started Checklist

**Pre-Launch:**
- [ ] Complete Apple Custom Email setup
- [ ] Test sending/receiving at support@contextify.sh
- [ ] Update website with support email
- [ ] Create email labels/folders for organization
- [ ] Save response templates somewhere accessible
- [ ] Add calendar reminder to check support inbox daily

**Post-Launch:**
- [ ] Monitor support@ daily (weekdays)
- [ ] Respond to all requests within 24 hours
- [ ] Create TODOs for actionable bugs/features
- [ ] Track volume and common issues
- [ ] Review support metrics monthly

---

## Related Documentation

- **Website:** `build/docs/operations/WEBSITE.md`
- **App Store:** `build/notes/todo-support/P0-APP-STORE-checklist.md`
- **TODOs:** `build/notes/TODOS.md`
- **Logging:** `build/docs/guides/logging-best-practices.md` (for requesting logs from users)

---

**Maintained by:** Rob Banagale
**Review frequency:** Quarterly or as needed
**Last reviewed:** 2025-11-19
