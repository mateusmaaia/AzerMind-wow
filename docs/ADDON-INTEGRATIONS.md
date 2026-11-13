# Addon intelligence

AzerMind can attach current GearQuest hunts and matching Dungeon Journal sources to a question. This is optional context for the AI conversation; it does not replace either addon or change their settings.

For example: **"Vou Dalaran. Tem itens que o GearQuest recomenda para mim?"** The installed journal's aliases identify City of Dalaran. An attached AzerMind dungeon link also works. Inside a party or raid instance, questions about items or drops can use the actual current instance. A journal page being viewed is never assumed to be a planned destination. If the destination is missing or ambiguous, the AI receives that limitation instead of a guessed dungeon.

## What is shared

- GearQuest's active hunt lists for its current player class/spec and weapon preferences, with live ownership checks when available. Simulated preview profiles are not used as actual player recommendations.
- Matching positive item IDs in the loaded ForeverDungeonJournal: boss loot, shared loot, trash drops and actual quest rewards. Completed quests and faction restrictions are labeled when available; prerequisites and reward eligibility are not guaranteed.
- Source/version and partial-data markers. Without loaded journal data, bundled instance records can supply explicitly partial references. Missing addons or failed reads are not interpreted as no upgrades.

The integration uses existing **Share character context → Equipment and GearQuest hunts** consent. Disabling automatic sharing or this field omits hunt data. Attachments are generated when a relevant question is sent, are capped at 3,200 bytes / 20 matched source rows, and remain visible in that message's history. Turning sharing off does not erase earlier messages.

Matches use base item IDs, not names. Random suffix requirements are retained, but the journal does not guarantee that exact variant will drop. An active hunt is GearQuest's recommendation, not a new AzerMind score or a guaranteed upgrade. Already owned items are omitted when GearQuest confirms ownership.

## Installation and compatibility

GearQuestForever and ForeverDungeonJournal are optional dependencies. Neither is installed, enabled or modified by this feature. Restart WoW fully after installing the new AzerMind Lua files so the client discovers them. Existing addon settings and chats are preserved.

Runtime adapters were checked against GearQuest Forever 1.1.4 and ForeverDungeonJournal 2.0.2. Their interfaces are not a shared public standard; missing methods, unloaded class data and malformed responses are reported as unavailable or partial. GearQuest supplies its active list order; AzerMind does not reimplement its scoring or vendor its databases.

For diagnostics, compare the **Addon gear observations** section in the sent question with the addons' current active lists. A plain question with no dungeon reference outside an instance does not establish a destination. Use a named dungeon again for follow-ups if you have not entered it.
