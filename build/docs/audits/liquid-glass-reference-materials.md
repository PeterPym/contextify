# Liquid Glass Reference Materials

**Purpose:** Supporting documentation for Liquid Glass compliance audit
**Date:** 2025-11-19
**Related:** `liquid-glass-audit-2025-11-19.md`

This document contains the complete reference materials from Apple's Liquid Glass documentation, formatted for easy review and reference during audit implementation.

---

## Table of Contents

1. [Adopting Liquid Glass (Overview)](#1-adopting-liquid-glass-overview)
2. [Applying Liquid Glass to Custom Views](#2-applying-liquid-glass-to-custom-views)
3. [WWDC 2025 Session 323: Meet Liquid Glass](#3-wwdc-2025-session-323-meet-liquid-glass)
4. [Landmarks Sample App: Building with Liquid Glass](#4-landmarks-sample-app-building-with-liquid-glass)
5. [Quick Reference: Key APIs](#5-quick-reference-key-apis)

---

## 1. Adopting Liquid Glass (Overview)

**Source:** https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass

### Overview

If you have an existing app, adopting Liquid Glass doesn't mean reinventing your app from the ground up. Start by building your app in the latest version of Xcode to see the changes. As you review your app, use the following sections to understand the scope of changes and learn how you can adopt these best practices in your interface.

### See Your App with Liquid Glass

If your app uses standard components from SwiftUI, UIKit, or AppKit, your interface picks up the latest look and feel on the latest platform releases for iOS, iPadOS, macOS, tvOS, and watchOS. In Xcode, build your app with the latest SDKs, and run it on the latest platform releases to see the changes in your interface.

### Visual Refresh

Interfaces across Apple platforms feature a new dynamic material called Liquid Glass, which combines the optical properties of glass with a sense of fluidity. This material forms a distinct functional layer for controls and navigation elements. It affects how the interface looks, feels, and moves, adapting in response to a variety of factors to help bring focus to the underlying content.

**Leverage system frameworks to adopt Liquid Glass automatically.** In system frameworks, standard components like bars, sheets, popovers, and controls automatically adopt this material. System frameworks also dynamically adapt these components in response to factors like element overlap and focus state. Take advantage of this material with minimal code by using standard components from SwiftUI, UIKit, and AppKit.

**Reduce your use of custom backgrounds in controls and navigation elements.** Any custom backgrounds and appearances you use in these elements might overlay or interfere with Liquid Glass or other effects that the system provides, such as the scroll edge effect. Make sure to check any custom backgrounds in elements like split views, tab bars, and toolbars. Prefer to remove custom effects and let the system determine the background appearance, especially for the following elements:

**SwiftUI:**
- `NavigationStack`
- `NavigationSplitView`
- `titleBar`
- `toolbar(content:)`

**Test your interface with accessibility settings.** Translucency and fluid morphing animations contribute to the look and feel of Liquid Glass, but can adapt to people's needs. For example, people might turn on accessibility settings that reduce transparency or motion in the interface, which can remove or modify certain effects. If you use standard components from system frameworks, this experience adapts automatically. Ensure your custom elements and animations provide a good fallback experience when these settings are on as well.

**Avoid overusing Liquid Glass effects.** If you apply Liquid Glass effects to a custom control, do so sparingly. Liquid Glass seeks to bring attention to the underlying content, and overusing this material in multiple custom controls can provide a subpar user experience by distracting from that content. Limit these effects to the most important functional elements in your app.

**SwiftUI API:** `glassEffect(_:in:)`

---

### App Icons

App icons take on a design that's dynamic and expressive. Updates to the icon grid result in a standardized iconography that's visually consistent across devices and concentric with hardware and other elements across the system. App icons now contain layers, which dynamically respond to lighting and other visual effects the system provides. iOS, iPadOS, and macOS all now offer default (light), dark, clear, and tinted appearance variants, empowering people to personalize the look and feel of their Home Screen.

**Reimagine your app icon for Liquid Glass.** Apply key design principles to help your app icon shine:

- Provide a visually consistent, optically balanced design across the platforms your app supports.
- Consider a simplified design comprised of solid, filled, overlapping semi-transparent shapes.
- Let the system handle applying masking, blurring, and other visual effects, rather than factoring them into your design.

**Design using layers.** The system automatically applies effects like reflection, refraction, shadow, blur, and highlights to your icon layers. Determine which elements of your design make sense as foreground, middle, and background elements, then define separate layers for them. You can perform this task in the design app of your choice.

**Compose and preview in Icon Composer.** Drag and drop app icon layers that you export from your design app directly into the Icon Composer app. Icon Composer lets you add a background, create layer groupings, adjust layer attributes like opacity, and preview your design with system effects and appearances. Icon Composer is available in the latest version of Xcode and for download from Apple Design Resources.

**Preview against the updated grids.** The system applies masking to produce your final icon shape — rounded rectangle for iOS, iPadOS, and macOS, and circular for watchOS. Keep elements centered to avoid clipping. Irregularly shaped icons receive a system-provided background. See how your app icon looks with the updated grids to determine whether you need to make adjustments. Download these grids from Apple Design Resources.

---

### Controls

Controls have a refreshed look across platforms, and come to life when a person interacts with them. For controls like sliders and toggles, the knob transforms into Liquid Glass during interaction, and buttons fluidly morph into menus and popovers. The shape of the hardware informs the curvature of controls, so many controls adopt rounder forms to elegantly nestle into the corners of windows and displays. Controls also feature an option for an extra-large size, allowing more space for labels and accents.

**Review updates to control appearance and dimensions.** If you use standard controls from system frameworks and don't hard-code their layout metrics, your app adopts changes to shapes and sizes automatically when you rebuild your app with the latest version of Xcode. Review changes to the following controls and any others and make sure they continue to look at home with the rest of your interface:

**SwiftUI:**
- `Button`
- `Toggle`
- `Slider`
- `Stepper`
- `Picker`
- `TextField`

**Review your use of color in controls.** Be judicious with your use of color in controls and navigation so they stay legible. If you do apply color to these elements, leverage system colors to automatically adapt to light and dark contexts.

**Check for crowding or overlapping of controls.** Prefer to use standard spacing metrics instead of overriding them, and avoid overcrowding or layering Liquid Glass elements on top of each other.

**Optimize for legibility when content scrolls beneath controls.** Scroll views offer a scroll edge effect that helps maintain sufficient legibility and contrast for controls by obscuring content that scrolls beneath them. System bars like toolbars adopt this behavior by default. If you use a custom bar with elements like controls, text, or icons that have content scrolling beneath them, you can register those views to use a scroll edge effect with these APIs:

**SwiftUI:**
- `safeAreaBar(edge:alignment:spacing:content:)`

**Consider aligning the shape of controls with other rounded elements throughout the interface.** Across Apple platforms, the shape of the hardware informs the curvature, size, and shape of nested interface elements, including controls, sheets, popovers, windows, and more. Help maintain a sense of visual continuity in your interface by using rounded shapes that are concentric to their containers using these APIs:

**SwiftUI:**
- `rect(corners:isUniform:)`
- `ConcentricRectangle`

**Leverage new button styles.** Instead of creating buttons with custom Liquid Glass effects, you can adopt the look and feel of the material with minimal code by using one of the following button style APIs:

**SwiftUI:**
- `glass`
- `glassProminent`
- `glass(_:)`

---

### Navigation

Liquid Glass applies to the topmost layer of the interface, where you define your navigation. Key navigation elements like tab bars and sidebars float in this Liquid Glass layer to help people focus on the underlying content.

**Establish a clear navigation hierarchy.** It's more important than ever for your app to have a clear and consistent navigation structure that's distinct from the content you provide. Ensure that you clearly separate your content from navigation elements, like tab bars and sidebars, to establish a distinct functional layer above the content layer.

**Consider adapting your tab bar into a sidebar automatically.** If your app uses a tab-based navigation, you can allow the tab bar to adapt into a sidebar depending on the context by using the following APIs:

**SwiftUI:**
- `sidebarAdaptable`

**Consider using split views to build sidebar layouts with an inspector panel.** Split views are optimized to create a consistent and familiar experience for sidebar and inspector layouts across platforms. You can use the following standard system APIs for split views to build these types of layouts with minimal code:

**SwiftUI:**
- `NavigationSplitView`
- `inspector(isPresented:content:)`

**Check content safe areas for sidebars and inspectors.** If you have these types of components in your app's navigation structure, audit the safe area compatibility of content next to the sidebar and inspector to help make sure underlying content is peeking through appropriately.

**Extend content beneath sidebars and inspectors.** A background extension effect creates a sense of extending a background under a sidebar or inspector, without actually scrolling or placing content under it. A background extension effect mirrors the adjacent content to give the impression of stretching it under the sidebar, and applies a blur to maintain legibility of the sidebar or inspector. This effect is perfect for creating a full, edge-to-edge content experience in apps that use split views, such as for hero images on product pages.

**SwiftUI API:**
- `backgroundExtensionEffect()`

**Choose whether to automatically minimize your tab bar in iOS.** Tab bars can help elevate the underlying content by receding when a person scrolls up or down. You can opt into this behavior and configure the tab bar to minimize when a person scrolls down or up. The tab bar expands when a person scrolls in the opposite direction.

**SwiftUI:**
```swift
TabView {
    // ...
}
.tabBarMinimizeBehavior(.onScrollDown)
```

---

### Menus and Toolbars

Menus have a refreshed look across platforms. They adopt Liquid Glass, and menu items for common actions use icons to help people quickly scan and identify those actions. New to iPadOS, apps also have a menu bar for faster access to common commands.

**Adopt standard icons in menu items.** For menu items that perform standard actions like Cut, Copy, and Paste, the system uses the menu item's selector to determine which icon to apply. To adopt icons in those menu items with minimal code, make sure to use standard selectors.

**Match top menu actions to swipe actions.** For consistency and predictability, make sure the actions you surface at the top of your contextual menu match the swipe actions you provide for the same item.

Toolbars take on a Liquid Glass appearance, and provide a grouping mechanism for toolbar items, letting you choose which actions to display together.

**Determine which toolbar items to group together.** Group items that perform similar actions or affect the same part of the interface, and maintain consistent groupings and placement across platforms.

You can create a fixed spacer to separate items that share a background using these APIs:

**SwiftUI:**
- `fixed`
- `ToolbarSpacer`

**Find icons to represent common actions.** Consider representing common actions in toolbars with standard icons instead of text. This approach helps declutter the interface and increase the ease of use for common actions. For consistency, don't mix text and icons across items that share a background.

**Provide an accessibility label for every icon.** Regardless of what you show in the interface, always specify an accessibility label for each icon. This way, people who prefer a text label can opt into this information by turning on accessibility features like VoiceOver or Voice Control.

**Audit toolbar customizations.** Review anything custom you do to display items in your toolbars, like your use of fixed spacers or custom items, as these can appear inconsistent with system behavior.

**Check how you hide toolbar items.** If you see an empty toolbar item without any content, your app might be hiding the view in the toolbar item instead of the item itself. Instead, hide the entire toolbar item, using these APIs:

**SwiftUI:**
- `hidden(_:)`

---

### Windows and Modals

Windows adopt rounder corners to fit controls and navigation elements. In iPadOS, apps show window controls and support continuous window resizing. Instead of transitioning between specific preset sizes, windows resize fluidly down to a minimum size.

**Support arbitrary window sizes.** Allow people to resize their window to the width and height that works for them, and adjust your content accordingly.

**Use split views to allow fluid resizing of columns.** To support continuous window resizing, split views automatically reflow content for every size using beautiful, fluid transitions. Make sure to use standard system APIs for split views to get these animations with minimal code:

**SwiftUI:**
- `NavigationSplitView`

**Use layout guides and safe areas.** Make sure you specify safe areas for your content so the system can automatically adjust the window controls and title bar in relation to your content.

Modal views like sheets and action sheets adopt Liquid Glass. Sheets feature an increased corner radius, and half sheets are inset from the edge of the display to allow content to peek through from beneath them. When a half sheet expands to full height, it transitions to a more opaque appearance to help maintain focus on the task.

**Check the content around the edges of sheets.** Inside the sheet, check for content and controls that might appear too close to rounder sheet corners. Outside the sheet, check that any content peeking through between the inset sheet and display edge looks as you expect.

**Audit the backgrounds of sheets and popovers.** Check whether you add a visual effect view to your popover's content view, and remove those custom background views to provide a consistent experience with other sheets across the system.

An action sheet originates from the element that initiates the action, instead of from the bottom edge of the display. When active, an action sheet also lets people interact with other parts of the interface.

**Specify the source of an action sheet.** Position an action sheet's anchor next to the control it originates from. Make sure to set the source view or item to indicate where to originate the action sheet and create the inline appearance.

**SwiftUI:**
- `confirmationDialog(_:isPresented:titleVisibility:presenting:actions:)`

---

### Organization and Layout

Style updates to list-based layouts help you organize and showcase your content so it can shine through the Liquid Glass layer. To give content room to breathe, organizational components like lists, tables, and forms have a larger row height and padding. Sections have an increased corner radius to match the curvature of controls across the system.

**Check capitalization in section headers.** Lists, tables, and forms optimize for legibility by adopting title-style capitalization for section headers. This means section headers no longer render entirely in capital letters regardless of the capitalization you provide. Make sure to update your section headers to title-style capitalization to match your app's text to this systemwide convention.

**Adopt forms to take advantage of layout metrics across platform.** Use SwiftUI forms with the grouped form style to automatically update your form layouts.

---

### Search

Platform conventions for location and behavior of search optimize the experience for each device and use case. To provide an engaging search experience in your app, review these search design conventions.

**Check the keyboard layout when activating your search interface.** In iOS, when a person taps a search field to give it focus, it slides upwards as the keyboard appears. Test this experience in your app to make sure the search field moves consistently with other apps and system experiences.

**Use semantic search tabs.** If your app's search appears as part of a tab bar, make sure to use the standard system APIs for indicating which tab is the search tab. The system automatically separates the search tab from other tabs and places it at the trailing end to make your search experience consistent with other apps and help people find content faster.

**SwiftUI:**
```swift
Tab(role: .search) {
    // ...
}
```

---

### Platform Considerations

Liquid Glass can have a distinct appearance and behavior across different platforms, contexts, and input methods. Test your app across devices to understand how the material looks and feels across platforms.

**In watchOS, adopt standard button styles and toolbar APIs.** Liquid Glass changes are minimal in watchOS, so they appear automatically when you open your app on the latest release even if you don't build against the latest SDK. However, to make sure your app picks up this appearance, adopt standard toolbar APIs and button styles from watchOS 10.

**In tvOS, adopt standard focus APIs.** Across apps and system experiences in tvOS, standard buttons and controls take on a Liquid Glass appearance when focus moves to them. For consistency with the system experience, consider applying these effects to custom controls in your app when they gain focus by adopting the standard focus APIs. Apple TV 4K (2nd generation) and newer models support Liquid Glass effects. On older devices, your app maintains its current appearance.

**SwiftUI:**
- `focusable(_:)`
- `isFocused`

**Combine custom Liquid Glass effects to improve rendering performance.** If you apply these effects to custom elements, make sure to combine them using a `GlassEffectContainer`, which helps optimize performance while fluidly morphing Liquid Glass shapes into each other.

**Performance test your app across platforms.** It's a good idea to regularly assess and improve your app's performance, and building your app with the latest SDKs provides an opportunity to check in. Profile your app to gather information about its current performance and find any opportunities for improving the user experience.

**To update and ship your app with the latest SDKs while keeping your app as it looks when built against previous versions of the SDKs, you can add the `UIDesignRequiresCompatibility` key to your project's Info pane.**

---

## 2. Applying Liquid Glass to Custom Views

**Source:** https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views

### Overview

Interfaces across Apple platforms feature a new dynamic material called Liquid Glass, which combines the optical properties of glass with a sense of fluidity. Liquid Glass is a material that blurs content behind it, reflects color and light of surrounding content, and reacts to touch and pointer interactions in real time. Standard components in SwiftUI use Liquid Glass. Adopt Liquid Glass on custom components to move, combine, and morph them into one another with unique animations and transitions.

### Apply and Configure Liquid Glass Effects

Use the `glassEffect(_:in:)` modifier to add Liquid Glass effects to a view. By default, the modifier uses the regular variant of Glass and applies the given effect within a Capsule shape behind the view's content.

Configure the effect to customize your components in a variety of ways:

- Use different shapes to have a consistent look and feel across custom components in your app. For example, use a rounded rectangle if you're applying the effect to larger components that would look odd as a Capsule or Circle.
- Assign a tint color to suggest prominence.
- Add `interactive(_:)` to custom components to make them react to touch and pointer interactions. This applies the same responsive and fluid reactions that glass provides to standard buttons.

**Examples:**

```swift
// Basic glass effect
Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect()

// Custom shape with corner radius
Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect(in: .rect(cornerRadius: 16.0))

// Tinted and interactive glass
Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect(.regular.tint(.orange).interactive())
```

---

### Combine Multiple Views with Liquid Glass Containers

Use `GlassEffectContainer` when applying Liquid Glass effects on multiple views to achieve the best rendering performance. A container also allows views with Liquid Glass effects to blend their shapes together and to morph in and out of each other during transitions. Inside a container, each view with the `glassEffect(_:in:)` modifier renders with the effects behind it.

Customize the spacing on the container to control how the Liquid Glass effects behind views interact with one another. The larger the spacing value on the container, the sooner the Liquid Glass effects behind views blend together and merge the shapes during a transition. A spacing value on the container that's larger than the spacing of an interior HStack, VStack, or other layout container causes Liquid Glass effects to blend together at rest because the views are too close to each other. Animating views in or out causes the shapes to morph apart or together as the space in the container changes.

The `glassEffect(_:in:)` modifier captures the content to send to the container to render. Apply the `glassEffect(_:in:)` modifier after other modifiers that affect the appearance of the view.

**Example:**

```swift
GlassEffectContainer(spacing: 40.0) {
    HStack(spacing: 40.0) {
        Image(systemName: "scribble.variable")
            .frame(width: 80.0, height: 80.0)
            .font(.system(size: 36))
            .glassEffect()

        Image(systemName: "eraser.fill")
            .frame(width: 80.0, height: 80.0)
            .font(.system(size: 36))
            .glassEffect()
            .offset(x: -40.0, y: 0.0)
    }
}
```

In some cases, you want the geometries of multiple views to contribute to a single Liquid Glass effect capsule, even when your content is at rest. Use the `glassEffectUnion(id:namespace:)` modifier to specify that a view contributes to a unified effect with a particular ID. This combines all effects with a similar shape, Liquid Glass effect, and ID into a single shape with the applied Liquid Glass material. This is especially useful when creating views dynamically, or with views that live outside of a layout container, like an HStack or VStack.

**Example with unions:**

```swift
let symbolSet: [String] = ["cloud.bolt.rain.fill", "sun.rain.fill", "moon.stars.fill", "moon.fill"]

GlassEffectContainer(spacing: 20.0) {
    HStack(spacing: 20.0) {
        ForEach(symbolSet.indices, id: \.self) { item in
            Image(systemName: symbolSet[item])
                .frame(width: 80.0, height: 80.0)
                .font(.system(size: 36))
                .glassEffect()
                .glassEffectUnion(id: item < 2 ? "1" : "2", namespace: namespace)
        }
    }
}
```

---

### Morph Liquid Glass Effects During Transitions

Morphing effects occur during transitions or animations between views with Liquid Glass effects. Coordinate transitions between views with effects in a container by using the `glassEffectID(_:in:)` modifier. `GlassEffectTransition` allows you to specify the type of transition to use when you want to add or remove effects within a container. For effects you want to add or remove that are positioned within the container's assigned spacing, the default transition type is `matchedGeometry`.

If you prefer to have a simpler transition or to create a custom transition, use the `materialize` transition and `withAnimation(_:_:)`. Use the `materialize` transition for effects you want to add or remove that are farther from each other than the container's assigned spacing. To provide people with a consistent experience, use `matchedGeometry` and `materialize` transitions across your apps. The system applies more than opacity changes with the available transition types.

Associate each Liquid Glass effect with a unique identifier within a namespace that the `Namespace` property wrapper provides. These IDs ensure SwiftUI animates the same shapes correctly when a shape appears or disappears due to view hierarchy changes. SwiftUI uses the spacing provided to the effect container along with the geometry of the shapes themselves to determine when and which appropriate shapes to morph into and out of.

The `glassEffectID(_:in:)` and `glassEffectTransition(_:)` modifiers only affect their content during view hierarchy transitions or animations.

**Example with morphing:**

```swift
@State private var isExpanded: Bool = false
@Namespace private var namespace

var body: some View {
    GlassEffectContainer(spacing: 40.0) {
        HStack(spacing: 40.0) {
            Image(systemName: "scribble.variable")
                .frame(width: 80.0, height: 80.0)
                .font(.system(size: 36))
                .glassEffect()
                .glassEffectID("pencil", in: namespace)

            if isExpanded {
                Image(systemName: "eraser.fill")
                    .frame(width: 80.0, height: 80.0)
                    .font(.system(size: 36))
                    .glassEffect()
                    .glassEffectID("eraser", in: namespace)
            }
        }
    }

    Button("Toggle") {
        withAnimation {
            isExpanded.toggle()
        }
    }
    .buttonStyle(.glass)
}
```

---

### Optimize Performance When Using Liquid Glass Effects

Creating too many Liquid Glass effect containers and applying too many effects to views outside of containers can degrade performance. Limit the use of Liquid Glass effects onscreen at the same time. Additionally, optimize how your app spends rendering time as people use it. To learn how to improve the performance of your UI, see "Explore UI animation hitches and the render loop" and "Optimize SwiftUI performance with Instruments".

---

### See Also

**Styling views with Liquid Glass:**
- [Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass)

**SwiftUI APIs:**
- `func glassEffect(Glass, in: some Shape) -> some View` - Applies the Liquid Glass effect to a view
- `func interactive(Bool) -> Glass` - Returns a copy of the structure configured to be interactive
- `struct GlassEffectContainer` - A view that combines multiple Liquid Glass shapes into a single shape that can morph individual shapes into one another
- `struct GlassEffectTransition` - A structure that describes changes to apply when a glass effect is added or removed from the view hierarchy
- `struct GlassButtonStyle` - A button style that applies glass border artwork based on the button's context
- `struct GlassProminentButtonStyle` - A button style that applies prominent glass border artwork based on the button's context
- `struct DefaultGlassEffectShape` - The default shape applied by glass effects, a capsule

---

## 3. WWDC 2025 Session 323: Meet Liquid Glass

**Source:** https://developer.apple.com/videos/play/wwdc2025/323/

**Video Transcript (Condensed)**

### Introduction

Hi. I'm Franck, an engineer on the SwiftUI team. And in this video, you will learn how to build a great app with the new design.

iOS 26 and macOS Tahoe introduce significant updates to the look and feel of apps and system experiences. At the heart of these updates is a brand new, adaptive material for controls and navigational elements that we call Liquid Glass.

It takes inspiration from the optical properties of glass and the fluidity of liquid to create a lightweight, dynamic material that helps elevate the underlying content across various components.

### Key Features

As you scroll through content, the glass automatically adapts to the content underneath, changing from light to dark.

With a new and refreshed look across all platforms, controls come alive during interaction. Controls like toggles, segmented pickers, and sliders now transform into liquid glass during interaction, creating a delightful experience!

These updates apply across all the platforms that your app runs on.

### App Structure

App structure refers to the family of APIs that define how people navigate your app. These include views and modifiers like NavigationSplitView, TabView and Sheets! Every one of these members is refined for the new design.

NavigationSplitView allows navigating through a well-defined hierarchy of possibly many root categories. They now have a Liquid Glass sidebar that floats above your content.

With the new `backgroundExtensionEffect` modifier, views can extend outside the safe area, without clipping their content. The image is mirrored and blurred outside of the safe area, extending the artwork while leaving all its content visible.

The new design makes inspectors shine, with more Liquid Glass! Opposite the sidebar in Landmarks, the inspector hosts content with a more subtle layering.

### TabView Updates

TabViews provide persistent, top-level navigation. With the new design, the tab bar on iPhone floats above the content, and can be configured to minimize on scroll. This lets your app's content remain the star of the show.

To adopt this behavior, use the `tabBarMinimizeBehavior` modifier. With this configuration, the tab bar re-expands when scrolling in the opposite direction.

Now, suppose your app has additional controls that you want close at hand, like this playback view in Music. Place a view above the bar with the `tabViewBottomAccessory` modifier. This takes advantage of the extra space provided by the tab bar's collapsing behavior.

Inside your accessory view, read the `tabViewBottomAccessoryPlacement` from the environment. Then, adjust the content of your accessory when it collapses into the tab bar area.

### Sheets

When creating a collection of landmarks, a sheet of landmark options gets presented. On iOS 26, partial height sheets are inset by default with a Liquid Glass background.

At smaller heights, the bottom edges pull in, nesting in the curved edges of the display. When transitioning to a full height sheet, the glass background gradually transitions, becoming opaque and anchoring to the edge of the screen.

If you've used the `presentationBackground` modifier to apply a custom background to your sheets, consider removing that and let the new material shine.

Sheets can also directly morph out of buttons that present them. To have the presentation content morph out of the source view, make the presenting toolbar item a source for a navigation zoom transition. And mark the content of your sheet as the destination of the transition.

### Toolbars

In the new design, toolbar items are placed on a Liquid Glass surface that floats above your app's content and automatically adapts to what's beneath it.

Toolbar items are automatically grouped. I used the new `ToolbarSpacer` API with fixed spacings to split them into their own group. This provides visual clarity that the grouped actions are related, while the separated actions, like the share link and inspector, have distinct behavior.

`ToolbarSpacer` can also be used to create a flexible space that expands between toolbar items.

Some toolbar items can do without this visual grouping, like this item from Books showing my avatar. Apply the `sharedBackgroundVisibility` modifier to separate an item into its own group without a background.

### Toolbar Badges

I added a feature that allows friends to react to my landmarks collection. I would like to add an indicator on my notification item when there is a new reaction.

By using the `badge` modifier on toolbar items, that sweet validation is just one line of code away! I applied the `badge` modifier to my toolbar item's content to display this indicator.

### Icon Rendering and Scroll Edge Effect

In addition to grouping and badging items in toolbars, the new design introduces a few other changes. Icons use monochrome rendering in more places, including in toolbars. The monochrome palette reduces visual noise, emphasizes your app's content, and maintains legibility.

You can still tint icons with a `tint` modifier, but use this to convey meaning, like a call to action or next step, but not just for visual effect.

In the new design, an automatic scroll edge effect keeps controls legible. It is a subtle blur and fade effect applied to content under system toolbars. If your app has any extra backgrounds or darkening effects behind the bar items, make sure to remove them, as these will interfere with the effect.

For denser UIs with a lot of floating elements, like in the calendar app, tune the sharpness of the effect on your content with the `scrollEdgeEffectStyle` modifier.

### Search

There are some big updates to two key patterns for search across all platforms.

Search in the toolbar places the field at the bottom of the screen, within easy reach. And on iPad and Mac, it appears in the top-trailing position of the toolbar.

The second pattern is to treat it as a dedicated page in a multi-tab app. For the Landmarks app, I placed the search in the top trailing corner.

When using this placement, you should make as much of your app's content available through search. The search field appears on its own Liquid Glass surface. A tap activates it and shows the keyboard.

To get this variant in Landmarks, I applied the `searchable` modifier on the NavigationSplitView. Declaring the modifier here indicates that search applies to the entire NavigationSplitView, not just one of the columns.

On iPhone, this variant automatically adapts to bring the search field at the bottom of the display.

Depending on device size, number of toolbar buttons, and other factors, the system may choose to minimize the search field into a toolbar button. When I tap on the button, a full-width search field appears above the keyboard.

If you want to explicitly opt-in to the minimized behavior, say because search isn't a main part of your app's experience, use the new `searchToolbarBehavior` modifier.

### Search in Multi-Tab Apps

Searching in multi-tab apps is often done in a dedicated search page. The pattern is used by apps across all our platforms, such as the Health app.

To do this in your app, set a search role on one of your tabs and place a `searchable` modifier on your TabView.

When someone selects this tab, a search field takes the place of the tab bar, and the content of the tab is shown. People can interact with your browsing suggestions, or tap on the search field to bring up the keyboard and continue with specific search terms.

On iPad and Mac, when someone selects the search tab, the search field appears centered above your apps browsing suggestions.

### Controls

The new design creates a strong family resemblance across platforms for controls like buttons, sliders, menus, and more.

Bordered buttons now have a capsule shape by default, harmonious with the curved corners of the new design. Mini, small, and medium size controls on macOS retain a rounded-rectangle shape, which preserves horizontal density.

And the existing `buttonBorderShape` modifier enables you to specify the shape for any size.

Control heights are updated for the new design. Most controls on macOS are slightly taller, providing a little more breathing room around the control label, and enhancing the size of the click targets.

For compatibility with existing high-density layouts, like complex inspectors and popovers, the existing `controlSize` modifier can be applied to a single control or across an entire set of controls.

And for your most important, prominent actions there is now support for extra large sized buttons.

Last but not least, the new `glass` and `glass prominent` button styles bring Liquid Glass to any button in your app.

### Sliders

Sliders have learned a few tricks too. They now support tick marks! The tick marks appear automatically when initializing a slider with a step parameter. You can even manually place individual ticks. Use the ticks closure to specify their location.

Sliders also let you start their track fill at a particular place. This is useful for values that may adjust left or right from a non-leading default value, like selecting faster or slower speed values on playback. Specify the starting point with the `neutralValue` parameter.

### Menus

Menus across platforms have a new design and more consistent layout. Icons are consistently on the leading edge and are now used on macOS too. The same API using Label or standard control initializers now create the same result on both platforms.

### Custom Liquid Glass Elements

Many of our controls have their corners aligned perfectly within their containers, even if the container is your iPhone! This is called corner concentricity.

To build views that automatically maintain concentricity with their container, use the concentric rectangle shape. Pass the `containerConcentric` configuration to the corner parameter of a rectangle and the shape will automatically match its container across different displays and window shapes.

### Custom Badge View with Liquid Glass

To add glass to your custom views, use the `glassEffect` modifier. By default, a glass effect will be applied within a capsule shape behind your content. SwiftUI automatically uses a vibrant text color that adapts to maintain legibility against colorful backgrounds.

Customize the shape of the glass effect by providing a shape to the modifier. For especially important views, use a `tint` modifier.

And just like text within a glass effect, the tint also uses a vibrant color that adapts to the content behind it.

On iOS, for custom controls or for containers with interactive elements, add the `interactive` modifier to the glass effect. Glass reacts to user interaction by scaling, bouncing, and shimmering, matching the effect provided by toolbar buttons and sliders.

### Multiple Glass Elements

To combine multiple glass elements, use the `GlassEffectContainer`. This grouping is essential for visual correctness. The glass material reflects and refracts lights, picking colors from nearby content. This effect is achieved by sampling content from an area larger than itself.

However, glass can not sample other glass, so having nearby glass elements in different containers will result in inconsistent behavior. Using a glass container allows these elements to share their sampling region, providing a consistent visual result.

When expanding badges, you get wonderful fluid morphing! Add these transitions to your own glass container by using the `glassEffectID` modifier.

To configure this, first declare a local namespace. Then, associate the namespace with each of the `glassEffect` elements in your expanded stack of badges and with your toolbar button.

### Conclusion

I hope you enjoyed this quick tour of applying the new design and using Liquid Glass. Now it's your turn! Adopt the new design in your app by building it with Xcode 26.

Audit the flow of your app and identify whether any views need changes, paying special attention to background colors behind sheets and toolbars that you can remove.

Finally, build expressive components with Liquid Glass that truly make your app stand out. I hope you have a brilliant time playing with the new design! Keep on shining!

---

## 4. Landmarks Sample App: Building with Liquid Glass

**Source:** https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass

### Overview

Landmarks is a SwiftUI app that demonstrates how to use the new dynamic and expressive design feature, Liquid Glass. The Landmarks app lets people explore interesting sites around the world. Whether it's a national park near their home or a far-flung location on a different continent, the app provides a way for people to organize and mark their adventures and receive custom activity badges along the way. Landmarks runs on iPad, iPhone, and Mac.

Landmarks uses a NavigationSplitView to organize and navigate to content in the app, and demonstrates several key concepts to optimize the use of Liquid Glass:

- Stretching content behind the sidebar and inspector with the background extension effect
- Extending horizontal scroll views under a sidebar or inspector
- Leveraging the system-provided glass effect in toolbars
- Applying Liquid Glass effects to custom interface elements and animations
- Building a new app icon with Icon Composer

The sample also demonstrates several techniques to use when changing window sizes, and for adding global search.

### Apply a Background Extension Effect

The sample applies a background extension effect to the featured landmark header in the top view, and the main image in the landmark detail view. This effect extends and blurs the image under the sidebar and inspector when they're open, creating a full edge-to-edge experience.

To achieve this effect, the sample creates and configures an Image that extends to both the leading and trailing edges of the containing view, and applies the `backgroundExtensionEffect()` modifier to the image. For the featured image, the sample adds an overlay with a headline and button after the modifier, so that only the image extends under the sidebar and inspector.

**Note:** The sample also extends the image beyond the top safe area, and adds logic to interactively extend the image when you scroll down beyond the view's bounds. While this improves the experience of the image in the app, it isn't required to implement the background extension effect.

### Extend Horizontal Scrolling Under the Sidebar

Within each continent section in LandmarksView, an instance of LandmarkHorizontalListView shows a horizontally scrolling list of landmark views. When open, the landmark views can scroll underneath the sidebar or inspector.

To achieve this effect, the app aligns the scroll views next to the leading and trailing edges of the containing view.

### Refine the Liquid Glass in the Toolbar

In LandmarkDetailView, the sample adds toolbar items for:
- Sharing a landmark
- Adding or removing a landmark from a list of Favorites
- Adding or removing a landmark from Collections
- Showing or hiding the inspector

The system applies Liquid Glass to toolbar items automatically.

The sample also organizes the toolbar into related groups, instead of having all the buttons in one group.

### Display Badges with Liquid Glass

Badges provide people with a visual indicator of the activities they've recorded in the Landmarks app. When a person completes all four activities for a landmark, they earn that landmark's badge. The sample uses custom Liquid Glass elements with badges, and shows how to coordinate animations with Liquid Glass.

To create a custom Liquid Glass badge, Landmarks uses a view with an Image to display a system symbol image for the badge. The badge has a background hexagon Image filled with a custom color. The badge view uses the `glassEffect(_:in:)` modifier to apply Liquid Glass to the badge.

To demonstrate the morphing effect that the system provides with Liquid Glass animations, the sample organizes the badges and the toggle button into a `GlassEffectContainer`, and assigns each badge a unique `glassEffectID(_:in:)`.

### Create the App Icon with Icon Composer

Landmarks includes a dynamic and expressive app icon composed in Icon Composer. You build app icons with four layers that the system uses to produce specular highlights when a person moves their device, so that the icon responds as if light was reflecting off the glass. The Settings app allows people to personalize the icon by selecting light, dark, clear, or tinted variants of your app icon as well.

For more information on creating a new app icon, see "Creating your app icon using Icon Composer".

For design guidance, see Human Interface Guidelines > App icons.

---

## 5. Quick Reference: Key APIs

### Core Liquid Glass APIs

**Apply Glass Effect:**
```swift
.glassEffect(_:in:)  // Apply Liquid Glass to a view
.glassEffect()  // Default capsule shape
.glassEffect(in: .rect(cornerRadius: 16.0))  // Custom shape
.glassEffect(.regular.tint(.orange).interactive())  // Tinted and interactive
```

**Glass Containers:**
```swift
GlassEffectContainer(spacing: 40.0) {
    // Multiple glass elements
}

.glassEffectID("identifier", in: namespace)  // For morphing transitions
.glassEffectUnion(id: "unionID", namespace: namespace)  // Combine shapes
```

**Button Styles:**
```swift
.buttonStyle(.glass)  // Standard glass button
.buttonStyle(.glassProminent)  // Prominent glass button
```

### Navigation

**NavigationSplitView:**
```swift
NavigationSplitView {
    // Sidebar with automatic glass
} detail: {
    // Detail view
}

.backgroundExtensionEffect()  // Extend content under panels
```

**TabView:**
```swift
TabView {
    Tab(role: .search) { /* ... */ }  // Semantic search tab
}
.tabBarMinimizeBehavior(.onScrollDown)  // Minimize on scroll
.tabViewBottomAccessory { /* ... */ }  // Bottom accessory view
```

### Toolbars

**Toolbar Items:**
```swift
.toolbar {
    ToolbarItemGroup(placement: .automatic) {
        // Toolbar items with automatic glass
    }
}

ToolbarSpacer(.fixed(size: 20))  // Fixed spacer
.sharedBackgroundVisibility(.hidden)  // Hide group background
.badge(count)  // Badge indicator
```

### Search

**Searchable:**
```swift
.searchable(text: $searchText, placement: .toolbar)
.searchToolbarBehavior(.minimized)  // Minimize to button
```

### Controls and Styling

**Control Sizing:**
```swift
.controlSize(.extraLarge)  // New extra-large size
```

**Concentric Corners:**
```swift
ConcentricRectangle(cornerConfiguration: .containerConcentric)
```

**Scroll Edge Effect:**
```swift
.safeAreaBar(edge: .top) { /* ... */ }  // Register for scroll edge effect
.scrollEdgeEffectStyle(.sharp)  // Tune effect sharpness
```

### Sliders

**Tick Marks:**
```swift
Slider(value: $value, in: 0...100, step: 10)  // Auto tick marks
Slider(value: $value, in: 0...100) {
    SliderTicks {
        // Custom tick positions
    }
}
```

**Neutral Value:**
```swift
Slider(value: $speed, in: -2...2, neutralValue: 0)  // Center-start fill
```

### Sheets and Modals

**Remove Custom Backgrounds:**
```swift
// ❌ Don't use custom backgrounds
.presentationBackground(.thinMaterial)

// ✅ Let system provide glass
.sheet(isPresented: $showSheet) { /* ... */ }
```

**Navigation Zoom Transition:**
```swift
Button { showSheet = true }
    .navigationZoomTransition(isSourceOf: showSheet) { /* sheet */ }
```

### Accessibility

**Reduce Motion/Transparency:**
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

if reduceMotion {
    // Instant state change
} else {
    withAnimation { /* ... */ }
}
```

### Performance

**Combine Glass Effects:**
```swift
GlassEffectContainer(spacing: 40.0) {
    // Multiple glass elements - optimized rendering
}
```

**Profile Performance:**
- Use Instruments to profile rendering
- Limit number of glass effects on screen
- Combine effects in containers when possible

---

## Additional Resources

### Documentation Links

- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Landmarks Sample Code](https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass)
- [WWDC 2025 Session 323](https://developer.apple.com/videos/play/wwdc2025/323/)

### Design Resources

- [Apple Design Resources](https://developer.apple.com/design/resources/) - Icon grids and templates
- [Human Interface Guidelines - App Icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- Icon Composer (included in Xcode 26 or download separately)

### Related WWDC Sessions

- "Explore UI animation hitches and the render loop"
- "Optimize SwiftUI performance with Instruments"

### Sample Code

- Clone the Landmarks sample app from Apple Developer
- Study system apps: Notes, Reminders, Calendar for Liquid Glass usage

---

**End of Reference Materials**

This document contains all official Apple documentation for Liquid Glass design and implementation. Use alongside the audit report for complete context during implementation planning and code review.
