-- description: "Creates an anchor layout for UI elements."
local Vector2 = require("@Vector2")
local UILayout = require("@UILayout")

-- UIAnchorLayout: each child declares its own anchor constraints via
-- a UIAnchor modifier child, similar to CSS absolute positioning with
-- top/right/bottom/left/center anchoring
--
-- UIAnchor properties (set on a child of the element you want to anchor):
--   AnchorTop    = UDim  -- distance from parent top edge (nil = unconstrained)
--   AnchorBottom = UDim  -- distance from parent bottom edge (nil = unconstrained)
--   AnchorLeft   = UDim  -- distance from parent left edge (nil = unconstrained)
--   AnchorRight  = UDim  -- distance from parent right edge (nil = unconstrained)
--   CenterX      = bool  -- horizontally center (overrides Left/Right)
--   CenterY      = bool  -- vertically center (overrides Top/Bottom)
--
-- When both opposite edges are constrained (e.g. AnchorLeft + AnchorRight),
-- the child is stretched to fill between them and its Size.X is ignored.
-- When only one edge is constrained, the child keeps its own Size and
-- is pinned to that edge

local propTable = {
	Name = "UIAnchorLayout",
	Enabled = true,

	render = function(surface, object)
		if not object.Enabled then
			return
		end
		local parent = object.Parent
		if not parent then
			return
		end

		local parentSize = UILayout.GetAbsoluteSize(parent, surface)

		local totalPaddingX, paddingRight, totalPaddingY, paddingBottom = UILayout.GetPadding(parent, parentSize)
		local effectiveWidth = math.max(0, parentSize.X - totalPaddingX - paddingRight)
		local effectiveHeight = math.max(0, parentSize.Y - totalPaddingY - paddingBottom)
		local effectiveSize = Vector2.new(effectiveWidth, effectiveHeight)

		local function resolveUDim(udim, axis)
			if not udim then
				return nil
			end
			local scale = axis == "x" and effectiveWidth or effectiveHeight
			return udim.Scale * scale + udim.Offset
		end

		for _, child in ipairs(parent:GetChildren()) do
			if not child.Visible or child == object or child.ClassName == "UIPadding" then
				continue
			end

			local anchor = child:FindFirstChildOfClass("UIAnchor")
			if not anchor then
				continue
			end

			rawset(child, "_LayoutControlled", true)

			local childSize = UILayout.GetSize(child, effectiveSize)
			local posX, posY, sizeX, sizeY

			local left = resolveUDim(anchor.AnchorLeft, "x")
			local right = resolveUDim(anchor.AnchorRight, "x")
			local centerX = anchor.CenterX

			if centerX then
				sizeX = childSize.X
				posX = totalPaddingX + (effectiveWidth - sizeX) * 0.5
			elseif left ~= nil and right ~= nil then
				posX = totalPaddingX + left
				sizeX = math.max(0, effectiveWidth - left - right)
			elseif left ~= nil then
				posX = totalPaddingX + left
				sizeX = childSize.X
			elseif right ~= nil then
				sizeX = childSize.X
				posX = totalPaddingX + effectiveWidth - right - sizeX
			else
				posX = totalPaddingX + child.Position.X.Scale * effectiveWidth + child.Position.X.Offset
				sizeX = childSize.X
			end

			local top = resolveUDim(anchor.AnchorTop, "y")
			local bottom = resolveUDim(anchor.AnchorBottom, "y")
			local centerY = anchor.CenterY

			if centerY then
				sizeY = childSize.Y
				posY = totalPaddingY + (effectiveHeight - sizeY) * 0.5
			elseif top ~= nil and bottom ~= nil then
				posY = totalPaddingY + top
				sizeY = math.max(0, effectiveHeight - top - bottom)
			elseif top ~= nil then
				posY = totalPaddingY + top
				sizeY = childSize.Y
			elseif bottom ~= nil then
				sizeY = childSize.Y
				posY = totalPaddingY + effectiveHeight - bottom - sizeY
			else
				posY = totalPaddingY + child.Position.Y.Scale * effectiveHeight + child.Position.Y.Offset
				sizeY = childSize.Y
			end

			rawset(child, "_LayoutRelativePosition", Vector2.new(posX, posY))
			rawset(child, "_LayoutRelativeSize", Vector2.new(sizeX, sizeY))
		end
	end,
}

return {
	class = "UIAnchorLayout",
	render = propTable.render,
	callback = function(instance)
		instance:SetProperties(propTable)
		return instance
	end,
}
