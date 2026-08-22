local typedefs = require("../typedefs")
local Rectangle = require("./Rectangle")
local Text = require("./Text")
local argon = require("@Argon")

local TEXT_SIZE = 12
local LINE_SPACING = 2
local RISE_DISTANCE = 6

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smoothTowards(current: number, target: number, speed: number, dt: number): number
	local t = 1 - math.exp(-speed * dt)
	return lerp(current, target, t)
end

local function withAlpha(color: typedefs.RGBA, alpha: number): typedefs.RGBA
	return {
		R = color.R,
		G = color.G,
		B = color.B,
		A = (color.A or 1) * alpha,
	}
end

local function buildLines(window, font, textSize, rawText: string, maxWidth: number?): { string }
	local sourceLines = {}
	for line in (rawText or ""):gmatch("[^\n]+") do
		table.insert(sourceLines, line)
	end
	if #sourceLines == 0 then
		sourceLines = { "" }
	end

	if not maxWidth then
		return sourceLines
	end

	local wrapped = {}
	for _, line in ipairs(sourceLines) do
		local words = {}
		for word in line:gmatch("%S+") do
			table.insert(words, word)
		end

		if #words == 0 then
			table.insert(wrapped, "")
		else
			local current = words[1]
			for i = 2, #words do
				local candidate = current .. " " .. words[i]
				local width = argon:MeasureText(window, candidate, textSize, font)
				if width <= maxWidth then
					current = candidate
				else
					table.insert(wrapped, current)
					current = words[i]
				end
			end
			table.insert(wrapped, current)
		end
	end
	return wrapped
end

return function(params: typedefs.TooltipParams, dt: number): (boolean, number)
	local storage = params.RetainedStorage
	local id = params.id
	local renderer = params.renderer
	local window = params.window
	local canvas = params.canvas
	local theme = params.theme

	local field = storage[id]
	if not field then
		field = {
			hoverTime = 0,
			alpha = 0,
			anchorMouse = { X = 0, Y = 0 },
		}
		storage[id] = field
	end

	local mousePos = argon:GetMousePosition()
	local hoveredNow = renderer:isMouseInRect(params.HoverRect)

	if hoveredNow then
		if field.hoverTime <= 0 then
			field.anchorMouse = mousePos
		end
		field.hoverTime += dt
	else
		field.hoverTime = 0
	end

	local hoverDelay = params.HoverDelay or 0.4
	local visibleTarget = (hoveredNow and field.hoverTime >= hoverDelay) and 1 or 0

	field.alpha = smoothTowards(field.alpha, visibleTarget, params.FadeSpeed or 14, dt)
	if math.abs(field.alpha - visibleTarget) < 0.01 then
		field.alpha = visibleTarget
	end

	if field.alpha <= 0.01 then
		return false, field.alpha
	end

	local font = argon:CreateFont(theme.Font)
	local textHeight = argon:GetFontLineHeight(TEXT_SIZE, font)
	local textAscent = argon:GetFontAscent(TEXT_SIZE, font)
	local padding = params.Padding or 6

	local lines = buildLines(window, font, TEXT_SIZE, params.Text or "", params.MaxWidth)

	local contentWidth = 0
	for _, line in ipairs(lines) do
		local w = argon:MeasureText(window, line, TEXT_SIZE, font)
		if w > contentWidth then
			contentWidth = w
		end
	end
	if params.MaxWidth then
		contentWidth = math.min(contentWidth, params.MaxWidth)
	end

	local boxWidth = contentWidth + padding * 2
	local lineStride = textHeight + LINE_SPACING
	local boxHeight = (#lines * lineStride) - LINE_SPACING + padding * 2

	local placement = params.Placement or "cursor"
	local boxX, boxY

	if placement == "cursor" then
		local offset = params.Offset or { x = 12, y = 20 }
		boxX = field.anchorMouse.X + offset.x
		boxY = field.anchorMouse.Y + offset.y
	elseif placement == "above" then
		local rect = params.HoverRect
		boxX = rect.x + (rect.width - boxWidth) / 2
		boxY = rect.y - boxHeight - (params.Gap or 8)
	elseif placement == "below" then
		local rect = params.HoverRect
		boxX = rect.x + (rect.width - boxWidth) / 2
		boxY = rect.y + rect.height + (params.Gap or 8)
	elseif placement == "left" then
		local rect = params.HoverRect
		boxX = rect.x - boxWidth - (params.Gap or 8)
		boxY = rect.y + (rect.height - boxHeight) / 2
	else -- "right"
		local rect = params.HoverRect
		boxX = rect.x + rect.width + (params.Gap or 8)
		boxY = rect.y + (rect.height - boxHeight) / 2
	end
	local riseAmount = (1 - field.alpha) * RISE_DISTANCE
	if placement == "left" then
		boxX -= riseAmount
	elseif placement == "right" then
		boxX += riseAmount
	else
		boxY -= riseAmount
	end

	local margin = params.ScreenMargin or 4
	boxX = math.clamp(boxX, margin, math.max(margin, window.Width - boxWidth - margin))
	boxY = math.clamp(boxY, margin, math.max(margin, window.Height - boxHeight - margin))

	local cornerRadius = params.CornerRadius or theme.CornerRadius or 6
	local bgColor = withAlpha(params.BackgroundColor or theme.ThirdColor, field.alpha)
	local borderColor = withAlpha(params.BorderColor or theme.SecondaryColor, field.alpha)
	local textColor = withAlpha(params.TextColor or theme.TextColor, field.alpha)

	argon:Save(window)
	argon:ClipRoundRect(window, {
		x = boxX,
		y = boxY,
		width = boxWidth,
		height = boxHeight,
	}, cornerRadius, cornerRadius)

	Rectangle({
		x = boxX,
		y = boxY,
		width = boxWidth,
		height = boxHeight,
		Color = bgColor,
		theme = theme,
		engine_window = canvas,
	}, dt)

	for index, line in ipairs(lines) do
		Text({
			x = boxX + padding,
			y = boxY + padding + (index - 1) * lineStride + textAscent,
			TextSize = TEXT_SIZE,
			theme = theme,
			Font = font,
			text = line,
			Color = textColor,
			engine_window = canvas,
		}, dt)
	end

	argon:Restore(window)

	return true, field.alpha
end
