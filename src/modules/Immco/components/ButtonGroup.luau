local typedefs = require("../typedefs")

local Text = require("./Text")
local Image = require("./Image")
local argon = require("@Argon")

local LEFT_MOUSE_BUTTON = 1

return function(params: typedefs.ButtonGroupParams, dt: number): (number, number)
	local window = params.engine_window
	local renderer = params.renderer
	local theme = params.theme
	local items = params.Items

	local orientation = params.Orientation or "horizontal"

	local textSize = params.TextSize or 14
	local itemHeight = params.ItemHeight or params.height or 32
	local paddingX = params.PaddingX or 12

	local iconSize = params.IconSize or 16
	local iconGap = params.IconGap or 6

	local cornerRadius = params.CornerRadius or theme.ButtonCornerRadius or theme.CornerRadius or 6

	local separatorInset = params.SeparatorInset or 6
	local separatorThickness = params.SeparatorThickness or 1

	local backgroundColor = params.BackgroundColor or theme.BgColor
	local buttonColor = params.ButtonColor or backgroundColor

	local hoverColor = params.HoverColor or theme.SecondaryColor

	local pressedColor = params.PressedColor or theme.ThirdColor or hoverColor

	local textColor = params.TextColor or theme.TextColor
	local mutedTextColor = params.MutedTextColor or theme.SecondaryTextColor

	local borderColor = params.BorderColor or theme.SecondaryColor

	local dividerColor = params.DividerColor or borderColor

	local font = argon:CreateFont(params.Font or theme.Font)

	local leftPressed = argon:IsMouseButtonPressed(LEFT_MOUSE_BUTTON)
	local leftDown = argon:IsMouseButtonDown(LEFT_MOUSE_BUTTON)

	local layout = {}
	local mainSize = 0
	local crossSize = 0

	-- Calculate item sizes first.
	for _, item in ipairs(items) do
		local kind = item.Type or "Button"

		if kind == "Separator" then
			local size = item.Thickness or separatorThickness

			table.insert(layout, {
				item = item,
				kind = kind,
				main = size,
				cross = itemHeight,
			})

			mainSize += size
			crossSize = math.max(crossSize, itemHeight)
		else
			local label = item.Text or ""

			local labelWidth = argon:MeasureText(window, label, textSize, font)

			local currentIconSize = item.IconSize or iconSize

			local contentWidth = labelWidth

			if item.Icon then
				contentWidth += currentIconSize

				if label ~= "" then
					contentWidth += iconGap
				end
			end

			local naturalWidth = item.Width or (contentWidth + paddingX * 2)

			local naturalHeight = item.Height or itemHeight

			if orientation == "horizontal" then
				table.insert(layout, {
					item = item,
					kind = kind,
					main = naturalWidth,
					cross = naturalHeight,
					contentWidth = contentWidth,
					labelWidth = labelWidth,
				})

				mainSize += naturalWidth
				crossSize = math.max(crossSize, naturalHeight)
			else
				table.insert(layout, {
					item = item,
					kind = kind,
					main = naturalHeight,
					cross = naturalWidth,
					contentWidth = contentWidth,
					labelWidth = labelWidth,
				})

				mainSize += naturalHeight
				crossSize = math.max(crossSize, naturalWidth)
			end
		end
	end

	local groupWidth
	local groupHeight

	if orientation == "horizontal" then
		groupWidth = math.max(mainSize, params.width or 0)
		groupHeight = params.height or crossSize
	else
		groupWidth = params.width or crossSize
		groupHeight = mainSize
	end

	local groupRect = {
		x = params.x,
		y = params.y,
		width = groupWidth,
		height = groupHeight,
	}

	argon:Save(window)
	argon:ClipRoundRect(window, groupRect, cornerRadius, cornerRadius)

	argon:DrawRectangle(window, {
		x = groupRect.x,
		y = groupRect.y,
		width = groupRect.width,
		height = groupRect.height,
		Color = backgroundColor,
	})

	local cursor = orientation == "horizontal" and params.x or params.y

	for index, info in ipairs(layout) do
		local item = info.item
		local kind = info.kind

		local rect

		if orientation == "horizontal" then
			rect = {
				x = cursor,
				y = params.y,
				width = info.main,
				height = groupHeight,
			}

			cursor += info.main
		else
			rect = {
				x = params.x,
				y = cursor,
				width = groupWidth,
				height = info.main,
			}

			cursor += info.main
		end

		if kind == "Separator" then
			local color = item.Color or params.SeparatorColor or dividerColor

			if orientation == "horizontal" then
				argon:DrawRectangle(window, {
					x = rect.x,
					y = rect.y + separatorInset,
					width = rect.width,
					height = math.max(0, rect.height - separatorInset * 2),
					Color = color,
				})
			else
				argon:DrawRectangle(window, {
					x = rect.x + separatorInset,
					y = rect.y,
					width = math.max(0, rect.width - separatorInset * 2),
					height = rect.height,
					Color = color,
				})
			end
		else
			local isButton = kind == "Button"
			local disabled = item.Disabled == true

			local hovered = isButton and not disabled and renderer:isMouseInRect(rect)

			local pressed = hovered and leftDown

			local color = item.Color or buttonColor

			if pressed then
				color = item.PressedColor or pressedColor
			elseif hovered then
				color = item.HoverColor or hoverColor
			end

			argon:DrawRectangle(window, {
				x = rect.x,
				y = rect.y,
				width = rect.width,
				height = rect.height,
				Color = color,
			})

			local label = item.Text or ""
			local currentIconSize = item.IconSize or iconSize

			local itemTextColor

			if disabled then
				itemTextColor = item.DisabledTextColor or mutedTextColor
			elseif kind == "Text" then
				itemTextColor = item.TextColor or mutedTextColor
			else
				itemTextColor = item.TextColor or textColor
			end

			local contentWidth = info.contentWidth or 0

			local contentX = rect.x + (rect.width - contentWidth) / 2

			local textHeight = argon:GetFontLineHeight(textSize, font)

			local textAscent = argon:GetFontAscent(textSize, font)

			local textY = rect.y + (rect.height - textHeight) / 2 + textAscent

			local iconPosition = item.IconPosition or "left"

			if item.Icon and iconPosition == "left" then
				Image({
					x = contentX,
					y = rect.y + (rect.height - currentIconSize) / 2,

					width = currentIconSize,
					height = currentIconSize,

					Image = item.Icon,

					theme = theme,
					engine_window = window,
				}, dt)

				contentX += currentIconSize

				if label ~= "" then
					contentX += iconGap
				end
			end

			if label ~= "" then
				Text({
					x = contentX,
					y = textY,

					TextSize = textSize,
					Font = font,

					text = label,
					Color = itemTextColor,

					theme = theme,
					engine_window = window,
				}, dt)

				contentX += info.labelWidth or 0

				if item.Icon and iconPosition == "right" then
					contentX += iconGap
				end
			end

			if item.Icon and iconPosition == "right" then
				Image({
					x = contentX,
					y = rect.y + (rect.height - currentIconSize) / 2,

					width = currentIconSize,
					height = currentIconSize,

					Image = item.Icon,

					theme = theme,
					engine_window = window,
				}, dt)
			end

			if isButton and hovered and leftPressed and item.OnClick then
				item.OnClick()
			end
		end

		if
			params.ShowDividers ~= false
			and index < #layout
			and kind ~= "Separator"
			and layout[index + 1].kind ~= "Separator"
		then
			if orientation == "horizontal" then
				argon:DrawRectangle(window, {
					x = rect.x + rect.width - 1,
					y = rect.y,
					width = 1,
					height = rect.height,
					Color = dividerColor,
				})
			else
				argon:DrawRectangle(window, {
					x = rect.x,
					y = rect.y + rect.height - 1,
					width = rect.width,
					height = 1,
					Color = dividerColor,
				})
			end
		end
	end

	if params.ShowBorder ~= false then
		argon:DrawRectangle(window, {
			x = groupRect.x,
			y = groupRect.y,
			width = groupRect.width,
			height = groupRect.height,
			Color = borderColor,
			isOutline = true,
		})
	end

	argon:Restore(window)

	return groupWidth, groupHeight
end
