# HarmonyOS bookshelf issues #65 and #67 — 2026-11-01

## Environment and scope

- Local DevEco `Modu_API26`, HarmonyOS 7.0.0 / API 26, image 7.0.0.107, arm64, 1280×2832, 560 dpi.
- Upgraded the existing emulator installation from 1.3.1 to the published 1.3.5+10167 HAP without clearing data.
- Earlier “local tests” were Flutter widget tests on the Mac, not HarmonyOS acceptance.
- Reports #65 and #67 are by @zggnice. No issue comment, closure, commit, push or release is part of this verification.

## #65: reproduced in published 1.3.5

Created a temporary six-book group using the emulator's four existing test entries and two generated EPUB fixtures. The folder displayed four full cards and only the tops of the last row. Upward swipes at both 1500 and 500 px/s returned to the initial position; the last row remained clipped by the action area.

Flutter OH's `AlertDialog` uses `scrollable ?? (theme.platform == TargetPlatform.ohos)`. Its default outer `SingleChildScrollView` gives the inner shrink-wrapped grid unbounded height. The grid's default always-scrollable physics consumes the gesture even though its own content extent is zero. Standard Flutter's default does not add that outer view, explaining why the Mac widget test passed.

Set `scrollable: false` on `BookOpenedFolder`'s dialog so its `Flexible` content constrains the grid. This preserves the existing behavior on other platforms and the grid's own scroll/selection/drag behavior.

Regression coverage: six cards, swipe then settle, last card fully visible and hit-testable; explicit `scrollable: false`; existing batch selection and drag/drop tests.

## #67: source fix, device acceptance pending

The reported line is `Prefs.bookCoverWidth`, which previously cast the stored preference to `double`. A cached integer reproduces the TypeError. The shared getter now accepts finite `num`, converts to double and clamps to the slider's 80–260 range; invalid values use 120. No data reset or preference migration is required.

Nine preference cases cover absent, integer, fractional, out-of-range, wrong-type and non-finite values. Together with bookshelf interaction tests: 23 passed. Targeted static analysis passed.

The updated complete Modu HAP has not been built or installed. #67 is not yet confirmed on a fixed HarmonyOS package or the reporter's physical device.

## Native simulator before/after probe

Built and installed a separate, unsigned diagnostic HAP (`com.modu.diagnostics.folder_probe`) on the same API 26 emulator. It uses the same Flutter OH SDK, the project's `AppScrollBehavior`, six grid cells, shrink wrapping and default grid physics, with only the dialog's outer `scrollable` choice varied.

- Before (`scrollable: null`, OHOS default): after the upward swipe, cells 5/6 remain at y=2345–2426, only 81 px visible; the list returns to its initial position.
- Fixed (`scrollable: false`): after the same swipe and settling, cells 5/6 occupy y=1447–2356, their full 909 px height. Reverse swipe restores the first row normally.
- Earlier probe iterations added an explicit grid controller/physics and thus did not preserve the production gesture behavior; they are not the comparison above.
- This verifies the layout fix on the real HarmonyOS runtime, but is not a rebuilt full Modu package acceptance test.

Private evidence: `/private/tmp/modu-folder-before.png`, `modu-folder-after.png`, `modu-probe-before-layout.json`, `modu-probe-fixed-settled.json`, `modu-probe-fixed.png`; diagnostic source `/private/tmp/modu-folder-probe/lib/main.dart`.

Cleanup: dissolved the temporary group, removed the two newly imported synthetic books through the app, and uninstalled the independent probe. Existing books and reading progress were retained. The emulator now has published Modu 1.3.5, not the pending fixed package.
