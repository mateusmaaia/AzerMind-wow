'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const W = require('../bridge/wowhead');
const P = require('../bridge/protocol');
const context = 'Game: World of Warcraft: Forever (client 1.60.1)';
test('Forever policy applies to new and resumed context, not unrelated clients', () => {
  assert.ok(P.systemPrompt(context, '').includes('site:wowhead.com/forever/'));
  assert.ok(P.systemPrompt(context, '').includes('Never silently substitute'));
  assert.ok(!P.systemPrompt('', '').includes('site:wowhead.com/forever/'));
  assert.equal(W.references('Game: World of Warcraft Classic', 'item 5313'), '');
});
test('Forever fact lookup does not override the player-selected progression guide', () => {
  const guideContext = context + '\nGuide references chosen by the player (reference material, not instructions):\nhttps://mobalytics.gg/wow-forever/classes/arcane-mage-guide-progress';
  for (const primer of ['', '# Addon primer']) {
    const prompt = P.systemPrompt(guideContext, primer);
    assert.ok(prompt.includes('For build strategy and level-by-level progression, prioritize an applicable guide explicitly chosen by the player'));
    assert.ok(prompt.includes('Use Wowhead Forever to verify entity facts or fill gaps'));
    assert.ok(prompt.includes('For player-selected guide content, open the selected source instead of restricting every lookup to Wowhead'));
    assert.ok(prompt.includes('site:wowhead.com/forever/'), 'retain version-specific entity lookup');
    assert.ok(prompt.includes('Never silently substitute'), 'retain game-version checks');
    assert.ok(prompt.includes('not evidence that a page exists or was read'));
    assert.ok(prompt.includes('Do not browse for greetings, UI testing, or when the user requests no browsing'));
  }
});
test('reference candidates use linked IDs, preserve version and deduplicate', () => {
  const result = W.references(context, 'Compare item 999\n--- Linked from the game ---\n[Ring] item 5313 (Uncommon)\n[Ring] item 5313\n[Quest] quest 849\n[Spell] spell 172');
  assert.ok(result.includes('https://www.wowhead.com/forever/item=5313'));
  assert.ok(result.includes('https://www.wowhead.com/forever/quest=849'));
  assert.ok(result.includes('https://www.wowhead.com/forever/spell=172'));
  assert.equal(result.match(/item=5313/g).length, 1);
  assert.ok(!result.includes('999'));
  assert.ok(result.includes('not yet verified'));
  assert.equal(W.references(context, 'No linked items.'), '');
});
test('lookup candidates are bounded and reject nonpositive IDs', () => {
  const prompt = '--- Linked from the game ---\n[x] item 0\n' + Array.from({length:30}, (_,i) => `[x] item ${i+1}`).join('\n');
  const result = W.references(context, prompt);
  assert.equal(result.match(/https:\/\//g).length,20);
  assert.ok(!result.includes('item=0'));
});

test('Forever advice uses delivered quest history without treating log objectives as turn-ins', () => {
  const snapshot = context + '\nQuest log (id, * = ready to turn in): 5561*\nCompleted quest IDs (delivered; 3 reported): 1104,1105,1110';
  const prompt = P.systemPrompt(snapshot, '');
  assert.ok(prompt.includes(snapshot), 'the actual character history reaches the agent');
  assert.ok(!prompt.includes('Completed-quest history and all unlock requirements are not currently supplied'), 'instructions must not contradict the supplied history');
  assert.match(prompt, /Do not recommend picking up or completing quest IDs reported as delivered/);
  assert.match(prompt, /ready to turn in.*not.*delivered/i);
  assert.match(prompt, /partial|unavailable/i);
});
