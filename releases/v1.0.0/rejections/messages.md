# App Store Rejection Messages - v1.0.0

Source: App Store Connect Resolution Center
Captured: 2025-12-03

---

## Message 1: Build 3 Rejection

**From:** Apple
**Date:** 2025-11-26 9:18 AM
**Submission ID:** 4a125b1d-7e23-4cb4-be80-09aaa29168cf
**Version reviewed:** 1.0
**Build:** 3
**Rejection Reason:** 2.1.0 Performance: App Completeness (macOS)

### Review Environment

- Submission ID: 4a125b1d-7e23-4cb4-be80-09aaa29168cf
- Review date: November 26, 2025
- Version reviewed: 1.0

### Guideline 2.1 - Information Needed

We are unable to successfully access all of the app. In order for us to continue the review, we need sample files to verify all of the app features and functionality.

**Next Steps**

Provide sample files of Claude project files we can use to review summarize feature. The sample files you provide should be hosted at a location that will remain available for future reviews

**Resources**

To learn more about providing information to App Review in App Store Connect, see [App Store Connect Help](https://developer.apple.com/help/app-store-connect/reference/app-review-information/).

### Guideline 2.1 - Information Needed

Before we can complete our review of your app, we need a video that demonstrates the current version of your app in use on a physical macOS device.

The demo video should:
- Show your app running on a physical device, not on a simulator.
- Clearly documents all relevant app features, services, and user permission requests.

**Next Steps**

Provide a link to the video in the App Review Information section of your app's page in App Store Connect and reply to this message. You can use a screen recorder to capture footage of your app in use. Note that if your app can only be reviewed with a demo video, you'll need to provide an updated demo video for every app submission.

**Resources**

To learn more about providing information to App Review in App Store Connect, see [App Store Connect Help](https://developer.apple.com/help/app-store-connect/reference/app-review-information/).

---

## Message 2: Build 10 Rejection

**From:** Apple
**Date:** 2025-12-03 12:49 PM
**Submission ID:** 4a125b1d-7e23-4cb4-be80-09aaa29168cf
**Version reviewed:** 1.0
**Build:** 10

### Opening

Hello,

The issues we previously identified still need your attention.

If you have any questions, we are here to help. Reply to this message in App Store Connect and let us know.

### Review Environment

- Submission ID: 4a125b1d-7e23-4cb4-be80-09aaa29168cf
- Review date: December 03, 2025
- Version reviewed: 1.0

### Guideline 2.4.5(i) - Performance

Your app saves user data to the app's container, which is not user accessible, as documented in the "Container Directories and File System Access" of [App Sandbox Design Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/AboutAppSandbox/AboutAppSandbox.html):

> "The container is in a hidden location, and so users do not interact with it directly. Specifically, the container is not for user documents. It is for files that your app uses, along with databases, caches, and other app-specific data."

**Next Steps**

It would be appropriate to save user files to a location selected by or available to users, using standard Save dialogs. For more information, see the "Save Dialogs" section of the [App Sandbox Design Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/AboutAppSandbox/AboutAppSandbox.html).

---

## Support (included in both messages)

- Reply to this message in your preferred language if you need assistance. If you need additional support, use the [Contact Us module](https://developer.apple.com/contact/topic/#!/topic/select).
- Consult with fellow developers and Apple engineers on the [Apple Developer Forums](https://developer.apple.com/forums/).
- Provide feedback on this message and your review experience by [completing a short survey](https://essentials.applesurveys.com/jfe/form/SV_esVePfih7uqt4NM?campaignid=0001).
