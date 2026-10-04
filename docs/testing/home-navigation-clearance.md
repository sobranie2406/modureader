# Home bottom-navigation clearance

> Historical record of the source checks described below; the previously generated Preview3 package did not include these changes. No full version number was specified here; this is not certification of the latest 1.2.0 release. See the [documentation index](../README.md).

## Changes

- Compact layouts consistently used `HomeNavigationBody` to reserve space outside page content for the bottom bar's height, floating offset, system safe area and a 12 dp gap. Lists, grids, empty states and fixed action areas were protected.
- Bookshelf, remote library, statistics and notes no longer used fixed 80/96 dp navigation compensation, retaining only normal content spacing and unconsumed system safe areas. Settings did not compensate for the bottom bar twice.
- Navigation-bar height grew with system text scaling; content used the same height calculation.
- Auto-hide retained clearance to avoid viewport changes during scrolling or obstructed controls when the bar reappeared. When the keyboard appeared, the bottom bar and return-to-top icon were hidden; Scaffold handled keyboard insets without rebuilding input content.
- Wide-screen side navigation reserved no bottom-bar space. Standalone pages and AI popout panels were unaffected by home bottom-navigation compensation.

## Automation

`flutter test --no-pub test/widgets/home_navigation_body_test.dart test/widgets/settings_bottom_navigation_test.dart test/platform/settings_navigation_test.dart`

42 passed. Coverage included grids, lists, fixed buttons, 0/24/48 dp system safe areas, 1.0/1.6/2.0 text scaling, keyboard opening/closing, auto-hide/restoration, sidebar layouts, and display/tapping of the real settings page's final item. Data tests used component fixtures without accessing personal libraries or WebDAV.

No package was rebuilt and no Android/macOS device interaction was verified in this round. The previously generated Preview3 package did not include these changes.
