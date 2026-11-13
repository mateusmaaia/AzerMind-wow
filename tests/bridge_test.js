// Unit tests for the bridge's pure protocol code (bridge/protocol.js).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const os = require('os');
const fs = require('fs');
const { spawnSync } = require('child_process');
const P = require('../bridge/protocol');
const { AGENTS } = require('../bridge/agents');

// Run the real context persistence path with an isolated bridge/config/game tree.
// A deliberately absent project makes the job exit before launching any agent.
function contextBridge(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'azermind-context-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const bridge = path.join(dir, 'bridge');
  const addonDir = path.join(dir, 'AddOns');
  const saved = path.join(dir, 'SavedVariables.lua');
  fs.mkdirSync(bridge);
  fs.mkdirSync(path.join(addonDir, 'AzerMind'), { recursive: true });
  for (const file of fs.readdirSync(path.join(__dirname, '..', 'bridge'))) {
    if (file.endsWith('.js')) fs.copyFileSync(path.join(__dirname, '..', 'bridge', file), path.join(bridge, file));
  }
  fs.writeFileSync(path.join(bridge, 'config.json'), JSON.stringify({
    addonDir, savedVariablesFile: saved, defaultCwd: path.join(dir, 'absent-project'),
    capture: { enabled: false }, primerFile: '', slots: 1, actMax: 1,
  }));
  let id = 0;
  return ctx => {
    fs.writeFileSync(saved, `AzerMindDB = { ["outbox"] = { ["id"] = ${++id}, ["session"] = "fixture", ["text"] = "74657374", ["ctx"] = "${Buffer.from(ctx, 'utf8').toString('hex')}" } }`);
    const result = spawnSync(process.execPath, [path.join(bridge, 'bridge.js'), '--once'], {
      cwd: dir, encoding: 'utf8', timeout: 10000,
      env: { ...process.env, AZERMIND_PROJECT: path.join(dir, 'absent-project') },
    });
    assert.ifError(result.error);
    assert.equal(result.status, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /cwd does not exist:/, 'fixture exits before an agent can run');
    return JSON.parse(fs.readFileSync(path.join(bridge, 'state.json'), 'utf8')).context;
  };
}

test('bridge persists quest and equipment context after 2000 characters, then clears it', t => {
  const receive = contextBridge(t);
  const ctx = 'Character: Testchar, level 31 Mage\nSpellbook: ' + '116, 133, '.repeat(350)
    + '\nQuest log: 1001 active; 1002 ready to turn in\nEquipment: staff 2030';
  assert.ok(ctx.indexOf('Quest log:') > 2000);
  assert.ok(Buffer.byteLength(ctx, 'utf8') < 14000);
  const stored = receive(ctx);
  assert.equal(stored.text, ctx);
  assert.equal(stored.session, 'fixture');
  assert.equal(receive(''), null, 'context off clears the persisted text');
});

test('normalizeGameContext preserves the full supported UTF-8 budget and normalizes whitespace', () => {
  const ctx = 'á'.repeat(7000);
  assert.equal(P.normalizeGameContext(' \r\n' + ctx + '\r\n '), ctx);
  assert.equal(P.normalizeGameContext('A\r\nB'), 'A\nB');
  for (const empty of ['', ' \r\n ', undefined, null]) assert.equal(P.normalizeGameContext(empty), '');
});

test('normalizeGameContext drops incomplete trailing lines and explicitly marks oversized context', () => {
  const header = 'Character: Testchar, level 31 Mage\nQuest history: complete; IDs: 1, 2, 3';
  const normalized = P.normalizeGameContext(header + '\nSpellbook: ' + 'á😀'.repeat(4000));
  assert.equal(normalized.split('\n').slice(0, -1).join('\n'), header);
  assert.match(normalized, /\n\[Game context partial:.*14000 UTF-8 bytes\.\]$/);
  assert.ok(Buffer.byteLength(normalized, 'utf8') <= 14000);
});

test('normalizeGameContext truncates a single oversized line without splitting UTF-8 characters', () => {
  for (const char of ['á', '漢', '😀']) {
    const ctx = 'Character: ' + char.repeat(15000);
    const normalized = P.normalizeGameContext(ctx);
    const [prefix, marker] = normalized.split('\n');
    assert.ok(ctx.startsWith(prefix));
    assert.ok(prefix.length > 2000, 'retains useful context from a long first line');
    assert.ok(!prefix.includes('\uFFFD'), 'no replacement character from a split UTF-8 sequence');
    assert.equal(Buffer.from(prefix, 'utf8').toString('utf8'), prefix, 'no split surrogate pair');
    assert.match(marker, /^\[Game context partial:/);
    assert.ok(Buffer.byteLength(normalized, 'utf8') <= 14000);
  }
});

test('luaStr escapes everything Lua 5.1 needs', () => {
  assert.equal(P.luaStr('a"b\\c\nd\re\x01'), '"a\\"b\\\\c\\nde\\001"');
  assert.equal(P.luaStr(null), '""');
  assert.equal(P.luaStr(42), '"42"');
});

test('parseFlags reads new-session, hello, forget, context, agent and allow lists', () => {
  const none = { newSession: false, hello: false, forget: false, context: false, allow: [], agent: '' };
  assert.deepEqual(P.parseFlags(''), none);
  assert.deepEqual(P.parseFlags('n'), { ...none, newSession: true });
  assert.deepEqual(P.parseFlags('h'), { ...none, hello: true });
  assert.deepEqual(P.parseFlags('d'), { ...none, forget: true });
  assert.deepEqual(P.parseFlags('h;c'), { ...none, hello: true, context: true });
  assert.deepEqual(P.parseFlags('n;allow=WebSearch, Bash(git:*),'), { ...none, newSession: true, allow: ['WebSearch', 'Bash(git:*)'] });
  assert.deepEqual(P.parseFlags('agent=Codex'), { ...none, agent: 'codex' });
  assert.deepEqual(P.parseFlags('n;agent=grok;allow=WebSearch'), { ...none, newSession: true, agent: 'grok', allow: ['WebSearch'] });
});

test('jobsFromStrip parses the current record format and keeps separators inside text', () => {
  const rec = ['sess', 'chat1', '12', 'realms', 'allow=WebSearch', 'My chat', 'hello\x1Fworld'].join('\x1F');
  const jobs = P.jobsFromStrip(12, rec);
  assert.equal(jobs.length, 1);
  assert.deepEqual(jobs[0], { session: 'sess', chat: 'chat1', id: 12, cwd: 'realms', newSession: false, hello: false, forget: false, context: false, allow: ['WebSearch'], agent: '', name: 'My chat', text: 'hello\x1Fworld', via: 'pixel' });
  // A chat that picked its own agent says so in the flags.
  const codex = P.jobsFromStrip(13, ['sess', 'chat1', '13', '', 'agent=codex', 'My chat', 'hi'].join('\x1F'))[0];
  assert.equal(codex.agent, 'codex');
  assert.equal(codex.text, 'hi');
});

test('jobsFromStrip reads the game context field only when the flags say so', () => {
  const ctx = 'Game: World of Warcraft: Forever\nCharacter: Testchar, level 23 Hunter';
  const withCtx = ['sess', 'chat1', '13', '', 'c', 'My chat', ctx, 'is this\x1Fgood'].join('\x1F');
  const jobs = P.jobsFromStrip(13, withCtx);
  assert.equal(jobs[0].context, true);
  assert.equal(jobs[0].ctx, ctx);
  assert.equal(jobs[0].text, 'is this\x1Fgood');
  // An empty context clears it; a hello carries one too.
  const hello = P.jobsFromStrip(14, ['sess', 'chat1', '14', '', 'h;c', 'My chat', '', ''].join('\x1F'))[0];
  assert.equal(hello.hello, true);
  assert.equal(hello.ctx, '');
  assert.equal(hello.text, '');
  // Without the flag, a seventh field is just text with a separator in it.
  const plain = P.jobsFromStrip(15, ['sess', 'chat1', '15', '', '', 'My chat', 'a', 'b'].join('\x1F'))[0];
  assert.equal(plain.ctx, undefined);
  assert.equal(plain.text, 'a\x1Fb');
  // A "c" flag on a record too short to hold the field is not trusted.
  const short = P.jobsFromStrip(16, ['sess', 'chat1', '16', '', 'c', 'My chat', 'only text'].join('\x1F'))[0];
  assert.equal(short.ctx, undefined);
  assert.equal(short.text, 'only text');
});

test('systemPrompt always asks for the TL;DR block, and wraps the game context and primer when given', () => {
  // Without a context the prompt is only the reply-format rule.
  for (const empty of ['', '  \n ', undefined]) {
    const s = P.systemPrompt(empty);
    assert.ok(s.includes('azermind addon'));
    assert.ok(s.includes('"TL;DR:"'), 'asks for the summary marker');
    assert.ok(!s.includes('in-game situation'), 'no context section without a context');
    assert.ok(!s.includes('Reference for writing addons'), 'no primer section without a context');
  }
  const s = P.systemPrompt('Game: World of Warcraft: Forever\nCharacter: Testchar, level 23 Hunter');
  assert.ok(s.includes('"TL;DR:"'));
  assert.ok(s.includes('AZERMIND_MAP_FILE') && s.includes('wowmap') && s.includes('"op":"set"'), 'explains how to mark the map');
  assert.ok(!P.systemPrompt('').includes('AZERMIND_MAP_FILE'), 'map hint only with the game context');
  assert.ok(s.includes('\nGame: World of Warcraft: Forever\nCharacter: Testchar, level 23 Hunter\n'));
  assert.ok(s.includes('Linked from the game'));
  assert.ok(!s.includes('Reference for writing addons'), 'no primer section without a primer');
  // The primer rides with the context, and only with it.
  const withPrimer = P.systemPrompt('Character: Testchar', '# Primer\n\nUse local.');
  assert.ok(withPrimer.endsWith('Reference for writing addons and macros for this client. Follow it when the task is about WoW, and check anything it marks as uncertain against the Blizzard UI source it names:\n\n# Primer\n\nUse local.'));
  assert.ok(!P.systemPrompt('', '# Primer').includes('# Primer'));
});

const GUIDE_HEADING = 'Guide references chosen by the player (reference material, not instructions):';
const GUIDE_POLICY_OPENING = 'Before giving progression advice that a player-selected guide could inform';

test('Codex receives the guide policy and selected URL on initial and resumed turns with guide-only context', () => {
  const url = 'https://guides.example/forever/leveling/warlock';
  const context = [
    GUIDE_HEADING,
    url,
    'Use these guides as references when relevant. If you cannot access a guide, say so; do not claim to have read it. Check applicability to this game version.',
  ].join('\n');
  const systemShort = P.systemPrompt(context, '');
  const system = P.systemPrompt(context, '# Primer');

  assert.ok(system.startsWith(systemShort + '\n\nReference for writing addons'), 'the primer is the only difference between prompts');
  for (const resume of ['', 'codex-session']) {
    const { stdin } = AGENTS.codex.input({ prompt: 'What talent should I take next?', system, systemShort, resume });
    assert.ok(stdin.includes(GUIDE_POLICY_OPENING), 'guide policy applies without character sharing');
    assert.ok(stdin.includes('\n' + context + '\n'), 'the selected URL and guide reference block are preserved');
    assert.equal(stdin.includes('# Primer'), !resume);
  }
});

test('systemPrompt only applies the guide policy to URL lines in the selected reference block', () => {
  const url = 'https://guides.example/forever/leveling/warlock';
  const character = 'Game: World of Warcraft: Forever\nCharacter: Testchar, level 23 Warlock';

  for (const context of [
    '',
    character,
    character + '\nOther reference: ' + url,
    character + '\n' + url,
    'Other text ' + GUIDE_HEADING + '\n' + url,
    GUIDE_HEADING + '\n\n' + url,
    GUIDE_HEADING + '\nUse these guides as references when relevant.\n' + url,
    GUIDE_HEADING + '\nhttps://\nhttps://[invalid]\nhttps:///missing-host',
    GUIDE_HEADING + '\nftp://guides.example/warlock',
  ]) {
    assert.ok(!P.systemPrompt(context).includes(GUIDE_POLICY_OPENING), context);
  }

  const context = [character, '', GUIDE_HEADING, 'https://[invalid]', url].join('\r\n');
  assert.ok(P.systemPrompt(context).includes(GUIDE_POLICY_OPENING), 'one valid URL activates the policy');
});

test('splitSummary takes the last TL;DR block for the game chat and keeps the whole reply for the window', () => {
  const reply = 'Renamed the function.\n\nDetails:\n- foo.js\n- bar.js\n\n---\n**TL;DR:** Renamed doIt to run in foo.js and bar.js.\nTests pass.';
  const r = P.splitSummary(reply);
  assert.equal(r.summary, 'Renamed doIt to run in foo.js and bar.js.\nTests pass.');
  assert.equal(r.text, reply);
  assert.deepEqual(P.splitSummary('no marker here'), { text: 'no marker here', summary: '' });
  assert.deepEqual(P.splitSummary(''), { text: '', summary: '' });
  assert.deepEqual(P.splitSummary(undefined), { text: '', summary: '' });
  // Headings, missing colon, no bold, and a marker that is not at a line start.
  assert.equal(P.splitSummary('a\n## TL;DR\nsum').summary, 'sum');
  assert.equal(P.splitSummary('a\ntldr: sum').summary, 'sum');
  assert.equal(P.splitSummary('a TL;DR: inline\nmore').summary, '');
  assert.equal(P.splitSummary('first TL;DR: x\n\nbody\n\nTL;DR: last one').summary, 'last one');
  // The slot file carries the summary only when there is one.
  const lua = P.luaTable('AzerMind_SlotData', [{ chat: 'c', id: 1, status: 'done', text: 'body\nTL;DR: short', summary: 'short' }, { chat: 'c', id: 2, status: 'done', text: 'plain' }]);
  assert.ok(lua.includes('summary = "short"'));
  assert.equal((lua.match(/summary = /g) || []).length, 1);
});

test('the shipped primer exists, mentions the essentials, and stays small enough to send on every run', () => {
  const fs = require('fs');
  const primer = fs.readFileSync(path.join(__dirname, '..', 'docs', 'WOW-ADDON-PRIMER.md'), 'utf8');
  for (const must of ['## Interface: 16001', 'Gethe/wow-ui-source', 'InCombatLockdown', 'hooksecurefunc', 'SavedVariables', '/reload', '#showtooltip']) {
    assert.ok(primer.includes(must), 'primer mentions ' + must);
  }
  assert.ok(primer.length < 9000, `primer is ${primer.length} chars; keep it under 9000 (it costs tokens on every message)`);
});

test('jobsFromStrip handles several records per frame and older formats', () => {
  const a = ['s', 'c1', '3', '', '', 'A', 'first'].join('\x1F');
  const b = ['s', 'c2', '4', 'C:\\x', 'n', 'second'].join('\x1F'); // no-name format
  const c = ['s', 'C:\\y', '', 'third'].join('\x1F'); // pre-chat format
  const jobs = P.jobsFromStrip(9, [a, b, c].join('\x1E'));
  assert.deepEqual(jobs.map(j => [j.id, j.chat, j.text, j.newSession]), [[3, 'c1', 'first', false], [4, 'c2', 'second', true], [9, '', 'third', false]]);
  assert.deepEqual(P.jobsFromStrip(1, 'garbage'), []);
  assert.deepEqual(P.jobsFromStrip(1, ['s', 'c', 'notanumber', '', '', '', 'x'].join('\x1F')), []);
});

test('parseOutbox decodes the SavedVariables fallback', () => {
  const hex = s => Buffer.from(s, 'utf8').toString('hex');
  const src = `AzerMindDB = {\n["outbox"] = {\n["id"] = 7,\n["session"] = "abc123",\n["chat"] = "c1",\n["text"] = "${hex('héllo')}",\n["cwd"] = "${hex('realms')}",\n["newSession"] = true,\n},\n["settings"] = {},\n}`;
  assert.deepEqual(P.parseOutbox(src), { id: 7, session: 'abc123', chat: 'c1', text: 'héllo', cwd: 'realms', newSession: true, via: 'reload' });
  const withAllow = src.replace('["newSession"]', `["allow"] = "${hex('WebSearch\x1fBash(git:*)')}",\n["newSession"]`);
  assert.deepEqual(P.parseOutbox(withAllow).allow, ['WebSearch', 'Bash(git:*)']);
  const withCtx = src.replace('["newSession"]', `["ctx"] = "${hex('Character: Testchar')}",\n["newSession"]`);
  assert.equal(P.parseOutbox(withCtx).ctx, 'Character: Testchar');
  const withAgent = src.replace('["newSession"]', '["agent"] = "codex",\n["newSession"]');
  assert.equal(P.parseOutbox(withAgent).agent, 'codex');
  assert.equal(P.parseOutbox(src).agent, undefined);
  assert.equal(P.parseOutbox('AzerMindDB = {}'), null);
  assert.equal(P.parseOutbox('["outbox"] = { ["text"] = "" }'), null);
});

test('resolveCwd: empty is the default, relative joins it, ~ is home, absolute wins', () => {
  const base = path.resolve('C:\\work\\proj');
  assert.equal(P.resolveCwd('', base), base);
  assert.equal(P.resolveCwd('  ', base), base);
  assert.equal(P.resolveCwd('realms', base), path.join(base, 'realms'));
  assert.equal(P.resolveCwd('./realms/', base), path.join(base, 'realms'));
  assert.equal(P.resolveCwd('../other', base), path.resolve(base, '..', 'other'));
  assert.equal(P.resolveCwd('~/x', base), path.join(os.homedir(), 'x'));
  assert.equal(P.resolveCwd('D:\\elsewhere', base), path.win32.normalize('D:\\elsewhere'));
  assert.ok(P.sameFolder('C:\\A\\b\\', 'c:/a/B'));
  assert.ok(!P.sameFolder('C:\\a', 'C:\\a\\b'));
});

test('ruleFor turns denials into prefix rules', () => {
  assert.equal(P.ruleFor({ tool_name: 'WebSearch' }), 'WebSearch');
  assert.equal(P.ruleFor({ tool_name: 'Bash', tool_input: { command: 'cargo build --release' } }), 'Bash(cargo:*)');
  assert.equal(P.ruleFor({ tool_name: 'Bash', tool_input: { command: '"C:\\weird path\\x.exe" arg' } }), 'Bash');
  assert.equal(P.ruleFor({}), 'Unknown');
});

test('describeToolUse gives one short line per tool call', () => {
  assert.equal(P.describeToolUse({ name: 'Bash', input: { command: 'npm test\nsecond line' } }), '$ npm test');
  assert.equal(P.describeToolUse({ name: 'Edit', input: { file_path: 'C:\\x\\player.gd' } }), 'edit player.gd');
  assert.equal(P.describeToolUse({ name: 'Mystery' }), 'Mystery');
});

test('handled ids are tracked per session token and capped', () => {
  const state = { lastId: 0, handled: {}, sessions: {} };
  const job = { session: 's1', id: 5 };
  assert.equal(P.alreadyHandled(state, job), false);
  P.markHandled(state, job, 1000);
  assert.equal(P.alreadyHandled(state, job), true);
  assert.equal(P.alreadyHandled(state, { session: 's2', id: 5 }), false);
  assert.equal(state.lastId, 5);
  assert.equal(state.seen.s1, 1000);
  for (let i = 1; i <= 1200; i++) P.markHandled(state, { session: 's1', id: i });
  assert.ok(Object.keys(state.handled.s1).length <= 1000);
  // Sessionless (inject / very old addon) jobs fall back to the high-water mark.
  assert.equal(P.alreadyHandled(state, { session: '', id: 3 }), true);
  assert.equal(P.alreadyHandled(state, { session: '', id: 5000 }), false);
});

test('pruneStale forgets session tokens not seen for a month', () => {
  const day = 24 * 3600 * 1000;
  const now = 100 * day;
  const state = { lastId: 0, handled: { old: { 1: 1 }, fresh: { 1: 1 }, unknown: { 1: 1 }, '': { 1: 1 } }, seen: { old: now - 40 * day, fresh: now - day } };
  const transcripts = { chats: {}, tokens: { old: now - 40 * day, fresh: now } };
  const removed = P.pruneStale(state, transcripts, now);
  assert.equal(removed, 2);
  assert.deepEqual(Object.keys(state.handled).sort(), ['', 'fresh', 'unknown']);
  assert.equal(state.seen.unknown, now); // grace period starts when first seen by the pruner
  assert.deepEqual(Object.keys(transcripts.tokens), ['fresh']);
});

test('slotNumber wraps and SILENT_WAV is a valid RIFF header', () => {
  assert.equal(P.slotNumber(1, 200), 1);
  assert.equal(P.slotNumber(200, 200), 200);
  assert.equal(P.slotNumber(201, 200), 1);
  assert.equal(P.SILENT_WAV.toString('ascii', 0, 4), 'RIFF');
  assert.equal(P.SILENT_WAV.readUInt32LE(4), P.SILENT_WAV.length - 8);
  assert.equal(P.chatKey({ session: 's', chat: 'c' }), 's:c');
  assert.equal(P.sessKey({ session: 's', chat: 'c' }), 'chat:c');
  assert.equal(P.sessKey({ session: 's', chat: '' }), 's:default');
});
