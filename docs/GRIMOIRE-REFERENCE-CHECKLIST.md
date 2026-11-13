# Grimoire reference polish checklist

Reference: user-provided concept and in-game capture, 2026-11-12.
All nine items have runtime Lua regression coverage. Visual fidelity remains pending an in-game capture.

1. [x] Assistant heading: `AzerMind - <actual reply provider>`; historical provider retained.
2. [x] Conversation title: centered, readable, bounded away from settings; gold ornaments on both sides.
3. [x] Conversation rows: distinct dark leather backgrounds, burgundy selection; retain scrollbar gutter.
4. [x] Reading area: one outer bronze frame around continuous parchment; no heavy per-message boxes.
5. [x] Composer: retain quiet parchment, dark readable ink and text padding.
6. [x] Leather: subtle stitched seams on header and sidebar, resize without allocating indefinitely.
7. [x] Connect: burgundy primary surface and larger crystal; preserve connect/send/stop state transitions.
8. [x] Composer scrollbar: spans the writing panel height, with separate room for the keyboard hint.
9. [x] Appearance settings: saved global opacity, live preview, bounded safe minimum, reset; applies to main, mini and independent dialogs without double multiplication.

Validation: `node --test tests/grimoire_reference_test.js`, existing layout/interaction checks, then `npm test`.
