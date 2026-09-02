local typedefs = require("../typedefs")

local Rectangle = require("./Rectangle")
local Tabs = require("./Tabs")

local TAB_HEIGHT = 22
local TAB_SPACING = 4
local TAB_Y_OFFSET = 3
local TAB_PADDING_X = 10
local ACCENT_HEIGHT = 2
local TEXT_SIZE = 13

return function(params: typedefs.WidgetParams, dt: number)
	local window = params.engine_window
	local theme = params.theme
	local renderer = params.renderer

	Rectangle({
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,

		Color = params.Color,

		theme = theme,
		engine_window = window,
	}, dt)

	local tabs = params.tabs or {
		{
			title = params.title or "Titlebar",
		},
	}

	local activeIndex = params.activeTab or 1

	local items = {}

	for i, tab in ipairs(tabs) do
		table.insert(items, {
			Value = tostring(i),
			Text = tab.title or "Tab",

			Disabled = tab.Disabled,

			Icon = tab.Icon,
			Count = tab.Count,
		})
	end

	Tabs({
		x = params.x + 5,
		y = params.y + TAB_Y_OFFSET,

		engine_window = window,
		renderer = renderer,
		theme = theme,

		Items = items,

		Value = tostring(activeIndex),

		Variant = "filled",
		Orientation = "horizontal",

		TabHeight = TAB_HEIGHT,
		PaddingX = TAB_PADDING_X,
		Gap = TAB_SPACING,

		TextSize = TEXT_SIZE,

		TextColor = theme.SecondaryTextColor,
		ActiveTextColor = theme.TextColor,

		IndicatorColor = theme.AccentColor,
		IndicatorThickness = ACCENT_HEIGHT,

		Animated = true,
		AnimationSpeed = 20,

		RenderContent = false,

		OnChange = function(value)
			local index = tonumber(value)

			if not index then
				return
			end

			local tab = tabs[index]

			if tab and params.OnTabChanged then
				params.OnTabChanged(index, tab)
			end
		end,
	}, dt)
end
