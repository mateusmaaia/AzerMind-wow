# Main integration, 2026-11-13

The default branch is `main`. Integration started from local `a11e341` and
remote `d8763cd`, including the six already merged PRs #1 through #6.

## Preserved work

- `bf868d0` records all 185 changed/new local files before merging: Grimoire
  presentation, runtime textures, image sources, AHledger auction context,
  installation/recovery tooling and regression checks.
- `backup/pre-integration-20261113` retains the original local base.
- Ignored runtime files, local configuration, dependencies and recovery snapshots
  were left in place. The separate clean `feat/go-companion` worktree at
  `021e945` was not part of the two open PRs and was left intact.

## Integrated branches and conflict decisions

- PR #7, `fix/forever-talent-context`, head `6e371d1`: retained the current
  active/completed quest context and its priority, then replaced the obsolete
  talent-totals-only section with `TalentContext()`. Documentation describes
  both quest history and purchased talent ranks. Commit: `aa1c7c8`.
- PR #8, `feat/addon-gear-intelligence`, head `1671aff`: combined the equipment
  sharing label with completed quest sharing, retained both troubleshooting and
  integration documentation, and combined optional dependencies (AHledger,
  GearQuestForever and ForeverDungeonJournal). All new modules and all local
  and incoming test suites remain enabled. Commit: `30d2be2`.
- Updated the connection-timeout regression to open and inspect the Grimoire
  status tooltip, which carries the full diagnostic behind the compact label.
  The UI test loaders include talents, auctions and gear intelligence together.
- Compared incoming adapter modules against their PR heads and local textures,
  image sources, theme, item/link integration and installer tools against the
  preservation commit; those implementations remain unchanged.

## Validation and limits

- `npm test`: passed all 277 Node tests, Lua 5.1 syntax/declaration-order checks,
  and all 16 real Windows `capture.ps1` codec cases.
- `node tools/audit-ui-simulation.js --summary`: completed; records 23 unmodeled
  APIs rather than claiming complete client fidelity.
- Final whitespace/conflict-marker review: removed one pre-existing extra blank
  line at the end of a local test; no functional local work was discarded.
- `node tools/visual-review.js --verify`: correctly reports visual review pending.
  No in-game screenshots, human approval, installation or release package is
  claimed. Fonts, layering, animation and scaled rendering still need WoW review.

The complete test suite passed after the integration changes. The final cleanup
only removes a blank line and adds this report.
