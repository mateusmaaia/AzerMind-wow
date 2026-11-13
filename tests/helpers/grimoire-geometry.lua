-- Resolve the actual anchor graph recorded from the Lua UI, not a second layout.
local function Factor(point, axis)
	if axis=="x" then
		if point:find("LEFT") then return 0 elseif point:find("RIGHT") then return 1 else return 0.5 end
	end
	if point:find("BOTTOM") then return 0 elseif point:find("TOP") then return 1 else return 0.5 end
end
function GR_Bounds(region, visiting)
	if region==UIParent then return {left=0,bottom=0,width=UIParent:GetWidth(),height=UIParent:GetHeight()} end
	visiting=visiting or {}; assert(not visiting[region],"Anchor cycle")
	visiting[region]=true
	local function Axis(axis)
		local size=axis=="x" and region.width or region.height
		local positions={}
		for point,anchor in pairs(region.points or {}) do
			if anchor.relative then
				local bounds=GR_Bounds(anchor.relative,visiting)
				local origin=axis=="x" and bounds.left or bounds.bottom
				local extent=axis=="x" and bounds.width or bounds.height
				positions[#positions+1]={factor=Factor(point,axis),position=origin+extent*Factor(anchor.relativePoint,axis)+(axis=="x" and anchor.x or anchor.y)}
			end
		end
		for i=1,#positions do for j=i+1,#positions do
				if positions[i].factor~=positions[j].factor then size=(positions[j].position-positions[i].position)/(positions[j].factor-positions[i].factor) end
		end end
		size=size or (axis=="x" and 400 or 300)
		return positions[1] and positions[1].position-positions[1].factor*size or 0,size
	end
	local left,width=Axis("x"); local bottom,height=Axis("y")
	-- The client positions the scroll child at the viewport origin, then offsets it.
	if region.parent and region.parent.scrollChild==region and not next(region.points or {}) then
	 local viewport=GR_Bounds(region.parent,visiting)
	 left=viewport.left;bottom=viewport.top-height+(region.parent.verticalScroll or 0)
	end
	visiting[region]=nil
	return {left=left,bottom=bottom,width=width,height=height,right=left+width,top=bottom+height}
end
