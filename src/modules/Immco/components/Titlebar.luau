local typedefs = require("../typedefs")
local Rectangle = require("./Rectangle")
local Text = require("./Text")
local argon = require("@Argon")

local TAB_HEIGHT = 22
local TAB_SPACING = 4
local TAB_Y_OFFSET = 3
local TAB_PADDING_X = 10
local ACCENT_HEIGHT = 2
local TEXT_SIZE = 13

return function(params: typedefs.WidgetParams, dt: number)
	local window = params.engine_window
	local theme = params.theme
	local cornerRadius = theme.CornerRadius
	local font = argon:CreateFont(theme.Font)

	Rectangle({
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
		Color = params.Color,
		theme = theme,
		engine_window = window,
	}, dt)

	local tabs = params.tabs or { { title = params.title or "Titlebar" } }
	local activeIndex = params.activeTab or 1

	local textHeight = argon:GetFontLineHeight(TEXT_SIZE, font)
	local textAscent = argon:GetFontAscent(TEXT_SIZE, font)

	local tabX = params.x + 5

	for i, tab in ipairs(tabs) do
		local isActive = i == activeIndex
		local title = tab.title or "Tab"
		local textWidth = argon:MeasureText(window, title, TEXT_SIZE, font)
		local tabWidth = textWidth + TAB_PADDING_X * 2
		local tabY = params.y + TAB_Y_OFFSET

		argon:Save(window)

		argon:ClipRoundRect(window, {
			x = tabX,
			y = tabY,
			width = tabWidth,
			height = TAB_HEIGHT,
		}, cornerRadius, cornerRadius)

		Rectangle({
			x = tabX,
			y = tabY,
			width = tabWidth,
			height = TAB_HEIGHT,
			Color = isActive and theme.ThirdColor or theme.SecondColor,
			theme = theme,
			engine_window = window,
		}, dt)

		argon:Restore(window)

		local textX = tabX + TAB_PADDING_X
		local textY = tabY + (TAB_HEIGHT - textHeight) / 2 + textAscent

		Text({
			x = textX,
			y = textY,
			TextSize = TEXT_SIZE,
			theme = theme,
			Font = font,
			text = title,
			Color = isActive and theme.TextColor or theme.SecondaryTextColor,
			engine_window = window,
		}, dt)

		if isActive then
			Rectangle({
				x = tabX,
				y = params.y + params.height - ACCENT_HEIGHT,
				width = tabWidth,
				height = ACCENT_HEIGHT,
				Color = theme.AccentColor,
				theme = theme,
				engine_window = window,
			}, dt)
		end

		tabX += tabWidth + TAB_SPACING
	end
end
