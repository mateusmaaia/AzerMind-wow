# Addon gear intelligence implementation plan

> **For agentic workers:** Use subagent-driven-development, with explicit file ownership. Root performs one consolidated review and final verification.

**Goal:** Answer whether an explicitly named or current dungeon contains active GearQuest hunts using installed addon data.

**Architecture:** Read-only runtime adapters expose normalized current GearQuest hunts and Dungeon Journal sources. An on-demand matcher appends a bounded, provenance-labeled attachment to relevant player questions. No new guide UI, copied third-party database, or inference of a destination from the journal's selected page. Existing equipment-sharing consent gates personal hunt data. Missing, simulated, ambiguous and partial data remain explicit.

**Tech Stack:** WoW Lua 5.1, installed GearQuest/ForeverDungeonJournal APIs, Node/Fengari tests.

## Ownership and steps

- [ ] GearQuest worker: `addon/AzerMind/GearQuestContext.lua` and `tests/gearquest_context_test.js`. Reproduce missing adapter, implement safe current-list reads, class/spec identity, preview rejection, weapon routing, ownership/eligibility checks, bounded results and unavailable states. No foreign settings mutation.
- [ ] Journal worker: `addon/AzerMind/JournalContext.lua` and `tests/journal_context_test.js`. Reproduce missing resolver/extractor, implement exact names/aliases/link IDs/current-instance resolution, direct/shared/trash loot and actual quest rewards, explicit ambiguity, provenance and partial data. Selected journal page is never a planned destination. Snapshot fallback marks limited coverage.
- [ ] Root: `addon/AzerMind/GearIntelligence.lua`, addon TOC/send hook, `tests/gear_intelligence_test.js`, test script and user documentation. Match IDs, append only relevant bounded matches, omit owned hunts, preserve source types and missing-data caveats. No automatic transmission when context/equipment sharing is off. Capture query before tooltip expansion and preserve multipart limits.
- [ ] Run adapter red/green tests, full suite, one consolidated review, fix findings directly, publish one feature PR and install verified files.
- [ ] Verify in game only after the client can load new addon files. Keep any required restart explicit; do not report live success before observing it.

## Acceptance

Named/current instance + active hunt intersection identifies item, slot and source without claiming guaranteed drops, quest eligibility or upgrade percentages. Absent data is not evidence of no upgrades. Both addons remain optional; integrations do not break ordinary chat. Unknown destination prompts for its name. Follow-up questions require an explicit dungeon or actual current instance, rather than guessing from a previous browse.
