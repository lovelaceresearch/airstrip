# Airstrip Design System & Aesthetics

Airstrip is designed to look premium, modern, and native to macOS. It heavily integrates Apple’s signature design guidelines and transitions from macOS 26.0+ (specifically Liquid Glass), while retaining graceful material fallbacks on older operating systems.

---

## 1. Liquid Glass Panel & Capsule UI

The main containers and buttons in Airstrip leverage custom modifiers defined in [LiquidGlassUI.swift](file:///Users/chanwoo/Documents/xcode/airstrip/Sources/Airstrip/UI/LiquidGlassUI.swift):

- **airstripGlassPanel**: Applies a system `.glassEffect` in a continuous rounded rectangle on macOS 26.0+. For older systems, it falls back to a clean `.regularMaterial` background combined with a subtle tint layer and an elegant `.strokeBorder` separator.
- **airstripGlassCapsule**: Wraps controls in glass capsules, automatically disabling double-layer background highlights in native toolbars (via the `isToolbarItem` parameter).
- **airstripGlassButton**: Installs prominent or regular glass button styles.

---

## 2. Palette & Visual Styles

Airstrip uses a curated color scheme rather than generic primaries:
- **Soft Indicators**: Status colors for running servers use custom tints (like green and orange) with low opacity borders rather than full-strength fills.
- **Stable Per-Project Gradients**: Project badges and tiles use `ProjectTint` which maps the project name deterministically to a color pair (e.g. teal/blue, indigo/purple, orange/pink), keeping visuals stable across launches.
- **Softening Saturation**: Entire views are softened via a saturation modifier using the visual settings slider strength to keep the interface easy on the eyes.

---

## 3. Toolbars & Dynamic Tabs

### Customizable Toolbars
Using macOS's new toolbar APIs, Airstrip supports customizable items which users can personalize by dragging and rearranging. Custom controls are wrapped in:
- `ToolbarNavigationCluster`
- `ToolbarActionCluster`
- **Expanding Search Field**: Leveraging an asymmetric transition (`.move(edge: .trailing).combined(with: .opacity)` on insertion, and `.opacity` on removal) combined with a container-level spring animation (`.spring(response: 0.3, dampingFraction: 0.82)`) to animate the capsule size changes smoothly on click toggle. When inactive, it collapses into a perfect `34x34` circular capsule.
- **Unified Toolbar Sizing**: All custom toolbar capsules share an identical height of `34` points. Combined with button frames of `28` points, this leaves a balanced `3` points of top/bottom visual cushioning, providing a spacious and cohesive look across the entire toolbar.

### Dynamic Tab Sizing
The Principal tab bar container [ContentView.swift](file:///Users/chanwoo/Documents/xcode/airstrip/Sources/Airstrip/App/ContentView.swift#L124) automatically scales open workspace tabs:
- Enforces a maximum area width of `480px` to prevent collisions.
- Sizes individual tab chips dynamically based on the total count: `usableWidth = maxAreaWidth - padding - spacing`.
- Truncates text gracefully using `Spacer(minLength: 0)` and `.lineLimit(1)`, preserving close buttons and icons.
- When empty, it falls back to exactly `136px` displaying a clean, centered placeholder state ("No Open Windows").

---

## 4. Sidebar & Bottom-Fixed Settings

The left status sidebar [Dashboard.swift](file:///Users/chanwoo/Documents/xcode/airstrip/Sources/Airstrip/Features/Dashboard/Dashboard.swift) uses a vertical split layout:
- **Scrollable Area**: Displays active ports, running servers/apps, tools, and developer helper utilities (Activity log card was removed to declutter).
- **Bottom-Fixed Panel**: Features a glass-styled settings gear button that is always pinned to the bottom. Clicking this button presents a sheet with API keys setup for Cloud AI models (Mistral, OpenAI, Gemini, Claude) to use in the AI Studio.

---

## 5. Full-Area Hit Testing

To ensure that interactions feel tactile and responsive:
- **Tab Chips**: Built with a layered `ZStack` where a full-width select button spans the entire width of the tab chip, and the close button is layered on top. Clicking anywhere on the chip background selects the tab, while clicking the small close icon closes it.
- **Springboard Tiles**: Apply `.contentShape(Rectangle())` directly after drawing the glass panel and before `.onHover` or gestures, so that double-clicking or hovering on the translucent background registers reliably.

---

## 6. Web View & Native Downloads

Airstrip hosts web-based applications (like visualization tools, React frontends, etc.) using `WKWebView` in [ProjectConsole.swift](file:///Users/chanwoo/Documents/xcode/airstrip/Sources/Airstrip/Features/Console/ProjectConsole.swift).
- **WKDownloadDelegate Conformance**: Intercepts download commands (such as clicking download links for PNG, CSV, or blob data) by conforming the coordinator to `WKDownloadDelegate`.
- **NSSavePanel Integration**: Automatically triggers a native macOS `NSSavePanel` dialog when a download is requested, giving users full control over the local target folder and filename.
- **Sidebar Download Manager**: Shows a `DownloadsCard` inside the left `StatusSidebar` in [Dashboard.swift](file:///Users/chanwoo/Documents/xcode/airstrip/Sources/Airstrip/Features/Dashboard/Dashboard.swift) that reads progress updates reactively from `ProjectStore`. It displays a file extension icon, live linear progress bar, error state, and features a "Show in Finder" folder action button for completed downloads. The card automatically hides itself when the download list is empty.
