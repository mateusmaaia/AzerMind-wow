# AzerMind

**Your AI companion in Azeroth.** Chat with your own AI agents inside World of Warcraft: Forever, share character context, browse items and quests, inspect dungeons and raids, and ask for macros or map routes.

AzerMind is a fork of [wow-ai by chelinho139](https://github.com/chelinho139/wow-ai), who built the original chat, agent bridge and transport architecture. This fork expands character tools, catalogs, reference browsing and settings. Original copyright and third-party notices are preserved; see [Credits](#credits) and [License](#license).

## Features

- Multiple conversations with independent agent sessions, working folders, live progress, cancellation and transcript recovery.
- Claude Code, OpenAI Codex, Grok Build, Antigravity and Hermes connectors using your installed CLI and authenticated account.
- Conversation defaults and per-conversation agent, model and supported reasoning overrides, searchable model choices and custom model IDs.
- Character sharing by category, with presets, preview and an off switch.
- Up to 20 guide-reference URLs shared with future messages.
- Character inventory and bundled item database, search, filters, level-range inputs, pagination, persistent selection, details and attachments.
- Character journal and bundled quest database, city/zone filters, quest details and map marks.
- Dungeons & Raids browser with search, type/location/level filters, boss and loot references, and attachments.
- Map layers, numbered routes, navigator arrow and optional gathering-node overlays.
- Macro creation/update buttons with confirmation and undo.
- Configurable notification sounds and Open chat / New chat bindings.
- Shift-click item, spell and quest links; copy replies and echo summaries into game chat.

The bundled snapshot includes **21,442 items, 5,233 quests, 13,417 NPCs and 7,045 objects**. Coverage is incomplete: records do not prove ownership, quest eligibility, current availability or drop rates.

### Optional AHledger prices

With the AHledger addon enabled, item picker tooltips and item attachments include
auction prices, market, quantity and observation time from its local API. Bundled
snapshots are marked explicitly. Prices are per unit and are not guaranteed sale
values. Without AHledger or an available price, browsing works as usual.
AHledger sync refreshes its data; AzerMind makes no network requests for prices.
Prices from [AHledger](https://ahledger.com); see its [integration documentation](https://ahledger.com/developers).

## Requirements

- **World of Warcraft: Forever**, interface **16001**. Compatibility with Retail or other Classic clients is not established.
- **Node.js 22.2+**, npm and at least one supported, authenticated agent CLI.
- Windows; Linux with Wine, **X11** and Python 3; or macOS with a native client and Python 3.
- A visible windowed or borderless game window for screen capture.

The bridge must run for AI chat. Local catalogs work without the bridge. AI subscriptions, usage charges and model access are managed by your provider.

## Install

### 1. Get this fork

Clone the repository and install dependencies:

```sh
git clone https://github.com/mateusmaaia/AzerMind-wow.git
cd AzerMind-wow
npm install
```

The [AzerMind repository](https://github.com/mateusmaaia/AzerMind-wow) contains this fork. The upstream link identifies the original project.

### 2. Install and authenticate an agent

You need only one connector:

| Agent ID | CLI | Preparation |
|---|---|---|
| `claude` | Claude Code | Install the CLI, run `claude` and authenticate. |
| `codex` | OpenAI Codex | `npm install -g @openai/codex`, then run `codex` and authenticate. |
| `grok` | Grok Build | Install the CLI, then run `grok login`. |
| `agy` | Antigravity | Install the supported CLI, then run `agy` and authenticate. |
| `hermes` | Hermes Agent | Install Hermes, then run `hermes setup`. |

Setup reports which executables it finds. See [agent documentation](docs/AGENTS.md) for permissions and connector details. Flags and available models depend on your installed CLI and account.

### 3. Install the addon

Fully quit WoW. On Windows:

```powershell
node setup.js --wow "C:\Program Files (x86)\World of Warcraft\_forever_" --project "C:\path\to\workspace"
```

On Linux or macOS:

```sh
node setup.js --wow "/path/to/client" --project "$HOME/projects/workspace"
```

If automatic client detection works, use `node setup.js --project <folder>`. Add `--account <name>` to select a specific WoW account.

Setup copies `AzerMind` and the four `AzerMind_Data*` modules into `Interface/AddOns`, creates reply-slot addons and signal files, and writes `bridge/config.json`. Thousands of small transport files are expected. All new files must exist before the game starts; a UI reload cannot discover new addon folders.

### 4. Start playing

```sh
npm start
```

Windows alternatives: double-click `bridge/start-window.cmd` or run `bridge/start.ps1`. The supervisor restarts a crashed bridge; Ctrl+C stops it.

Launch WoW, enable **AzerMind** and its data modules, log in, enter `/azermind`, then click **Connect** if shown. Type and press Enter.

- Windows: see [installation guide](docs/INSTALL-WINDOWS.md).
- Linux/Wine: use X11; run `npm run probe` while an outgoing pixel strip is visible to inspect capture. See [Linux guide](docs/INSTALL-LINUX.md).
- macOS: grant Screen Recording and Automation / System Events permissions to the terminal running the bridge. Use `npm run probe:mac` to check capture.

### Optional global command

Run `npm link` in the source folder. Then run `azermind` from any working folder, or `azermind --project <folder>`. Only one bridge should run at a time. Individual chats can choose their own folders.

## Upgrade from WoW AI

1. Stop the bridge and fully quit WoW so saved data is flushed.
2. Keep the existing `bridge/` state, config and transcripts. Run `npm install` and `node setup.js` from this fork, with client/account arguments if needed.
3. Setup copies legacy `WoWAI.lua` saved data to `AzerMind.lua` when no AzerMind save exists, updates config paths, and disables legacy WoWAI addon entry points. Original saved data is retained.
4. Relaunch WoW, enable AzerMind and restart the bridge. Recheck your key bindings.
5. For a previously linked command, run `npm unlink -g wow-ai`, then `npm link` in this fork.

`/wow-ai` remains a compatibility alias. Older WoWClaude migration support is also retained. Back up WTF saved data and bridge state before moving installations between machines.

## Use

### Conversations and AI configuration

Open `/azermind` and create a conversation. Right-click a conversation for management options; each conversation has its own session and working folder.

Open **Settings > AI Config** and choose **Conversation defaults** or **This conversation**. Conversations can inherit defaults or override agent, model and reasoning. Model preferences are stored per agent. Changing effective provider settings starts a fresh provider session while preserving the transcript.

Models come from local discovery, configured catalogs and bundled compatibility choices. **Enter model ID...** accepts a custom ID; empty overrides use CLI defaults. Listed models do not guarantee account access. Reasoning options depend on connector support; Grok keeps its CLI reasoning default.

### Character sharing and guides

Under **Settings > Character**, choose game/client, identity, realm/guild, zone, coordinates, money/XP, talent totals, professions, skills, learned spells, quest IDs and equipped items. Use presets and **Preview**, then **Save**. You can disable automatic sharing; manual attachments still form part of your message. Individual talent ranks and pet abilities are not collected. Missing data and size limits are identified. Disabling sharing does not erase previously sent information.

Under **Settings > Guide references**, enter one URL per line, up to 20, and save. Links apply to future messages in all conversations independently of character sharing. Agents can read them only if their tools and permissions allow it.

### Items, quests and instances

| Browser | How to use |
|---|---|
| **Items** | Choose inventory or database, search and filter, set a required-level range, browse pages and inspect details. Select rows, a page or filtered results and insert them into your draft. Bank data depends on client availability. |
| **Quests** | Choose journal or database, search and filter by City/Zone, inspect records and insert selected references. City means a recorded quest-starter capital, not the objective location. |
| **Dungeons & Raids** | Search instance/boss/location, filter type/location/near-level, inspect bosses/loot/entrances and insert selected references. Level ranges are references, not guaranteed entry requirements. |

Selections can persist across pages and filters: check the selected count. Database entries are reference records, not owned items or accepted quests. Item fields can depend on the client cache. Missing records are not invented, and snapshot content is not a live opening or loot guarantee.

Right-click a quest link to mark an available objective or turn-in on the map. Multiple locations open a chooser. Missing coordinates are not guessed, and manual marks do not automatically track progress.

Focus the input and shift-click supported items, spells, quests or links to attach them. Attachments expand to reference data when sent. Click a reply or `/azermind copy` to copy it. `/r` replies to the agent when it was the last sender; a player whisper restores normal reply behavior.

### Maps and macros

Ask for a route or location to receive map layers and numbered pins. The navigator points to the current stop; right-click advances it. Gathering overlays require a compatible optional `AzerMind_Nodes` addon, which is not bundled here.

Ask for a macro, then click **Create macro** or **Update**. Replacing a different macro asks for confirmation; script-like macros receive an extra prompt. Creation is blocked in combat. The addon does not execute the macro. `/azermind macro undo` reverses the latest change.

### Notifications and shortcuts

**Settings > Notifications** offers None, Whisper, Battle.net toast, Map ping, Ready check and Tutorial popup, with **Preview**. Sound availability depends on the client.

Use **Settings > Key bindings** for Open chat / New chat, or the AzerMind section of the game's Key Bindings menu.

## Commands

`/ai` is a short alias for `/azermind`. Run `/azermind help` for the full built-in list.

| Command | Action |
|---|---|
| `/azermind` | Toggle the window. |
| `/ai <message>` | Send from normal game chat. |
| `/azermind new [name]` | Create a conversation. |
| `/azermind chat <number or name>` | Switch conversations. |
| `/azermind agent [claude\|codex\|grok\|agy\|hermes\|default]` | Show/change agent. |
| `/azermind cd <folder>` | Change working folder; omit the folder to restore default. |
| `/azermind rename`, `delete`, `clear` | Manage the conversation. |
| `/azermind reset` | Reset provider memory, retain transcript. |
| `/azermind context [on\|off]` | Inspect/toggle context. |
| `/azermind echo summary\|full\|short\|off\|<chars>` | Set game-chat reply output. |
| `/azermind copy` | Copy the latest reply. |
| `/azermind bind <key>` | Set the legacy toggle/check-reply shortcut. |
| `/azermind cancel`, `resend` | Stop waiting / retransmit a message. |
| `/azermind diag`, `slots` | Transport diagnostics. |
| `/azermind reload` | Reload UI and free consumed slots. |
| `/azermind mode reload` | Use the UI-reload fallback transport. |
| `/azermind map` | List map settings/layers. |
| `/azermind map ore [on\|off]`, `map herb [on\|off]` | Toggle optional gathering overlays. |
| `/azermind map filter all\|skill` | Filter gathering nodes. |
| `/azermind map hide <layer>`, `map show <layer>` | Toggle a layer. |
| `/azermind map nav <layer> [stop]` | Start navigation. |
| `/azermind macro undo` | Undo the latest macro change. |

## Bridge settings and permissions

Edit `bridge/config.json`, then restart the bridge. Keep local runtime files private.

| Key | Purpose |
|---|---|
| `defaultCwd`, `agent` | Default working folder and agent. |
| `agents.<id>.path` | Explicit CLI path if discovery fails. |
| `agents.<id>.model`, `.reasoning`, `.models` | Defaults and optional model catalog. |
| `agents.<id>.permissionMode` | Provider-specific permissions. |
| `agents.<id>.allowedTools`, `.deniedTools` | Tool rules where supported. |
| `agents.codex.networkAccess` | Codex sandbox network access; default off. |
| `maxParallel` | Simultaneous runs; default 3. |
| `gameContext`, `primerFile` | Character-context master switch and addon reference file. |
| `capture.processName` | Game process without `.exe`. |
| `timeoutMs` | Run timeout; default 30 minutes. |

Agents operate in the selected folder with their configured permissions. Claude/Grok **Allow & retry** actions persist rules in config: read the proposed rule before accepting. Permission semantics differ across providers; `bypassPermissions` grants broad access. See [configuration](docs/CONFIGURATION.md) and [agents](docs/AGENTS.md).

## Architecture and catalog updates

Outgoing messages are encoded as colored screen pixels. The bridge captures the strip, runs the agent and writes replies into pre-created load-on-demand addon slots. Signal files provide heartbeat/readiness checks. Normal operation does not need a UI reload per message.

The addon uses game addon APIs; the bridge uses screen capture and ordinary files. It does not inject code into the game, read game process memory or generate gameplay input. This is an implementation description, not a Blizzard endorsement.

Catalog indexes and detail modules load separately on demand. Lists are paginated; first-time Lua loading remains synchronous. Catalogs ship with releases rather than downloading during gameplay. See [architecture](docs/ARCHITECTURE.md), [maps](docs/MAP.md) and [catalog sources/building](CATALOG.md).

## Troubleshooting

| Symptom | Check |
|---|---|
| Red light / no answer | Run `npm start`, keep the game visible and inspect `bridge/bridge.log`. |
| Update not visible | Run `node setup.js` and `npm run verify:install`. Fully restart for renamed/new folders; `/reload` only reloads existing files. Enable AzerMind and disable old WoW AI. |
| Agent unavailable | Check startup discovery, authenticate manually, or configure its executable path. |
| Model rejected | Use CLI default and check account/version support; listed models do not grant access. |
| Slots missing/exhausted | Run `npm run slots` and restart for missing files; `/azermind reload` frees already discovered slots. |
| Catalog missing | Install and enable all `AzerMind_Data*` modules from the same build. Load new modules outside combat. |
| Missing stats/sources | Check client cache and catalog coverage; not every field exists. |
| Lost chats | Keep `bridge/transcripts.json`; reconnect for bridge recovery. |
| Linux black capture | Use X11, windowed mode, `capture.keepComposited` and `npm run probe`. |
| macOS capture denied | Grant terminal Screen Recording / Automation permissions. |

## Development and packaging

```sh
npm install
npm test
npm run verify:install
# Optional real agent call, requiring an authenticated CLI:
npm run test:live -- --agent codex
# Rebuild from local source artifacts:
npm run catalog:build -- /path/to/QuestieDB
node tools/build-instances.js /path/to/ForeverDungeonJournal
```

Create the addon ZIP on Windows with `./tools/package-release.ps1`. It includes catalog modules, transport slots and notices; the Node bridge is installed separately. Packaging does not publish to CurseForge. Upstream's CurseForge page is not an AzerMind release channel.

| Path | Contents |
|---|---|
| `addon/AzerMind/` | Chat, settings, links, pickers and map UI. |
| `addon/AzerMind_Data*/` | Catalogs, source provenance and licenses. |
| `bridge/` | Capture, agents, transport and local state. |
| `tools/` | Builders, packaging and installation verification. |
| `tests/` | Protocol, connector, installer and Lua tests. |
| `docs/` | Platform and architecture references. |

Offline tests do not establish client rendering or live provider compatibility. Check the installed build in Forever before publishing. See [contributing](CONTRIBUTING.md).

## Credits

| Author / project | Contribution |
|---|---|
| [chelinho139 — wow-ai](https://github.com/chelinho139/wow-ai) | Original project and upstream author: in-game conversations, agent bridge, transport, maps, macros, recovery, installers and documentation. Original MIT copyright retained. |
| [0xInuarashi — wow-forever-codex](https://github.com/0xinuarashi/wow-forever-codex) | Pioneered pixel output for Codex and measured Forever file-loading rules; upstream adapted those findings to load-on-demand replies instead of a font-metrics return channel. |
| [Gethe — wow-ui-source](https://github.com/Gethe/wow-ui-source) | Blizzard UI source mirror, used by upstream to verify Forever APIs. |
| [Questie team and contributors](https://github.com/Questie/Questie) | Map research and historical quest/world data underlying QuestieDB, including its historical contributors. |
| [QuestieDB team and contributors](https://github.com/Questie/QuestieDB) | Bundled Forever item, quest, NPC and object data. Manifest records source commit, checksum, counts and gaps. |
| ForeverDungeonJournal authors and contributors | Installed factual dungeon snapshot: names, levels, entrances, bosses and available loot. Checksum recorded in `addon/AzerMind/InstancesData.json`; the generator excludes strategy prose and art. |
| [Blizzard Entertainment — Forever raid overview](https://news.blizzard.com/en-gb/article/24303009/world-of-warcraft-forever-raid-overviewlocations-raid-sizes-and-attunement) | Source of bundled announced raid overview records. World of Warcraft and related names belong to their respective owners. |
| AzerMind contributors | Fork branding, expanded sharing, catalogs, instance browsing, guide references, model settings and UI improvements. |

This fork is not an official release by the upstream author, Blizzard, Questie or any AI provider. Renaming does not change the origin of their work.

## License

Original code is **MIT**; see [LICENSE](LICENSE). `Copyright (c) 2026 chelinho139` is preserved.

Third-party catalog data has separate terms. Keep the [source license](addon/AzerMind_Data/SOURCE-LICENSE.md), [GPLv3 text](addon/AzerMind_Data/SOURCE-gpl-3.0.md), manifest and provenance with distributions. QuestieDB documents unresolved historical licensing; the addon/bridge MIT license does not relicense those records or establish that all upstream rights are cleared. See [CATALOG.md](CATALOG.md).
