---
title: Text views
description: A text view displays multiline, styled text content, which can optionally be editable.
source: https://developer.apple.com/design/human-interface-guidelines/text-views
timestamp: 2025-12-15T00:13:10.161Z
---

**Navigation:** [Human Interface Guidelines](/design/human-interface-guidelines)

**article**

# Text views

> A text view displays multiline, styled text content, which can optionally be editable.



Text views can be any height and allow scrolling when the content extends outside of the view. By default, content within a text view is aligned to the leading edge and uses the system label color. In iOS, iPadOS, and visionOS, if a text view is editable, a keyboard appears when people select the view.

## Best practices

**Use a text view when you need to display text that’s long, editable, or in a special format.** Text views differ from [Text fields](/design/human-interface-guidelines/text-fields) and [Labels](/design/human-interface-guidelines/labels) in that they provide the most options for displaying specialized text and receiving text input. If you need to display a small amount of text, it’s simpler to use a label or — if the text is editable — a text field.

**Keep text legible.** Although you can use multiple fonts, colors, and alignments in creative ways, it’s essential to maintain the readability of your content. It’s a good idea to adopt Dynamic Type so your text still looks good if people change text size on their device. Be sure to test your content with accessibility options turned on, such as bold text. For guidance, see [Accessibility](/design/human-interface-guidelines/accessibility) and [Typography](/design/human-interface-guidelines/typography).

**Make useful text selectable.** If a text view contains useful information such as an error message, a serial number, or an IP address, consider letting people select and copy it for pasting elsewhere.

## Platform considerations

*No additional considerations for macOS, visionOS, or watchOS.*

### iOS, iPadOS

**Show the appropriate keyboard type.** Several different keyboard types are available, each designed to facilitate a different type of input. To streamline data entry, the keyboard you display when editing a text view needs to be appropriate for the type of content. For guidance, see [Virtual keyboards](/design/human-interface-guidelines/virtual-keyboards).

### tvOS

You can display text in tvOS using a text view. Because text input in tvOS is minimal by design, tvOS uses [Text fields](/design/human-interface-guidelines/text-fields) for editable text instead.

## Resources

#### Related

[Labels](/design/human-interface-guidelines/labels)

[Text fields](/design/human-interface-guidelines/text-fields)

[Combo boxes](/design/human-interface-guidelines/combo-boxes)

#### Developer documentation

[Text](/documentation/SwiftUI/Text) — SwiftUI

[UITextView](/documentation/UIKit/UITextView) — UIKit

[NSTextView](/documentation/AppKit/NSTextView) — AppKit

## Change log

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All Human Interface Guidelines belong to Apple Inc.*
