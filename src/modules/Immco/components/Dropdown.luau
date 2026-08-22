local typedefs = require("../typedefs")
local Rectangle = require("./Rectangle")
local Text = require("./Text")
local argon = require("@Argon")

local LEFT_MOUSE_BUTTON = 1
local TEXT_SIZE = 13

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smoothTowards(current: number, target: number, speed: number, dt: number): number
	local t = 1 - math.exp(-speed * dt)
	return lerp(current, target, t)
end

local function optionText(option): string
	if type(option) == "table" then
		return option.Text or tostring(option.Value)
	end
	return tostring(option)
end

local function optionValue(option)
	if type(option) == "table" then
		return option.Value
	end
	return option
end

return function(params: typedefs.DropdownParams, dt: number): (number, boolean, any)
	local storage = params.RetainedStorage
	local id = params.id
	local renderer = params.renderer
	local window = params.window
	local theme = params.theme

	local options = params.Options or {}

	local field = storage[id]
	if not field then
		field = {
			open = false,
			openAmount = 0,
			selected = params.InitialSelected or 0,
			hoverIndex = 0,
		}
		storage[id] = field
	end

	if field.selected > #options then
		field.selected = 0
	end

	local font = argon:CreateFont(theme.Font)
	local textHeight = argon:GetFontLineHeight(TEXT_SIZE, font)
	local textAscent = argon:GetFontAscent(TEXT_SIZE, font)

	local optionHeight = params.OptionHeight or params.height
	local maxVisible = params.MaxVisibleOptions or 5
	local visibleCount = math.min(#options, maxVisible)
	local listHeight = visibleCount * optionHeight
	local listScrollable = #options > maxVisible

	local headerRect = {
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
	}

	local listRect = {
		x = params.x,
		y = params.y + params.height,
		width = params.DropdownWidth or params.width,
		height = listHeight,
	}

	local mousePos = argon:GetMousePosition()
	local hoveredHeader = renderer:isMouseInRect(headerRect)
	local hoveredList = field.openAmount > 0.01 and renderer:isMouseInRect(listRect)

	local leftPressed = argon:IsMouseButtonPressed(LEFT_MOUSE_BUTTON)

	if leftPressed then
		if hoveredHeader then
			field.open = not field.open
		elseif field.open and not hoveredList then
			field.open = false
		end
	end

	field.hoverIndex = 0
	local listScrollY = field.listScrollY or 0
	if hoveredList then
		local localY = (mousePos.Y - listRect.y) + listScrollY
		local index = math.floor(localY / optionHeight) + 1
		if index >= 1 and index <= #options then
			field.hoverIndex = index
		end
	end

	if leftPressed and field.hoverIndex > 0 then
		local changed = field.selected ~= field.hoverIndex
		field.selected = field.hoverIndex
		field.open = false
		if changed and params.OnChanged then
			params.OnChanged(field.selected, optionValue(options[field.selected]))
		end
	end

	if listScrollable and hoveredList then
		local wheelDelta = argon:GetMouseWheelMove()
		if wheelDelta ~= 0 then
			local maxScroll = math.max(0, (#options * optionHeight) - listHeight)
			field.listScrollY = math.clamp(listScrollY - wheelDelta * (params.ScrollSpeed or 40), 0, maxScroll)
		end
	end
	listScrollY = field.listScrollY or 0

	local openTarget = field.open and 1 or 0
	field.openAmount = smoothTowards(field.openAmount, openTarget, params.OpenLerpSpeed or 18, dt)
	if math.abs(field.openAmount - openTarget) < 0.01 then
		field.openAmount = openTarget
	end

	local cornerRadius = params.CornerRadius or theme.CornerRadius or 0

	Rectangle({
		x = headerRect.x,
		y = headerRect.y,
		width = headerRect.width,
		height = headerRect.height,
		Color = hoveredHeader and theme.SecondaryColor or theme.BgColor,
		theme = theme,
		engine_window = window,
	}, dt)

	Rectangle({
		x = headerRect.x,
		y = headerRect.y,
		width = headerRect.width,
		height = headerRect.height,
		Color = theme.SecondaryColor,
		theme = theme,
		engine_window = window,
		isOutline = true,
	}, dt)

	local selectedOption = field.selected > 0 and options[field.selected]
	local label = selectedOption and optionText(selectedOption) or (params.Placeholder or "Select...")

	Text({
		x = headerRect.x + (params.Padding or 8),
		y = headerRect.y + (headerRect.height - textHeight) / 2 + textAscent,
		TextSize = TEXT_SIZE,
		theme = theme,
		Font = font,
		text = label,
		Color = selectedOption and theme.TextColor or theme.SecondaryTextColor,
		engine_window = window,
	}, dt)

	local arrowGlyph = field.open and "\u{25B4}" or "\u{25BE}"
	local arrowWidth = argon:MeasureText(window, arrowGlyph, TEXT_SIZE, font)

	Text({
		x = headerRect.x + headerRect.width - (params.Padding or 8) - arrowWidth,
		y = headerRect.y + (headerRect.height - textHeight) / 2 + textAscent,
		TextSize = TEXT_SIZE,
		theme = theme,
		Font = font,
		text = arrowGlyph,
		Color = field.open and theme.AccentColor or theme.TextColor,
		engine_window = window,
	}, dt)

	if field.openAmount > 0.01 then
		local animatedHeight = listHeight * field.openAmount

		argon:Save(window)
		argon:ClipRoundRect(window, {
			x = listRect.x,
			y = listRect.y,
			width = listRect.width,
			height = animatedHeight,
		}, cornerRadius, cornerRadius)

		Rectangle({
			x = listRect.x,
			y = listRect.y,
			width = listRect.width,
			height = animatedHeight,
			Color = theme.ThirdColor,
			theme = theme,
			engine_window = window,
		}, dt)

		for index, option in ipairs(options) do
			local optionY = listRect.y + (index - 1) * optionHeight - listScrollY
			if optionY + optionHeight >= listRect.y and optionY <= listRect.y + animatedHeight then
				if index == field.selected then
					Rectangle({
						x = listRect.x,
						y = optionY,
						width = listRect.width,
						height = optionHeight,
						Color = theme.AccentColor,
						theme = theme,
						engine_window = window,
					}, dt)
				elseif index == field.hoverIndex then
					Rectangle({
						x = listRect.x,
						y = optionY,
						width = listRect.width,
						height = optionHeight,
						Color = theme.SecondaryColor,
						theme = theme,
						engine_window = window,
					}, dt)
				end

				Text({
					x = listRect.x + (params.Padding or 8),
					y = optionY + (optionHeight - textHeight) / 2 + textAscent,
					TextSize = TEXT_SIZE,
					theme = theme,
					Font = font,
					text = optionText(option),
					Color = theme.TextColor,
					engine_window = window,
				}, dt)
			end
		end

		argon:Restore(window)
	end

	return field.selected, field.open, selectedOption and optionValue(selectedOption) or nil
end
