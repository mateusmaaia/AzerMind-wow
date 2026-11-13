# Forever talent context implementation plan

> **For agentic workers:** Use subagent-driven-development, with root performing one consolidated review and final verification.

**Goal:** Supply the AI with actual talent allocation from the Forever client instead of an unavailable legacy-tree summary.

**Architecture:** Read the active C_ClassTalents/C_Traits configuration, group totals and purchased node ranks with named spell definitions. Treat staged edits as unavailable committed data, expose unspent points only when reliable, and retain compatible legacy fallbacks. Respect existing talent-sharing preference and bounded game context. Never claim ranks are absent when a valid snapshot is supplied.

**Tech Stack:** WoW Lua 5.1 and Node/Fengari tests.

- [x] Reproduce active Forever configuration with no legacy globals and assert named talent ranks in GameContext.
- [x] Read and bound talent data in the existing sharing section. Identify unavailable, partial, and pending data. Handle shared nodes, choices, zero points, and legacy APIs.
- [x] Cover sharing disabled, malformed or missing APIs, pending changes, rank and name resolution, and refresh after spending a point.
- [x] Update the character-sharing UI and API documentation.
- [ ] Integrate with the context-budget and guide changes, publish the dedicated fix PR, and verify installed context after reload or restart.
