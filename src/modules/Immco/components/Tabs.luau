local typedefs = require("../typedefs")

local Text = require("./Text")
local Image = require("./Image")
local argon = require("@Argon")

local LEFT_MOUSE_BUTTON = 1

local function lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

return function(params: typedefs.TabsParams, dt: number): (string?, number, number)
	local window = params.engine_window
	local renderer = params.renderer
	local theme = params.theme

	local items = params.Items or {}

	local storage = params.RetainedStorage
	local id = params.id

	local orientation = params.Orientation or "horizontal"
	local variant = params.Variant or "filled"

	local textSize = params.TextSize or 14
	local tabHeight = params.TabHeight or 34
	local paddingX = params.PaddingX or 12

	local iconSize = params.IconSize or 16
	local iconGap = params.IconGap or 6

	local countGap = params.CountGap or 6
	local itemGap = params.Gap or 2

	local cornerRadius = params.CornerRadius or theme.ButtonCornerRadius or theme.CornerRadius or 6

	local font = argon:CreateFont(params.Font or theme.Font)

	local backgroundColor = params.BackgroundColor or theme.ThirdColor or theme.BgColor

	local activeColor = params.ActiveColor or theme.SecondaryColor

	local hoverColor = params.HoverColor or theme.AlternatingColor1 or theme.SecondaryColor

	local textColor = params.TextColor or theme.SecondaryTextColor

	local activeTextColor = params.ActiveTextColor or theme.TextColor

	local indicatorColor = params.IndicatorColor or theme.AccentColor

	local countColor = params.CountColor or theme.SecondaryTextColor

	local disabledColor = params.DisabledTextColor or theme.SecondaryTextColor

	local leftPressed = argon:IsMouseButtonPressed(LEFT_MOUSE_BUTTON)

	--
	-- State
	--

	local state

	if storage and id then
		storage[id] = storage[id] or {}
		state = storage[id]
	else
		state = {}
	end

	local firstEnabled

	for _, item in ipairs(items) do
		if item.Disabled ~= true then
			firstEnabled = item.Value
			break
		end
	end

	if state.selected == nil then
		state.selected = params.DefaultValue or firstEnabled
	end

	local selectedValue

	if params.Value ~= nil then
		selectedValue = params.Value
	elseif state.selected == false then
		selectedValue = nil
	else
		selectedValue = state.selected
	end

	-- Measure tabs

	local layout = {}

	local totalWidth = 0
	local totalHeight = 0

	for _, item in ipairs(items) do
		local text = item.Text or item.Value or ""

		local textWidth = argon:MeasureText(window, text, textSize, font)

		local contentWidth = textWidth

		if item.Icon then
			contentWidth += iconSize

			if text ~= "" then
				contentWidth += iconGap
			end
		end

		local countText

		if item.Count ~= nil then
			countText = tostring(item.Count)

			local countWidth = argon:MeasureText(window, countText, textSize - 2, font)

			contentWidth += countGap + countWidth
		end

		local width = item.Width or params.TabWidth or (contentWidth + paddingX * 2)

		local height = item.Height or tabHeight

		table.insert(layout, {
			item = item,

			width = width,
			height = height,

			textWidth = textWidth,
			contentWidth = contentWidth,

			countText = countText,
		})

		if orientation == "horizontal" then
			totalWidth += width

			if #layout > 1 then
				totalWidth += itemGap
			end

			totalHeight = math.max(totalHeight, height)
		else
			totalWidth = math.max(totalWidth, width)

			totalHeight += height

			if #layout > 1 then
				totalHeight += itemGap
			end
		end
	end

	if params.width then
		totalWidth = params.width
	end

	if params.height then
		totalHeight = params.height
	end

	--
	-- Background
	--

	if variant == "filled" then
		argon:Save(window)

		argon:ClipRoundRect(window, {
			x = params.x,
			y = params.y,
			width = totalWidth,
			height = totalHeight,
		}, cornerRadius, cornerRadius)

		argon:DrawRectangle(window, {
			x = params.x,
			y = params.y,
			width = totalWidth,
			height = totalHeight,
			Color = backgroundColor,
		})

		argon:Restore(window)
	end

	--
	-- Resolve positions
	--

	local cursorX = params.x
	local cursorY = params.y

	local activeRect = nil

	for _, info in ipairs(layout) do
		local item = info.item

		local rect

		if orientation == "horizontal" then
			rect = {
				x = cursorX,
				y = params.y,
				width = info.width,
				height = info.height,
			}

			cursorX += info.width + itemGap
		else
			rect = {
				x = params.x,
				y = cursorY,
				width = params.width or totalWidth,
				height = info.height,
			}

			cursorY += info.height + itemGap
		end

		info.rect = rect

		if item.Value == selectedValue then
			activeRect = rect
		end
	end

	--
	-- Animated active indicator
	--

	if activeRect then
		if not state.indicator then
			state.indicator = {
				x = activeRect.x,
				y = activeRect.y,
				width = activeRect.width,
				height = activeRect.height,
			}
		end

		local indicator = state.indicator

		if params.Animated ~= false then
			local speed = params.AnimationSpeed or 18
			local alpha = 1 - math.exp(-speed * dt)

			indicator.x = lerp(indicator.x, activeRect.x, alpha)
			indicator.y = lerp(indicator.y, activeRect.y, alpha)

			indicator.width = lerp(indicator.width, activeRect.width, alpha)

			indicator.height = lerp(indicator.height, activeRect.height, alpha)
		else
			indicator.x = activeRect.x
			indicator.y = activeRect.y
			indicator.width = activeRect.width
			indicator.height = activeRect.height
		end

		if variant == "filled" then
			local inset = params.ActiveInset or 2

			local rect = {
				x = indicator.x + inset,
				y = indicator.y + inset,

				width = math.max(0, indicator.width - inset * 2),

				height = math.max(0, indicator.height - inset * 2),
			}

			argon:Save(window)

			argon:ClipRoundRect(window, rect, math.max(0, cornerRadius - inset), math.max(0, cornerRadius - inset))

			argon:DrawRectangle(window, {
				x = rect.x,
				y = rect.y,
				width = rect.width,
				height = rect.height,
				Color = activeColor,
			})

			argon:Restore(window)
		elseif variant == "underline" then
			local thickness = params.IndicatorThickness or 2

			if orientation == "horizontal" then
				argon:DrawRectangle(window, {
					x = indicator.x,
					y = indicator.y + indicator.height - thickness,

					width = indicator.width,
					height = thickness,

					Color = indicatorColor,
				})
			else
				argon:DrawRectangle(window, {
					x = indicator.x,
					y = indicator.y,

					width = thickness,
					height = indicator.height,

					Color = indicatorColor,
				})
			end
		end
	end

	--
	-- Tabs
	--

	for _, info in ipairs(layout) do
		local item = info.item
		local rect = info.rect

		local disabled = item.Disabled == true
		local selected = item.Value == selectedValue

		local hovered = not disabled and renderer:isMouseInRect(rect)

		if hovered and not selected and variant == "filled" then
			local inset = params.ActiveInset or 2

			local hoverRect = {
				x = rect.x + inset,
				y = rect.y + inset,

				width = math.max(0, rect.width - inset * 2),

				height = math.max(0, rect.height - inset * 2),
			}

			argon:Save(window)

			argon:ClipRoundRect(window, hoverRect, math.max(0, cornerRadius - inset), math.max(0, cornerRadius - inset))

			argon:DrawRectangle(window, {
				x = hoverRect.x,
				y = hoverRect.y,
				width = hoverRect.width,
				height = hoverRect.height,
				Color = hoverColor,
			})

			argon:Restore(window)
		end

		if hovered and leftPressed then
			local newValue = item.Value

			if params.Toggleable and selected then
				newValue = nil
			end

			selectedValue = newValue

			if params.Value == nil then
				if newValue == nil then
					state.selected = false
				else
					state.selected = newValue
				end
			end

			if params.OnChange then
				params.OnChange(newValue)
			end
		end

		--
		-- Content positioning
		--

		local contentX = rect.x + (rect.width - info.contentWidth) / 2

		local textHeight = argon:GetFontLineHeight(textSize, font)

		local textAscent = argon:GetFontAscent(textSize, font)

		local baselineY = rect.y + (rect.height - textHeight) / 2 + textAscent

		--
		-- Icon
		--

		if item.Icon then
			Image({
				x = contentX,

				y = rect.y + (rect.height - iconSize) / 2,

				width = iconSize,
				height = iconSize,

				Image = item.Icon,

				theme = theme,
				engine_window = window,
			}, dt)

			contentX += iconSize + iconGap
		end

		--
		-- Label
		--

		local itemTextColor

		if disabled then
			itemTextColor = disabledColor
		elseif selected then
			itemTextColor = activeTextColor
		else
			itemTextColor = textColor
		end

		Text({
			x = contentX,
			y = baselineY,

			text = item.Text or item.Value,

			TextSize = textSize,
			Font = font,

			Color = itemTextColor,

			theme = theme,
			engine_window = window,
		}, dt)

		contentX += info.textWidth

		--
		-- Count
		--

		if info.countText then
			contentX += countGap

			Text({
				x = contentX,
				y = baselineY,

				text = info.countText,

				TextSize = textSize - 2,
				Font = font,

				Color = item.CountColor or countColor,

				theme = theme,
				engine_window = window,
			}, dt)
		end
	end

	--
	-- Selected tab content
	--

	if params.RenderContent ~= false then
		local selectedItem

		for _, item in ipairs(items) do
			if item.Value == selectedValue then
				selectedItem = item
				break
			end
		end

		if selectedItem and selectedItem.Content then
			local contentGap = params.ContentGap or 8

			local contentRect

			if orientation == "horizontal" then
				contentRect = {
					x = params.x,
					y = params.y + totalHeight + contentGap,

					width = params.ContentWidth or totalWidth,

					height = params.ContentHeight or 0,
				}
			else
				contentRect = {
					x = params.x + totalWidth + contentGap,
					y = params.y,

					width = params.ContentWidth or 0,
					height = params.ContentHeight or totalHeight,
				}
			end

			selectedItem.Content({
				x = contentRect.x,
				y = contentRect.y,

				width = contentRect.width,
				height = contentRect.height,

				window = window,
				renderer = renderer,

				theme = theme,

				Value = selectedValue,
				Item = selectedItem,
			}, dt)
		end
	end

	return selectedValue, totalWidth, totalHeight
end
