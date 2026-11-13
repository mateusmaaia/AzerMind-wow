# Archivist Grimoire — main chat implementation

Chosen direction: brown leather, quiet ivory parchment, aged bronze and burgundy selection. Preserve the approved violet crystal / open-book emblem. Scope: main chat and its menus, tooltips, conditional actions and minimized bar. Item/quest/instance/settings interiors are a later project; their launch buttons belong here. Do not commit or install into the game before the preview has been shown.

## Asset inventory and production rules

The executable inventory is `tools/grimoire-manifest.js`: every source PNG, runtime RGBA TGA, size, resize mode and consuming component is declared there. No text is baked into artwork. Sources and generated production textures remain in this repository. Never store MCP credentials.

| Batch | Assets | Usage |
| --- | --- | --- |
| Identity | Approved emblem | Header, AI avatar, empty state, minimized bar |
| Materials | Leather, parchment, warm parchment | Outer window/header/sidebar, transcript/composer, AI message |
| Frames | Window, panel, card, input, popup | Corners fixed, edges tiled, center separate |
| Buttons | Primary burgundy, secondary bronze, conversation selection | Every caption remains live text |
| Navigation | Divider, scroll track/thumb, resize grip | Conversation/history/input scrolling, sizing |
| Toolbar icons | Items, quests, instances, character | Existing four actions |
| Action icons | Settings, plus, more, delete, copy, resend, send, stop, connect, clear, minimize, reload | Conversations, messages, composer, header |
| Supporting icons | Up/down chevrons, user, warning, sources | Scrollbars, role, errors, links |
| Gems | Connected, connecting, disconnected, unread | Connection and conversation activity |

Normal/hover/pressed/disabled/selected/focus appearances derive from shared art plus Lua overlays and tints. Share repeated icons instead of generating duplicates. Protected source insets are declared per asset (16px for the original small art, 64px for illustrated controls, 192px for the illustrated window). Source dimensions may be rectangular. Illustrated rails are separate repeatable textures so stitches retain their scale instead of stretching. Tile materials must have matching opposing edges and no baked shadows, borders, text or objects. Convert to uncompressed 32-bit TGA; verify decoded pixels and alpha against source. Review art here before integration.

## Sequential gates

Run `npm run grimoire:verify -- --through N`. Every run rechecks all predecessors against the current files. A missing test is a failure, never a skipped or implicitly completed step. These are development gates, not protection against someone deliberately editing the checks. Never claim a later gate passes because its checklist exists.

| Step | Deliverable | Required executable verification before proceeding |
| --- | --- | --- |
| 1 | Inventory, sizing rules and baseline | Manifest validation and existing real-Lua addon tests |
| 2 | Four identity/material assets, conversion and preview | File signatures/sizes/format; image decoder tests for PNG/TGA pixel equivalence, transparency and tile seams; inspect preview at 1x and 2x |
| 3 | Frames, buttons, icons and gems | All declared files; decoded images, alpha bounds, safe slice insets, visible nonempty icons; assembled contact sheet inspected |
| 4 | Art registry and reusable Lua skin components; skin actual main-chat widgets | Real Lua tests assert texture paths, tiling, UVs, protected corners, button state transitions and actual widget consumers. Parse changed Lua; run existing addon suite. No proof by searching source strings alone |
| 5 | Resize and behavioral preservation | Drive real frame resize handlers at minimum 900x600, standard 1180x830 and large 1600x1000; verify effective WindowBounds first. Assert nonoverlap, anchored composer, wrapped text, toolbar two-row transition, scrolling, message actions, new/select/delete chat, attachments, connect/send/stop, minimize/restore, tooltip and permission states |
| 6 | Visual evidence and deployment parity | Native-client screenshots at all three sizes, connected/disconnected/busy/empty/error states; record current source/art SHA256 with screenshots and review findings. Tests reject stale or incomplete evidence. Install test compares source and installed art hashes and packaging contents. Run full regression suite. Final commit remains on hold |

Step 2's image tests and subsequent gate test files are intentionally not placeholders: implement them with their actual deliverables. Until then those gates remain blocked. Generation completion is not implementation completion.

## Build order within integration

1. Add registry and separate background/edge renderers with a functional fallback.
2. Skin window/header/sidebar; verify fixed logo and live title/status.
3. Skin user/AI/system messages and attachment pills without changing serialization or content.
4. Skin toolbar/composer/actions; preserve connect/send/stop semantics and keyboard behavior.
5. Skin scrollbars, menus, tooltips, activity indicators and minimized bar.
6. Verify small-window reflow, then inspect native-client output and deployment.

## What code checks cannot prove

The Lua stub can verify geometry/state contracts but cannot reproduce WoW font metrics, GPU sampling, actual TGA loading or visual quality. Seam tolerances must be numeric and checked with decoded pixels, then reviewed visually. Screenshots require the real client; no mocked screenshot counts as native evidence. If deployment is unavailable, report step 6 blocked and retain the preview; do not pretend local tests verified installed files.

## Current progress

### Early in-game materials preview

At the user's explicit request to put the current materials in the game now, an incremental preview applies the completed step-2 materials before the step-3 bespoke frames/icons. This is not completion of gates 3–6. Main-window leather, parchment transcript/cards/composer, dark ink, burgundy selection and the approved header emblem are wired to actual widgets. Existing native borders/icons remain. The real-Lua addon tests exercise applied texture paths, resizing UVs and ink/link handling. The focused installer preserves Inbox.lua and verifies every copied file by SHA256; installation parity now includes nested TGA/BLP textures. Use `npm run grimoire:install` for the preview. Actual client visual QA remains outstanding.

The first complete skin passed steps 1 through 5. Native screenshots subsequently showed that its procedural art was too flat compared with the approved concept. The revised version now has 62 declared production assets, including 9 illustrated skins exported from image-generated masters and 20 dedicated seamless rail textures. PixelLab recipes remain for the base materials and small icons. `npm run grimoire:art` reproduces all exports from their preserved recipes/masters. Decoded-pixel tests verify material/rail seams, no quadrant lighting drift, alpha, 7:1 ink contrast for reading materials, per-axis slices and lossless conversion. Previews under `art/grimoire/previews` include materials, illustrated controls, frames, icons, navigation and gems; provenance is in `GRIMOIRE-ASSET-JOBS.json`.

The main chat now consumes bronze nine-slice frames, non-native brown/burgundy buttons, burgundy conversation selection, parchment rows, generated toolbar/message icons, role avatars, connection gems and three skinned scrollbars. Connect/send/stop artwork follows runtime state. Header text is constrained away from right-side controls. Resize bounds are 900x600 minimum (or the available UI area on smaller displays), up to 95% of UIParent. Tests resolve the actual recorded Lua anchor graph at 900x600, 1180x830 and 1600x1000 and reject toolbar/composer/action overlap; font rendering still requires native-client QA. Native template emulation in tests keeps button labels separate from button geometry.

The illustrated revision adds 32px protected outer corners, stitched leather rails, bevelled parchment/dark leather/burgundy controls, 17px serif message text, 18px sender headings, 24px branding and 16px conversation labels. The header is 80px tall; composer actions are 148px wide with horizontal icon/caption layout. Placeholder and keyboard hint remain real live text, with reserved hint space in the composer.

Complete inventory snapshot blocks in user messages now render as compact inspectable attachment cards (first item, quantity/location and a count of additional items). Only presentation changes: saved message text, copied context and agent transport retain the full snapshot. Malformed blocks and assistant messages are not collapsed. Actual item icons are used only when an explicit item ID is present; otherwise a generic bag is shown. Clicking a card opens its original snapshot.

Step 6 remains outstanding: the code is not an in-game screenshot, and no native visual approval is recorded for this version. Installation is user-run because this session cannot write into the game's Program Files directory. Use `npm run grimoire:install`, restart WoW to discover new TGA assets, then inspect the main window at several sizes. No commit has been made. Consult current verifier output rather than treating this document as an approval receipt.
