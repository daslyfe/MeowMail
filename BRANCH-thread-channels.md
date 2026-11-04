# Branch: thread-channels

Changes on this branch, grouped so each part can be adopted on its own.

1. Followed thread channels
2. Channel and badge changes
3. Restyle
4. Technical notes

## 1. Followed thread channels

Adds a third kind of channel that holds specific threads, shown in a **FOLLOWING** section of the sidebar above **PEOPLE**.

| Action | How |
|---|---|
| Follow a thread in a new channel | Drag the thread from the thread list onto empty space in the sidebar, or right-click the thread → **Give this thread its own channel** |
| Add a thread to an existing followed channel | Drag the thread onto that channel, or right-click the thread → **Add to channel ▸** |
| Remove one thread from a channel | Open the channel, right-click the thread → **Remove from this channel**. Removing the last thread removes the channel. |
| Remove a whole followed channel | Hover the channel and click **×**, or right-click → **Done with this thread** |

- New channels are named after the thread subject with reply prefixes removed: "Re: Fwd: Lisbon in March?" becomes `#lisbon-in-march`.
- Followed threads are kept up to date even after they are archived in Gmail.
- Removing a thread or channel does not change anything in Gmail.
- On iPhone, use the right-click (long-press) menus, since the thread list and sidebar are on separate screens.

## 2. Channel and badge changes

- **Rename any channel:** right-click → **Rename channel…**
- **Opening a channel opens its most recent thread** (macOS). This marks that thread read in Gmail.
- **Inbox badges removed:** the inbox timeline channel has no count badge. The account icon's dot shows only for new mail in people or followed channels.
- **Default inbox channel name** is `all-mail` instead of `threads`. Existing saved names are unchanged.

## 3. Restyle

- Light mode instead of dark.
- Grey backgrounds (#bfbfbf account rail, #d9d9d9 sidebar, #e6e6e6 content), black text, 0.5 pt dashed rules between sections.
- Fonts: Monor Bold for section titles, channel headers and sender names; MXWim Garamond for subjects and message text; Nanum Myeongjo for dates, recipients and snippets; Courier for text inputs.
- Square avatars in pastel colors with black borders. Sender names sit on a pastel underline stroke.
- Count badges are black tags with white text.
- Search, reply and recipient fields are Courier on a dotted underline. **send** and **new** are bevelled silver buttons.
- A pixel-pattern border runs down the right edge of the channel sidebar (`MeowMail/pixel-strip.png`).
- Color rules:
  - Followed and people channels show colored avatars and name strokes, and their names in the sidebar have a colored underline.
  - In the inbox timeline, threads are grey unless they are unread and received mail from someone else since the channel was last opened. Opening a thread turns it grey.
  - Threads that belong to a followed channel stay colored in the inbox timeline.

## 3a. Composer and scrolling

- **Bigger drafting space:** the reply box starts 5 lines tall and grows to 20. In the new email window the body starts 14 lines tall and grows to 40, and the window opens at 640 × 600 or larger and can be resized.
- **Scrolling past HTML emails (macOS):** HTML messages are drawn in a web view sized to the whole message. The web view caught scroll-wheel events, so a long HTML message could trap scrolling and hide the messages below it. Scroll events now pass through to the conversation.

### Fonts

| Font | File | License | In git |
|---|---|---|---|
| Monor Bold | `MeowMail/Fonts/monor-bold.otf` | SIL Open Font License | Yes |
| Nanum Myeongjo | `MeowMail/Fonts/nanumthin.ttf` | SIL Open Font License | Yes |
| MXWim Garamond | `MeowMail/Fonts/MXWimGaramond-*.otf` | Commercial (Maxitype) | No, gitignored |

Fonts are registered at launch from the app bundle. Any font that is missing falls back to the system serif, so the app builds and runs without MXWim.

## 4. Technical notes

- **Data model:** `Channel.Kind` has a new `.thread` case. `Channel` has new optional `threadID` and `threadIDs` fields, read through `followed`. Saved `state.json` files from before this branch still load.
- **Sync:** each sync also downloads followed threads that are not in the inbox, one request per thread, within the existing rate limiting.
- **Thread list rows** are plain views with a tap gesture and button accessibility traits instead of `Button`s. A `Button` on macOS consumes the mouse-down, which prevented dragging.
- **Read status:** opening a channel now opens its newest thread, which marks it read.
- **Tests:** 22 pass, including 5 new tests for thread channels, channel naming, multi-thread channels and decoding older saved state.
- **iPhone:** the iOS target compiles. It has not been run on a device.

## Files changed

| File | Change |
|---|---|
| `Core/Models.swift` | `.thread` channel kind, followed thread IDs, subject-to-channel-name helper |
| `Core/AppStore.swift` | Follow, add, remove and rename actions; open newest thread; badge and color rules; sync of followed threads |
| `Views/Sidebars.swift` | FOLLOWING section, drag and drop, context menus, rename dialog, restyle |
| `Views/ChatView.swift` | Restyle, color rules, bigger reply and new email fields |
| `Views/HTMLMessageView.swift` | Scroll events pass through HTML messages on macOS |
| `Views/RootView.swift` | Open newest thread on channel click, restyle |
| `Views/Theme.swift` | Colors, font loading, pixel strip, dashed rule, silver button, avatars, badges |
| `MeowMailApp.swift` | Light mode |
| `MeowMailTests/CoreTests.swift` | New tests |
| `Fonts/`, `pixel-strip.png`, `.gitignore` | Fonts, sidebar border image, paid font excluded |
