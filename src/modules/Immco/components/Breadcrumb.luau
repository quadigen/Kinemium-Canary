local typedefs = require("../typedefs")

local Text = require("./Text")
local argon = require("@Argon")

local LEFT_MOUSE_BUTTON = 1

return function(params: typedefs.BreadcrumbParams, dt: number): number
	local window = params.engine_window
	local renderer = params.renderer
	local theme = params.theme
	local items = params.Items

	local textSize = params.TextSize or 14
	local gap = params.Gap or 10

	local separator = params.Separator or "›"
	local ellipsis = params.Ellipsis or "..."
	local collapsed = params.Collapsed == true

	local font = argon:CreateFont(params.Font or theme.Font)

	local textHeight = argon:GetFontLineHeight(textSize, font)
	local textAscent = argon:GetFontAscent(textSize, font)

	local height = params.height or textHeight + 8

	local baselineY = params.y + (height - textHeight) / 2 + textAscent

	local linkColor = params.LinkColor or theme.SecondaryTextColor
	local hoverColor = params.HoverColor or theme.TextColor
	local pageColor = params.PageColor or theme.TextColor
	local separatorColor = params.SeparatorColor or theme.SecondaryTextColor

	local leftPressed = argon:IsMouseButtonPressed(LEFT_MOUSE_BUTTON)

	local cursorX = params.x

	local entries = {}

	if collapsed and #items > 3 then
		table.insert(entries, {
			kind = "item",
			index = 1,
		})

		table.insert(entries, {
			kind = "ellipsis",
		})

		table.insert(entries, {
			kind = "item",
			index = #items - 1,
		})

		table.insert(entries, {
			kind = "item",
			index = #items,
		})
	else
		for index = 1, #items do
			table.insert(entries, {
				kind = "item",
				index = index,
			})
		end
	end

	local shadowColor = params.ShadowColor or argon:RGBA(0, 0, 0, 140)

	local shadowOffset = {
		X = params.ShadowOffsetX or 0,
		Y = params.ShadowOffsetY or 2,
	}

	local shadowBlur = params.ShadowBlur or 3
	local shadowSpread = params.ShadowSpread or 1

	local function drawText(text: string, x: number, color)
		if params.TextShadow ~= false then
			argon:DrawTextShadow(window, text, {
				X = x,
				Y = baselineY,

				TextSize = textSize,
				Font = font,
				Color = color,
			}, shadowOffset, shadowBlur, shadowSpread, shadowColor)
		end

		Text({
			x = x,
			y = baselineY,

			TextSize = textSize,
			Font = font,

			text = text,
			Color = color,

			theme = theme,
			engine_window = window,
		}, dt)
	end

	for entryIndex, entry in ipairs(entries) do
		if entry.kind == "item" then
			local item = items[entry.index]

			local width = argon:MeasureText(window, item.Text, textSize, font)

			local rect = {
				x = cursorX,
				y = params.y,
				width = width,
				height = height,
			}

			local isCurrent = item.Current == true or (item.Current == nil and entry.index == #items)

			local clickable = not isCurrent and not item.Disabled and item.OnClick ~= nil

			local hovered = clickable and renderer:isMouseInRect(rect)

			local color

			if isCurrent then
				color = pageColor
			elseif hovered then
				color = hoverColor
			else
				color = linkColor
			end

			drawText(item.Text, cursorX, color)

			if hovered and leftPressed then
				item.OnClick()
			end

			cursorX += width
		else
			local width = argon:MeasureText(window, ellipsis, textSize, font)

			local rect = {
				x = cursorX,
				y = params.y,
				width = width,
				height = height,
			}

			local clickable = params.OnEllipsisClick ~= nil
			local hovered = clickable and renderer:isMouseInRect(rect)

			drawText(ellipsis, cursorX, hovered and hoverColor or linkColor)

			if hovered and leftPressed then
				local hiddenItems = {}

				for index = 2, #items - 2 do
					table.insert(hiddenItems, items[index])
				end

				params.OnEllipsisClick(hiddenItems)
			end

			cursorX += width
		end

		if entryIndex < #entries then
			cursorX += gap

			local separatorWidth = argon:MeasureText(window, separator, textSize, font)

			drawText(separator, cursorX, separatorColor)

			cursorX += separatorWidth + gap
		end
	end

	return cursorX - params.x
end
