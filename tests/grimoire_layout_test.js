'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const boot=require('./helpers/grimoire-vm');
for(const [width,height] of [[900,600],[1180,830],[1600,1000]]) {
  test(`real anchor graph keeps composer, toolbar and protected corners within ${width}x${height}`,t=>{
    const vm=boot(t);
    vm.run(fs.readFileSync(path.join(__dirname,'helpers/grimoire-geometry.lua'),'utf8'));
    vm.run(`
      AzerMindFrame:SetSize(${width},${height})
      for _,fn in ipairs(AzerMindFrame.hooks.OnSizeChanged or {}) do fn(AzerMindFrame,${width},${height}) end
      local frame=GR_Bounds(AzerMindFrame)
      local field=GR_Bounds(AzerMindInputScroll.parent)
      assert(field.left>=frame.left and field.right<=frame.right,"composer horizontal overflow")
      assert(field.bottom>=frame.bottom and field.top<frame.top,"composer vertical overflow")
      TOOLBARS={}
      for _,f in ipairs(STUB.frames) do
        if f.text=="Items" or f.text=="Quests" or f.text=="Dungeons & Raids" or (f.text and f.text:find("Context:",1,true)==1) then
          local b=GR_Bounds(f)
          assert(b.left>=frame.left and b.right<=frame.right,"toolbar overflow: "..f.text)
          assert(b.bottom>=field.top,"toolbar overlaps composer")
          for _,other in ipairs(TOOLBARS) do
            local o=GR_Bounds(other)
            assert(b.right<=o.left or b.left>=o.right or b.top<=o.bottom or b.bottom>=o.top,"toolbar controls overlap")
          end
          TOOLBARS[#TOOLBARS+1]=f
        end
      end
      local chat=GR_Bounds(AzerMindScroll)
      for _,f in ipairs(TOOLBARS) do assert(chat.bottom>=GR_Bounds(f).top,"chat overlaps toolbar") end
      assert(#TOOLBARS==4,"missing toolbar controls")
      for _,button in ipairs(STUB.frames) do
        if button.actionArt or button.text=="Clear draft" then
          local b=GR_Bounds(button)
          assert(b.left>=field.right and b.right<=frame.right,"action overlaps field or window edge")
          assert(b.bottom>=frame.bottom and b.top<=field.top,"action vertical overflow")
        end
      end
      CORNER=AzerMindFrame.grimoireFrame.parts[1]
    `);
    assert.equal(vm.num('CORNER.width'),32);
    assert.equal(vm.num('CORNER.height'),32);
    assert.equal(vm.num('CORNER.texCoords[2]'),192/1024);
    assert.match(vm.value('AzerMindFrame.grimoireFrame.parts[2].texture'),/frame-window-top\.tga$/);
    assert.equal(vm.num('AzerMindFrame.grimoireFrame.parts[2].texCoords[2]'),(width-64)/(256*32/192));
    assert.equal(vm.num('AzerMindFrame.grimoireFrame.parts[4].texCoords[4]'),(height-64)/(256*32/192));
    assert.equal(vm.num('AzerMindFrame.grimoireMaterial.texCoords[2]'),(width-8)/256);
    assert.equal(vm.num('AzerMindFrame.resizeBounds[1]'),900);
    assert.ok(vm.num('AzerMindFrame.resizeBounds[3]')>=1600);
  });
}
test('rerender and repeated resizing reuse frame parts and hooks',t=>{
  const vm=boot(t);
  vm.run(`
    local chat=AzerMindDB.chats[1];chat.history={{role="assistant",text="A long answer"}}
    AzerMind.Render(); BUBBLE=AzerMindContent.children[1]
    COUNT=#BUBBLE.children; HOOKS=#AzerMindFrame.hooks.OnSizeChanged
    for i=1,10 do AzerMind.Render(); AzerMindTheme.Frame(AzerMindFrame,"frame-window",32) end
  `);
  assert.equal(vm.num('#BUBBLE.children'),vm.num('COUNT'));
  assert.equal(vm.num('#AzerMindFrame.hooks.OnSizeChanged'),vm.num('HOOKS'));
});

test('screenshot regressions: scroll gutters clear borders and compact labels have room',t=>{
  const vm=boot(t);
  vm.run(fs.readFileSync(path.join(__dirname,'helpers/grimoire-geometry.lua'),'utf8'));
  vm.run(`
    for _,size in ipairs({{900,600},{1180,830},{1600,1000}}) do
      AzerMindFrame:SetSize(size[1],size[2])
      for _,fn in ipairs(AzerMindFrame.hooks.OnSizeChanged or {}) do fn(AzerMindFrame,size[1],size[2]) end
      local outer=GR_Bounds(AzerMindFrame)
      for _,scroll in ipairs({AzerMindScroll,AzerMindInputScroll,AzerMindConversationScroll}) do
        local viewport=GR_Bounds(scroll)
        local bar=GR_Bounds(scroll.ScrollBar)
        local container=GR_Bounds(scroll.parent)
        assert(bar.left>=viewport.right+6,'scrollbar touches content')
        assert(bar.right<=container.right-8,'scrollbar touches container border: '..scroll:GetName()..' '..bar.right..' / '..container.right)
        local limit=scroll==AzerMindInputScroll and container or viewport
        assert(bar.top<=limit.top and bar.bottom>=limit.bottom,'scrollbar escapes its container')
      end
      for _,button in ipairs(STUB.frames) do
        if button.text=='Config' then
          local bounds=GR_Bounds(button)
          assert(bounds.top<=outer.top-16,'Config overlaps decorative corner')
          assert(button:GetWidth()>=90 and button:GetHeight()>=30,'Config label cramped')
        elseif button.text=='Items' or button.text=='Quests' then
          assert(button.caption:GetWidth()>=46,'toolbar label truncated')
        end
      end
    end
  `);
});

