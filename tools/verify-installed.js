'use strict';
// Read-only comparison: never print bridge credentials or modify the game.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
function verify(addonDir) {
  const differences = [];
  let checked = 0;
  const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  function files(dir, relative='') {
    return fs.readdirSync(dir,{withFileTypes:true}).flatMap(entry=>{
      const name=path.join(relative,entry.name);
      return entry.isDirectory()?files(path.join(dir,entry.name),name):[name];
    });
  }
  for (const folder of fs.readdirSync(path.join(root, 'addon'))) {
    if (!/^AzerMind(?:_Data(?:_[A-Za-z]+)?)?$/.test(folder)) continue;
    for (const name of files(path.join(root, 'addon', folder))) {
      if (!/\.(lua|toc|xml|tga|blp)$/.test(name) || name === 'Inbox.lua') continue;
      const source = path.join(root, 'addon', folder, name);
      const installed = path.join(addonDir, folder, name);
      checked++;
      if (!fs.existsSync(installed)) differences.push(`${folder}/${name}: missing`);
      else if (digest(source) !== digest(installed)) differences.push(`${folder}/${name}: outdated`);
    }
  }
  return { checked, differences };
}
module.exports = { verify };
if (require.main === module) {
  const addonDir = process.argv[2] || JSON.parse(fs.readFileSync(path.join(root, 'bridge', 'config.json'), 'utf8')).addonDir;
  if (!addonDir) throw Error('Pass the game Interface/AddOns directory.');
  const result = verify(addonDir);
  console.log(`Checked ${result.checked} addon files; ${result.differences.length} missing or outdated.`);
  for (const difference of result.differences) console.log(difference);
  if (result.differences.length) process.exitCode = 1;
  else console.log('Installed code and texture files match the project.');
}
