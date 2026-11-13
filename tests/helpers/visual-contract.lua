-- Explicit visibility contract, not a substitute for the WoW rasterizer.
function GR_AssertVisible(region,container)
 assert(region:IsVisible(),'hidden region or ancestor')
 local alpha=region:GetEffectiveAlpha()*(region.vertexColor and region.vertexColor[4] or 1)*(region.color and region.color[4] or 1)
 assert(alpha>0.05,'transparent region or ancestor')
 assert((region.scale or 1)==1,'scaled rendering needs in-game validation')
 assert(region.points and next(region.points),'missing anchor')
 for _,anchor in pairs(region.points) do assert(anchor.relative,'implicit or missing relative frame') end
 local bounds=GR_Bounds(region)
 assert(bounds.width>0 and bounds.height>0,'empty region')
 if container then
  local box=GR_Bounds(container)
  assert(bounds.left>=box.left and bounds.right<=box.right and bounds.bottom>=box.bottom and bounds.top<=box.top,'region escapes its control')
 end
 local descendant,ancestor=region,region.parent
 while ancestor do
  assert((ancestor.scale or 1)==1,'scaled rendering needs in-game validation')
  if ancestor.clipsChildren or (ancestor.kind=='ScrollFrame' and ancestor.scrollChild==descendant) then
   local clip=GR_Bounds(ancestor)
   assert(bounds.left<clip.right and bounds.right>clip.left and bounds.bottom<clip.top and bounds.top>clip.bottom,'region fully clipped')
  end
  descendant=ancestor;ancestor=ancestor.parent
 end
end
function GR_AssertMessageAction(button)
 local glyph=button.actionIcon
 GR_AssertVisible(button)
 GR_AssertVisible(glyph,button)
 assert(glyph.parent==button,'message icon must be a direct button texture')
 assert(glyph.drawLayer=='OVERLAY' and glyph.drawSublevel==7,'icon below foreground')
 assert(type(glyph.texture)=='string' and glyph.texture:match('%.tga$'),'missing icon image')
end
