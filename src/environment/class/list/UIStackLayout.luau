-- description: "A modifier class that stacks GUI elements in a vertical or horizontal layout."
local Vector2 = require("@Vector2")
local Enum = require("@EnumMap")
local UDim2 = require("@UDim2")
local UILayout = require("@UILayout")

local propTable = {
	Name = "UIStackLayout",
	Enabled = true,

	-- "ZIndex" stacks by ZIndex order, "LayoutOrder" stacks by LayoutOrder
	SortOrder = Enum.SortOrder.LayoutOrder,

	-- Which corner/edge children anchor to when stacking
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Top,

	-- If true, each child fills the full parent size (classic overlay stack)
	-- If false, children keep their own size and are just layered at the alignment point
	FillParent = true,

	-- Offset applied between each layer (creates a "fanned" effect when > 0)
	LayerOffset = UDim2.new(0, 0, 0, 0),

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

		local offsetX = object.LayerOffset.X.Scale * effectiveSize.X + object.LayerOffset.X.Offset
		local offsetY = object.LayerOffset.Y.Scale * effectiveSize.Y + object.LayerOffset.Y.Offset

		local children = {}
		for _, child in ipairs(parent:GetChildren()) do
			if child.Visible and child ~= object and child.ClassName ~= "UIPadding" then
				table.insert(children, child)
			end
		end

		if object.SortOrder == Enum.SortOrder.LayoutOrder and #children > 1 then
			table.sort(children, function(a, b)
				return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
			end)
		elseif #children > 1 then
			-- ZIndex sort
			table.sort(children, function(a, b)
				return (a.ZIndex or 0) < (b.ZIndex or 0)
			end)
		end

		for i, child in ipairs(children) do
			rawset(child, "_LayoutControlled", true)

			local layerX = totalPaddingX + offsetX * (i - 1)
			local layerY = totalPaddingY + offsetY * (i - 1)

			if object.FillParent then
				-- Each layer fills the full effective area (offset aside)
				rawset(child, "_LayoutRelativePosition", Vector2.new(layerX, layerY))
				rawset(child, "_LayoutRelativeSize", Vector2.new(
					math.max(0, effectiveWidth - offsetX * (i - 1)),
					math.max(0, effectiveHeight - offsetY * (i - 1))
				))
			else
				-- Position child at the alignment point without resizing it
				local childSize = UILayout.GetSize(child, effectiveSize)
				rawset(child, "_LayoutRelativeSize", childSize)

				local x = layerX
				if object.HorizontalAlignment == Enum.HorizontalAlignment.Center then
					x = totalPaddingX + (effectiveWidth - childSize.X) * 0.5 + offsetX * (i - 1)
				elseif object.HorizontalAlignment == Enum.HorizontalAlignment.Right then
					x = totalPaddingX + effectiveWidth - childSize.X + offsetX * (i - 1)
				end

				local y = layerY
				if object.VerticalAlignment == Enum.VerticalAlignment.Center then
					y = totalPaddingY + (effectiveHeight - childSize.Y) * 0.5 + offsetY * (i - 1)
				elseif object.VerticalAlignment == Enum.VerticalAlignment.Bottom then
					y = totalPaddingY + effectiveHeight - childSize.Y + offsetY * (i - 1)
				end

				rawset(child, "_LayoutRelativePosition", Vector2.new(x, y))
			end
		end
	end,
}

return {
	class = "UIStackLayout",
	render = propTable.render,
	callback = function(instance)
		instance:SetProperties(propTable)
		return instance
	end,
}
