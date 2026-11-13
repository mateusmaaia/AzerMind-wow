# Grimoire finishing pass

Each item is implemented and checked in order. Code checks do not constitute visual approval in WoW.

- [x] 1. Scrolls: bronze channel, bounded buttons, readable thumb.
- [x] 2. Message actions: direct image textures on the buttons, retaining hover/pressed/disabled feedback. The procedural renderer was retired after a client visibility regression; visual review remains pending.
- [x] 3. Paper border: layered bevel, restrained brightness and defined corners.
- [x] 4. Messages: subtle inner outlines and compact header/body rhythm.
- [x] 5. Sender: larger avatar; stronger AzerMind name, secondary provider.
- [x] 6. Conversations: more title space, integrated menu and distinct rows.
- [x] 7. Toolbar: normalize optical size, not just canvas size.
- [x] 8. Connect: vertical crystal and balanced icon/label group.
- [x] 9. Composer: paper bevel, readable hint with bottom padding.
- [x] 10. Header: align brand, bridge and ping on a compact grid.
- [x] 11. Stitches: recessed seam and paired thread highlights, not floating dashes.

Checks: `node --test tests/grimoire_finish_test.js`, followed by existing layout/interaction checks and `npm test`.

Validation result: all 202 tests passed. In-game visual review is still pending.
