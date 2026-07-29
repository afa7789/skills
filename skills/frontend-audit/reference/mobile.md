# Mobile & native adapter — React Native / Expo / Flutter / Compose / SwiftUI

There is no single Storybook for mobile, so this adapter uses **two layers per
platform**, exactly like web:

- **State isolation layer** — the platform's own catalog/preview mechanism, which
  renders one screen in one state with fake data.
- **Real-device layer** — the built app on an emulator/simulator, driven through
  the accessibility tree. **Maestro** is the one tool that covers Android, iOS,
  React Native and Flutter with the same flow files, which makes it the generic
  capture engine for this skill.

| Platform | State isolation | Real-device capture |
|---|---|---|
| React Native / Expo | Storybook for React Native (on-device) or a screen harness | Maestro (or Detox `device.takeScreenshot()`) |
| Flutter | Widgetbook use-cases; golden tests | Maestro; `integration_test` screenshots |
| Android / Compose | `@Preview` + Compose screenshot tests (or Paparazzi/Roborazzi, no device needed) | Maestro; `adb exec-out screencap` |
| iOS / SwiftUI | `#Preview` variants; snapshot tests | Maestro; `xcrun simctl io booted screenshot` |

---

## 1. React Native / Expo

### State isolation

**Option A — Storybook for React Native.** It renders on the device/simulator
with an on-device UI to switch stories. Setup varies by Storybook major version,
so check the installed version and follow its own docs; the shape is always:

```bash
npx storybook@latest init --type react_native
```

- Stories are normal CSF (`*.stories.tsx`) and are auto-required by a generated
  requires file — re-run the generator after adding stories.
- The Storybook entry replaces the app entry behind a flag/env var
  (e.g. `STORYBOOK_ENABLED`) so it stays out of the production bundle.
- Metro needs the Storybook wrapper in `metro.config.js`.

**Option B — a screen harness (lighter, always works).** A debug-only screen that
lists every screen×state from the catalog and pushes it with injected fake
services. Cheaper than Storybook when the app already has DI:

```tsx
// .ux-review/harness/UxHarness.tsx  — registered as a dev-only route
const CASES = [
  { id: 'dashboard__loading', render: () => <ServiceProvider value={loadingFakes}><Dashboard/></ServiceProvider> },
  { id: 'dashboard__empty',   render: () => <ServiceProvider value={emptyFakes}><Dashboard/></ServiceProvider> },
  { id: 'dashboard__error',   render: () => <ServiceProvider value={errorFakes}><Dashboard/></ServiceProvider> },
]
// Deep link: myapp://ux-harness?case=dashboard__loading  → Maestro drives it by id
```

The deep-link-per-case trick is what makes the capture loop a simple `for` over
the catalog instead of a hand-written navigation script per screen.

### Mocking

React Native has no service worker. Intercept at the boundary the app actually
uses: swap the API client / repository via DI or context, or use MSW's native
integration for `fetch`/XHR if the project already has MSW. Do not stub inside
components.

---

## 2. Flutter

### Widgetbook — the state catalog

```yaml
# pubspec.yaml (dev)
dev_dependencies:
  widgetbook_generator: ^3.0.0
  build_runner: ^2.0.0
dependencies:
  widgetbook: ^3.0.0
  widgetbook_annotation: ^3.0.0
```

```dart
@widgetbook.UseCase(name: 'Loading', type: DashboardPage)
Widget dashboardLoading(BuildContext context) => ProviderScope(
  overrides: [itemsRepoProvider.overrideWithValue(LoadingRepo())],
  child: const DashboardPage(),
);
```

Run `dart run build_runner build` to generate the directory, then run the
Widgetbook app on a simulator (or as Flutter web, which lets **Playwright**
capture it exactly like a web catalog — the cheapest path when the design review
only needs pixels).

### Golden tests — deterministic, no device

```dart
await tester.pumpWidget(app);
await expectLater(find.byType(DashboardPage), matchesGoldenFile('goldens/dashboard_default.png'));
// flutter test --update-goldens   to write the baseline
```

Goldens are the fastest before/after comparison in Flutter. Pin the font and
`TestWidgetsFlutterBinding` surface size or the images will differ per machine.

### Built-in accessibility assertions (use these — they are free findings)

```dart
await expectLater(tester, meetsGuideline(textContrastGuideline));
await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
```

### Real-device screenshots

`integration_test` + `convertFlutterSurfaceToImage()` + `binding.takeScreenshot(name)`,
or drive the built app with Maestro (simpler, and identical to the other platforms).

---

## 3. Android / Jetpack Compose

### Previews as the state catalog

```kotlin
@PreviewLightDark
@PreviewFontScale
@PreviewScreenSizes
@Composable
fun DashboardEmptyPreview() = AppTheme { DashboardScreen(state = DashboardState.Empty) }
```

Multipreview annotations give you the light/dark, font-scale and screen-size
matrix for free — that is exactly the audit matrix this skill wants.

### Screenshot tests

- **Compose Screenshot Testing** (AGP plugin, `@PreviewTest`): `updateDebugScreenshotTest`
  writes baselines, `validateDebugScreenshotTest` compares. Still evolving — check
  the AGP version's docs.
- **Paparazzi** or **Roborazzi**: render on the JVM, no emulator, very fast and
  very deterministic. Prefer one of these for CI.

### Accessibility checks

Enable the framework checks in instrumented tests
(`AccessibilityChecks.enable()` for Espresso, or the Compose test rule's
accessibility validation), and run **Accessibility Scanner** on the emulator for
a human-readable pass.

---

## 4. iOS / SwiftUI

```swift
#Preview("Empty") { DashboardView(state: .empty) }
#Preview("Error", traits: .sizeThatFitsLayout) { DashboardView(state: .error) }
```

Previews cover the state matrix during development but are hard to export
programmatically. For repeatable images use snapshot tests
(`swift-snapshot-testing`, asserting against per-device/per-trait references), and
use the simulator for real-device shots.

Accessibility audit: `XCUIApplication().performAccessibilityAudit()` in a UI test
reports contrast, hit-region, clipped-text and missing-label issues — run it per
screen and save the output into `audits/`.

---

## 5. Maestro — the generic capture engine

Maestro drives the built app through the accessibility/view hierarchy, so the same
flow file works for RN, Flutter, Compose and SwiftUI.

```bash
maestro test .ux-review/harness/flows/            # run all flows
maestro studio                                    # interactively find selectors
maestro hierarchy                                 # dump the view tree (great for a11y labels)
```

```yaml
# .ux-review/harness/flows/dashboard.yaml
appId: com.example.app
---
- launchApp:
    clearState: true
    arguments:
      uxCase: "dashboard__empty"      # harness reads this and renders the case
- assertVisible: "Dashboard"
- takeScreenshot: dashboard__empty__phone
- tapOn: "Filters"
- takeScreenshot: dashboard__filters-open__phone
```

Generate one flow per catalog entry from `ui-catalog.yaml` rather than writing
them by hand. `maestro hierarchy` doubles as an accessibility-label audit: any
interactive node without a label is a P0 candidate.

---

## 6. Device-level determinism (do this before capturing anything)

**Android:**
```bash
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb shell "cmd uimode night yes"                       # dark-mode pass
adb shell settings put system font_scale 1.3           # font-scaling pass
adb shell settings put global sysui_demo_allowed 1     # freeze the status bar
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941
adb exec-out screencap -p > shot.png
```

**iOS simulator:**
```bash
xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100
xcrun simctl ui booted appearance dark
xcrun simctl ui booted content_size accessibility-extra-large
xcrun simctl io booted screenshot shot.png
```

**Every platform:**

- [ ] Fixed device/emulator model per viewport entry in the catalog — never "whatever is booted"
- [ ] `clearState: true` on launch so no previous run leaks
- [ ] Fake data injected via DI/deep-link argument; zero real network
- [ ] Fixed clock/locale/timezone; status bar frozen
- [ ] Animations disabled
- [ ] Capture light **and** dark, default **and** largest font scale
- [ ] Note safe areas / notch / dynamic island — they are a real source of P0 clipping

---

## 7. Mobile-specific things the panel must review

Add these to the reviewer prompts; they have no web equivalent and are where
mobile UX most often fails:

- Safe areas, notch/dynamic island, home indicator, rounded-corner clipping
- Keyboard: does it cover the focused input, the submit button, the error text?
- Touch targets ≥ 48×48dp, and spacing between adjacent targets
- Thumb reachability of primary actions on a large phone
- Landscape and tablet/foldable layouts; split screen
- Font scaling to the maximum accessibility size without truncation
- Scroll performance and long-list behaviour; pull-to-refresh feedback
- Offline and slow-network states; retry affordances
- Permission prompts: is there context *before* the OS dialog appears?
- Back-gesture / hardware-back behaviour and unsaved-state loss
- Platform idiom: Material on Android vs HIG on iOS where the product wants it
