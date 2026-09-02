-- description: "A layout class that affects the positioning of gui objects."
local UDim = require("@UDim")
local Vector2 = require("@Vector2")
local Enum = require("@EnumMap")
local UILayout = require("@UILayout")

local propTable = {
	Name = "UIPageLayout",
	BaseClass = "Kinemium.uimodifier",
	Enabled = true,

	Animated = true,
	Circular = false,
	EasingDirection = 1, -- Enum
	EasingStyle = 1, -- Enum
	FillDirection = Enum.FillDirection.Horizontal,
	GamepadInputEnabled = true,
	HorizontalAlignment = 1, -- Enum
	Padding = UDim.new(0, 0),
	ScrollWheelInputEnabled = true,
	SortOrder = Enum.SortOrder.LayoutOrder,
	TouchInputEnabled = true,
	TweenTime = 1,
	VerticalAlignment = 1, -- Enum
	CurrentPage = 1,

	render = function(surface, object)
		if object.Enabled == false or not object.Parent then
			return
		end

		local parent = object.Parent
		local parentSize = UILayout.GetAbsoluteSize(parent, surface)
		local left, right, top, bottom = UILayout.GetPadding(parent, parentSize)
		local contentSize =
			Vector2.new(math.max(0, parentSize.X - left - right), math.max(0, parentSize.Y - top - bottom))
		local horizontal = object.FillDirection == Enum.FillDirection.Horizontal
		local gap = object.Padding.Scale * (horizontal and contentSize.X or contentSize.Y) + object.Padding.Offset
		local pages = {}
		for _, child in ipairs(parent:GetChildren()) do
			if child ~= object and child.Visible and child.BaseClass == "GuiObject" then
				pages[#pages + 1] = child
			end
		end
		if object.SortOrder == Enum.SortOrder.LayoutOrder then
			table.sort(pages, function(a, b)
				return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
			end)
		end

		local current = math.clamp(math.floor(object.CurrentPage or 1), 1, math.max(1, #pages))
		for index, page in ipairs(pages) do
			local delta = index - current
			local x = left + (horizontal and delta * (contentSize.X + gap) or 0)
			local y = top + (horizontal and 0 or delta * (contentSize.Y + gap))
			rawset(page, "_LayoutControlled", true)
			rawset(page, "_LayoutRelativePosition", Vector2.new(x, y))
			rawset(page, "_LayoutRelativeSize", contentSize)
		end
	end,
}

return {
	class = "UIPageLayout",
	render = propTable.render,
	callback = function(instance)
		instance:SetProperties(propTable)
		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
