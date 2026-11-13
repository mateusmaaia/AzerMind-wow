'use strict';

// Production art contract. Sources are PNG; WoW textures are uncompressed RGBA TGA.
const assets = [];
function add(id, phase, size, mode, usage) {
  assets.push({id, phase, width:size, height:size, mode, usage,
    source:`art/grimoire/sources/${id}.png`,
    runtime:`addon/AzerMind/Art/Grimoire/${id}.tga`});
}
add('emblem',2,256,'fixed','Approved crystal and grimoire; preserve original design');
add('leather',2,256,'tile','Window, header and sidebar: espresso leather, no lighting gradient');
add('parchment',2,256,'tile','Transcript and composer: quiet ivory paper without baked text');
add('parchment-warm',2,256,'tile','Assistant card variation; subtle warm paper');
for (const [id,usage] of Object.entries({
  'frame-window':'Outer bronze corners and edges',
  'frame-panel':'Sidebar and reading-area border',
  'frame-card':'User, AI and system message cards',
  'frame-input':'Composer border; focus uses tinted overlay',
  'frame-popup':'Menus, tooltips, attachments and authorization notices',
  'button-secondary':'Toolbar, config, menus and clear draft',
  'button-primary':'New conversation, connect/send/stop; burgundy inset',
  'conversation-selection':'Selected conversation inset and rail'
})) add(id,3,128,'nine-slice',usage);
add('divider',3,128,'horizontal','Section dividers; end caps fixed');
add('scroll-track',3,32,'vertical','Three scrollbars share this track');
add('scroll-thumb',3,64,'nine-slice','Three scrollbars share this thumb');
add('resize-grip',3,32,'fixed','Bottom-right sizing affordance');
for (const id of ['items','quests','instances','character','settings','plus','more','delete','copy','resend','send','stop','connect','clear','minimize','reload','chevron-up','chevron-down','user','warning','sources']) {
  add(`icon-${id}`,3,32,'fixed',`Shared ${id} icon; no baked caption`);
}
for (const id of ['connected','connecting','disconnected','unread']) add(`gem-${id}`,3,32,'fixed',`${id} indicator, always accompanied by text or tooltip`);
add('button-paper',3,128,'nine-slice','Illustrated parchment button for new chat and unselected conversations');
for (const a of assets) {
  if(['frame-window','frame-panel','frame-popup'].includes(a.id)) {
    Object.assign(a,{width:1024,height:1024,slices:{left:192,right:192,top:192,bottom:192},authoring:'imagegen'});
  }
  if(['button-paper','button-primary','button-secondary','conversation-selection','frame-card','frame-input'].includes(a.id)) {
    Object.assign(a,{width:512,height:256,slices:{left:64,right:64,top:64,bottom:64},authoring:'imagegen'});
  }
}
// Dedicated repeating rails preserve stitch size; a cropped atlas cannot repeat a subregion.
for(const prefix of ['frame-window','button-paper','button-primary','button-secondary','frame-card']) {
  for(const side of ['top','bottom','left','right']) {
    add(`${prefix}-${side}`,3,256,(side==='top'||side==='bottom')?'horizontal':'vertical',`Repeating illustrated ${side} rail of ${prefix}`);
    Object.assign(assets.at(-1),{authoring:'imagegen',derivedFrom:prefix});
  }
}

// Preserve approved PixelLab masters when rebuilding procedural assets.
for (const [kind,job] of Object.entries({settings:'faab48d8-fcdd-4e19-9440-b8db1e352ee4',items:'82498f18-aa6b-4df8-9e20-1612efbeb641',quests:'955a4bce-780c-4ab4-be86-28d2b6fbd8f2',instances:'0cb8dc63-dddb-49cb-9ba4-2dd0cef4bd43',character:'3490a848-c2a9-4f21-ab94-b0dc7171fb38',user:'3490a848-c2a9-4f21-ab94-b0dc7171fb38',copy:'6ca02b29-2a56-4b35-9e63-9b908e1fb591',resend:'f75a4317-4961-481e-8dd8-20c9f4da808d',delete:'48a0c7dc-7f8b-461f-be42-bf51decd955e'})) {
  Object.assign(assets.find(a=>a.id===`icon-${kind}`),{authoring:'imagegen',provider:'pixellab',job});
}

module.exports = {
  version:1, theme:'Archivist Grimoire', assets,
  states:['normal','hover','pressed','disabled','selected','focus'],
  // Derived in Lua using overlays/tints; no duplicated AI generations for these states.
  derivedStates:true,
  sizes:[{name:'minimum',width:900,height:600},{name:'standard',width:1180,height:830},{name:'large',width:1600,height:1000}],
  slices:{left:16,right:16,top:16,bottom:16},
};
