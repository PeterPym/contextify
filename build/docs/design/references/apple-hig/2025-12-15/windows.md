---
title: Windows
description: A window presents UI views and components in your app or game.
source: https://developer.apple.com/design/human-interface-guidelines/windows
timestamp: 2025-12-15T00:15:29.189Z
---

**Navigation:** [Human Interface Guidelines](/design/human-interface-guidelines)

**article**

# Windows

> A window presents UI views and components in your app or game.



In iPadOS, macOS, and visionOS, windows help define the visual boundaries of app content and separate it from other areas of the system, and enable multitasking workflows both within and between apps. Windows include system-provided interface elements such as frames and window controls that let people open, close, resize, and relocate them.

Conceptually, apps use two types of windows to display content:

- A *primary* window presents the main navigation and content of an app, and actions associated with them.
- An *auxiliary* window presents a specific task or area in an app. Dedicated to one experience, an auxiliary window doesn’t allow navigation to other app areas, and it typically includes a button people use to close it after completing the task.

For guidance laying out content within a window on any platform, see [Layout](/design/human-interface-guidelines/layout); for guidance laying out content in Apple Vision Pro space, see [Spatial layout](/design/human-interface-guidelines/spatial-layout). For developer guidance, see [Windows](/documentation/SwiftUI/Windows).

## Best practices

**Make sure that your windows adapt fluidly to different sizes to support multitasking and multiwindow workflows.** For guidance, see [Layout](/design/human-interface-guidelines/layout) and [Multitasking](/design/human-interface-guidelines/multitasking).

**Choose the right moment to open a new window.** Opening content in a separate window is great for helping people multitask or preserve context. For example, Mail opens a new window whenever someone selects the Compose action, so both the new message and the existing email are visible at the same time. However, opening new windows excessively creates clutter and can make navigating your app more confusing. Avoid opening new windows as default behavior unless it makes sense for your app.

**Consider providing the option to view content in a new window.** While it’s best to avoid opening new windows as default behavior unless it benefits your user experience, it’s also great to give people the flexibility of viewing content in multiple ways. Consider letting people view content in a new window using a command in a [Context menus](/design/human-interface-guidelines/context-menus) or in the [File menu](/design/human-interface-guidelines/the-menu-bar#File-menu). For developer guidance, see [OpenWindowAction](/documentation/SwiftUI/OpenWindowAction).

**Avoid creating custom window UI.** System-provided windows look and behave in a way that people understand and recognize. Avoid making custom window frames or controls, and don’t try to replicate the system-provided appearance. Doing so without perfectly matching the system’s look and behavior can make your app feel broken.

**Use the term *window* in user-facing content.** The system refers to app windows as *windows* regardless of type. Using different terms — including *scene*, which refers to window implementation — is likely to confuse people.

## Platform considerations

*Not supported in iOS, tvOS, or watchOS.*

### iPadOS

Windows present in one of two ways depending on a person’s choice in Multitasking & Gestures settings.

- **Full screen.** App windows fill the entire screen, and people switch between them — or between multiple windows of the same app — using the app switcher.
- **Windowed.** People can freely resize app windows. Multiple windows can be onscreen at once, and people can reposition them and bring them to the front. The system remembers window size and placement even when an app is closed.

**Make sure window controls don’t overlap toolbar items.** When windowed, app windows include window controls at the leading edge of the toolbar. If your app has toolbar buttons at the leading edge, they might be hidden by window controls when they appear. To prevent this, instead of placing buttons directly on the leading edge, move them inward when the window controls appear.

**Consider letting people use a gesture to open content in a new window.** For example, people can use the pinch gesture to expand a Notes item into a new window. For developer guidance, see [collectionView(_:sceneActivationConfigurationForItemAt:point:)](/documentation/UIKit/UICollectionViewDelegate/collectionView(_:sceneActivationConfigurationForItemAt:point:)) (to transition from a collection view item), or [UIWindowScene.ActivationInteraction](/documentation/UIKit/UIWindowScene/ActivationInteraction) (to transition from an item in any other view).

### macOS

In macOS, people typically run several apps at the same time, often viewing windows from multiple apps on one desktop and switching frequently between different windows — moving, resizing, minimizing, and revealing the windows to suit their work style.

To learn about setting up a window to display your game in macOS, see [Managing your game window for Metal in macOS](/documentation/Metal/managing-your-game-window-for-metal-in-macos).

#### macOS window anatomy

A macOS window consists of a frame and a body area. People can move a window by dragging the frame and can often resize the window by dragging its edges.

The *frame* of a window appears above the body area and can include window controls and a  [Toolbars](/design/human-interface-guidelines/toolbars). In rare cases, a window can also display a bottom bar, which is a part of the frame that appears below body content.

#### macOS window states

A macOS window can have one of three states:

- **Main.** The frontmost window that people view is an app’s main window. There can be only one main window per app.
- **Key.** Also called the *active window*, the key window accepts people’s input. There can be only one key window onscreen at a time. Although the front app’s main window is usually the key window, another window — such as a panel floating above the main window — might be key instead. People typically click a window to make it key; when people click an app’s Dock icon to bring all of that app’s windows forward, only the most recently accessed window becomes key.
- **Inactive.** A window that’s not in the foreground is an inactive window.

The system gives main, key, and inactive windows different appearances to help people visually identify them. For example, the key window uses color in the title bar options for closing, minimizing, and zooming; inactive windows and main windows that aren’t key use gray in these options. Also, inactive windows don’t use [Materials](/design/human-interface-guidelines/materials) (an effect that can pull color into a window from the content underneath it), which makes them appear subdued and seem visually farther away than the main and key windows.



**Make sure custom windows use the system-defined appearances.** People rely on the visual differences between windows to help them identify the foreground window and know which window will accept their input. When you use system-provided components, a window’s background and button appearances update automatically when the window changes state; if you use custom implementations, you need to do this work yourself.

**Avoid putting critical information or actions in a bottom bar, because people often relocate a window in a way that hides its bottom edge.** If you must include one, use it only to display a small amount of information directly related to a window’s contents or to a selected item within it. For example, Finder uses a bottom bar (called the status bar) to display the total number of items in a window, the number of selected items, and how much space is available on the disk. A bottom bar is small, so if you have more information to display, consider using an inspector, which typically presents information on the trailing side of a split view.

### visionOS

visionOS defines two main window styles: default and volumetric. Both a default window (called a *window*) and a volumetric window (called a *volume*) can display 2D and 3D content, and people can view multiple windows and volumes at the same time in both the Shared Space and a Full Space.

The system defines the initial position of the first window or volume people open in your app or game. In both the Shared Space and a Full Space, people can move windows and volumes to new locations.

#### visionOS windows

The default window style consists of an upright plane that uses an unmodifiable background [Materials](/design/human-interface-guidelines/materials) called *glass* and includes a close button, window bar, and resize controls that let people close, move, and resize the window. A window can also include a Share button, [Tab bars](/design/human-interface-guidelines/tab-bars), [Toolbars](/design/human-interface-guidelines/toolbars), and one or more [Ornaments](/design/human-interface-guidelines/ornaments). By default, visionOS uses dynamic [Scale](/design/human-interface-guidelines/spatial-layout#Scale) to help a window’s size appear to remain consistent regardless of its proximity to the viewer. For developer guidance, see [DefaultWindowStyle](/documentation/SwiftUI/DefaultWindowStyle).



**Prefer using a window to present a familiar interface and to support familiar tasks.** Help people feel at home in your app by displaying an interface they’re already comfortable with, reserving more [Immersive experiences](/design/human-interface-guidelines/immersive-experiences) for the meaningful content and activities you offer. If you want to showcase bounded 3D content like a game board, consider using a [visionOS volumes](/design/human-interface-guidelines/windows#visionOS-volumes).

**Retain the window’s glass background.** The default glass background helps your content feel like part of people’s surroundings while adapting dynamically to lighting and using specular reflections and shadows to communicate the window’s scale and position. Removing the glass material tends to cause UI elements and text to become less legible and to no longer appear related to each other; using an opaque background obscures people’s surroundings and can make a window feel constricting and heavy.

**Choose an initial window size that minimizes empty areas within it.** By default, a window measures 1280x720 pt. When a window first opens, the system places it about two meters in front of the wearer, giving it an apparent width of about three meters. Too much empty space inside a window can make it look unnecessarily large while also obscuring other content in people’s space.

**Aim for an initial shape that suits a window’s content.** For example, a default Keynote window is wide because slides are wide, whereas a default Safari window is tall because most webpages are much longer than they are wide. For games, a tower-building game is likely to open in a taller window than a driving game.

**Choose a minimum and maximum size for each window to help keep your content looking great.** People appreciate being able to resize windows as they customize their space, but you need to make sure your layout adjusts well across all sizes. If you don’t set a minimum and maximum size for a window, people could make it so small that UI elements overlap or so large that your app or game becomes unusable. For developer guidance, see [Positioning and sizing windows](/documentation/visionOS/positioning-and-sizing-windows).



**Minimize the depth of 3D content you display in a window.** The system adds highlights and shadows to the views and controls within a window, giving them the appearance of [Depth](/design/human-interface-guidelines/spatial-layout#Depth) and helping them feel more substantial, especially when people view the window from an angle. Although you can display 3D content in a window, the system clips it if the content extends too far from the window’s surface. To display 3D content that has greater depth, use a volume.

#### visionOS volumes

You can use a volume to display 2D or 3D content that people can view from any angle. A volume includes window-management controls just like a window, but unlike in a window, a volume’s close button and window bar shift position to face the viewer as they move around the volume. For developer guidance, see [VolumetricWindowStyle](/documentation/SwiftUI/VolumetricWindowStyle).



**Prefer using a volume to display rich, 3D content.** In contrast, if you want to present a familiar, UI-centric interface, it generally works best to use a [visionOS windows](/design/human-interface-guidelines/windows#visionOS-windows).

**Place 2D content so it looks good from multiple angles.** Because a person’s perspective changes as they move around a volume, the location of 2D content within it might appear to change in ways that don’t make sense. To pin 2D content to specific areas of 3D content inside a volume, you can use an attachment.

**In general, use dynamic scaling.** Dynamic scaling helps a volume’s content remain comfortably legible and easy to interact with, even when it’s far away from the viewer. On the other hand, if you want a volume’s content to represent a real-world object, like a product in a retail app, you can use fixed scaling (this is the default).

**Take advantage of the default baseplate appearance to help people discern the edges of a volume.** In visionOS 2 and later, the system automatically makes a volume’s horizontal “floor,” or *baseplate*, visible by displaying a gentle glow around its border when people look at it. If your content doesn’t fill the volume, the system-provided glow can help people become aware of the volume’s edges, which can be particularly useful in keeping the resize control easy to find. On the other hand, if your content is full bleed or fills the volume’s bounds — or if you display a custom baseplate appearance — you may not want the default glow.

**Consider offering high-value content in an ornament.** In visionOS 2 and later, a volume can include an ornament in addition to a toolbar and tab bar. You can use an ornament to reduce clutter in a volume and elevate important views or controls. When you use an attachment anchor to specify the ornament’s location, such as `topBack` or `bottomFront`, the ornament remains in the same position, relative to the viewer’s perspective, as they move around the volume. Be sure to avoid placing an ornament on the same edge as a toolbar or tab bar, and prefer creating only one additional ornament to avoid overshadowing the important content in your volume. For developer guidance, see [ornament(visibility:attachmentAnchor:contentAlignment:ornament:)](/documentation/SwiftUI/View/ornament(visibility:attachmentAnchor:contentAlignment:ornament:)).

**Choose an alignment that supports the way people interact with your volume.** As people move a volume, the baseplate can remain parallel to the floor of a person’s surroundings, or it can tilt to match the angle at which a person is looking. In general, a volume that remains parallel to the floor works well for content that people don’t interact with much, whereas a volume that tilts to match where a person is looking can keep content comfortably usable, even when the viewer is reclining.

## Resources

#### Related

[Layout](/design/human-interface-guidelines/layout)

[Split views](/design/human-interface-guidelines/split-views)

[Multitasking](/design/human-interface-guidelines/multitasking)

#### Developer documentation

[Windows](/documentation/SwiftUI/Windows) — SwiftUI

[WindowGroup](/documentation/SwiftUI/WindowGroup) — SwiftUI

[UIWindow](/documentation/UIKit/UIWindow) — UIKit

[NSWindow](/documentation/AppKit/NSWindow) — AppKit

#### Videos

- [Elevate the design of your iPad app](https://developer.apple.com/videos/play/wwdc2025/208) - Make your app look and feel great on iPadOS. Learn best practices for designing a responsive layout for resizable app windows. Get familiar with window controls and explore the best ways to accommodate them. Discover the building blocks of a great menu bar. And meet the new pointer and its updated effects.

## Change log

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All Human Interface Guidelines belong to Apple Inc.*
