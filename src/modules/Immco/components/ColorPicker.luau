local typedefs = require("../typedefs")
local Rectangle = require("./Rectangle")
local Text = require("./Text")
local argon = require("@Argon")

local LEFT_MOUSE_BUTTON = 1
local TEXT_SIZE = 12

local function hsvToRgb(h: number, s: number, v: number): (number, number, number)
	local c = v * s
	local hh = (h % 360) / 60
	local x = c * (1 - math.abs(hh % 2 - 1))
	local r, g, b = 0, 0, 0
	if hh < 1 then
		r, g, b = c, x, 0
	elseif hh < 2 then
		r, g, b = x, c, 0
	elseif hh < 3 then
		r, g, b = 0, c, x
	elseif hh < 4 then
		r, g, b = 0, x, c
	elseif hh < 5 then
		r, g, b = x, 0, c
	else
		r, g, b = c, 0, x
	end
	local m = v - c
	return r + m, g + m, b + m
end

local function rgbToHsv(r: number, g: number, b: number): (number, number, number)
	local max = math.max(r, g, b)
	local min = math.min(r, g, b)
	local delta = max - min

	local h = 0
	if delta > 0 then
		if max == r then
			h = 60 * (((g - b) / delta) % 6)
		elseif max == g then
			h = 60 * (((b - r) / delta) + 2)
		else
			h = 60 * (((r - g) / delta) + 4)
		end
	end

	local s = (max == 0) and 0 or (delta / max)
	local v = max
	return h, s, v
end

local function toHex(r: number, g: number, b: number): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5)
	)
end

local function drawCheckerboard(
	rect,
	cellSize: number,
	colorA: typedefs.RGBA,
	colorB: typedefs.RGBA,
	engineWindow,
	theme,
	dt: number
)
	local cols = math.ceil(rect.width / cellSize)
	local rows = math.ceil(rect.height / cellSize)
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			local cellW = math.min(cellSize, rect.width - col * cellSize)
			local cellH = math.min(cellSize, rect.height - row * cellSize)
			Rectangle({
				x = rect.x + col * cellSize,
				y = rect.y + row * cellSize,
				width = cellW,
				height = cellH,
				Color = ((row + col) % 2 == 0) and colorA or colorB,
				theme = theme,
				engine_window = engineWindow,
			}, dt)
		end
	end
end

return function(params: typedefs.ColorPickerParams, dt: number): (typedefs.RGBA, boolean)
	local storage = params.RetainedStorage
	local id = params.id
	local renderer = params.renderer
	local window = params.window
	local theme = params.theme

	local field = storage[id]
	if not field then
		local initial = params.InitialColor or { R = 1, G = 0, B = 0, A = 1 }
		local h, s, v = rgbToHsv(initial.R, initial.G, initial.B)
		field = {
			hue = h,
			saturation = s,
			value = v,
			alpha = initial.A or 1,
			dragging = nil :: string?,
			hoverGlow = 0,
		}
		storage[id] = field
	end

	local size = params.Size or 160
	local hueBarWidth = params.HueBarWidth or 20
	local showAlpha = params.ShowAlpha or false
	local alphaBarWidth = params.AlphaBarWidth or 20
	local gap = params.Gap or 10
	local resolution = params.Resolution or 24
	local hueSegments = params.HueSegments or 60
	local checkerSize = params.CheckerSize or 6
	local cornerRadius = params.CornerRadius or theme.CornerRadius or 0
	local showPreview = (params.ShowPreview == nil) or params.ShowPreview
	local showHex = (params.ShowHex == nil) or params.ShowHex
	local previewHeight = params.PreviewHeight or 24

	local svRect = { x = params.x, y = params.y, width = size, height = size }
	local hueRect = { x = svRect.x + svRect.width + gap, y = params.y, width = hueBarWidth, height = size }
	local alphaRect = showAlpha
			and { x = hueRect.x + hueRect.width + gap, y = params.y, width = alphaBarWidth, height = size }
		or nil

	local mousePos = argon:GetMousePosition()
	local hoveredSV = renderer:isMouseInRect(svRect)
	local hoveredHue = renderer:isMouseInRect(hueRect)
	local hoveredAlpha = alphaRect ~= nil and renderer:isMouseInRect(alphaRect)

	local leftPressed = argon:IsMouseButtonPressed(LEFT_MOUSE_BUTTON)
	local leftDown = argon:IsMouseButtonDown(LEFT_MOUSE_BUTTON)

	if leftPressed then
		if hoveredSV then
			field.dragging = "sv"
		elseif hoveredHue then
			field.dragging = "hue"
		elseif hoveredAlpha then
			field.dragging = "alpha"
		end
	end

	if not leftDown then
		field.dragging = nil
	end

	local changed = false

	if field.dragging == "sv" then
		local s = math.clamp((mousePos.X - svRect.x) / svRect.width, 0, 1)
		local v = 1 - math.clamp((mousePos.Y - svRect.y) / svRect.height, 0, 1)
		if s ~= field.saturation or v ~= field.value then
			changed = true
		end
		field.saturation, field.value = s, v
	elseif field.dragging == "hue" then
		local t = math.clamp((mousePos.Y - hueRect.y) / hueRect.height, 0, 1)
		local h = t * 360
		if h ~= field.hue then
			changed = true
		end
		field.hue = h
	elseif field.dragging == "alpha" and alphaRect then
		local t = math.clamp((mousePos.Y - alphaRect.y) / alphaRect.height, 0, 1)
		local a = 1 - t
		if a ~= field.alpha then
			changed = true
		end
		field.alpha = a
	end

	local r, g, b = hsvToRgb(field.hue, field.saturation, field.value)
	local currentColor: typedefs.RGBA = { R = r, G = g, B = b, A = field.alpha }

	if changed and params.OnChanged then
		params.OnChanged(currentColor)
	end

	argon:Save(window)
	argon:ClipRoundRect(window, svRect, cornerRadius, cornerRadius)

	local cellW = svRect.width / resolution
	local cellH = svRect.height / resolution
	for gy = 0, resolution - 1 do
		local v = 1 - (gy / (resolution - 1))
		for gx = 0, resolution - 1 do
			local s = gx / (resolution - 1)
			local cr, cg, cb = hsvToRgb(field.hue, s, v)
			Rectangle({
				x = svRect.x + gx * cellW,
				y = svRect.y + gy * cellH,
				width = cellW + 1,
				height = cellH + 1,
				Color = { R = cr, G = cg, B = cb, A = 1 },
				theme = theme,
				engine_window = window,
			}, dt)
		end
	end

	argon:Restore(window)

	Rectangle({
		x = svRect.x,
		y = svRect.y,
		width = svRect.width,
		height = svRect.height,
		Color = theme.SecondaryColor,
		theme = theme,
		engine_window = window,
		isOutline = true,
	}, dt)

	local markerX = svRect.x + field.saturation * svRect.width
	local markerY = svRect.y + (1 - field.value) * svRect.height
	local markerSize = 10
	local markerColor = (field.value > 0.5) and { R = 0, G = 0, B = 0, A = 1 } or theme.InputTextColor
	Rectangle({
		x = markerX - markerSize / 2,
		y = markerY - markerSize / 2,
		width = markerSize,
		height = markerSize,
		Color = markerColor,
		theme = theme,
		engine_window = window,
		isOutline = true,
	}, dt)

	argon:Save(window)
	argon:ClipRoundRect(window, hueRect, cornerRadius, cornerRadius)

	local segHeight = hueRect.height / hueSegments
	for i = 0, hueSegments - 1 do
		local segHue = (i / hueSegments) * 360
		local hr, hg, hb = hsvToRgb(segHue, 1, 1)
		Rectangle({
			x = hueRect.x,
			y = hueRect.y + i * segHeight,
			width = hueRect.width,
			height = segHeight + 1,
			Color = { R = hr, G = hg, B = hb, A = 1 },
			theme = theme,
			engine_window = window,
		}, dt)
	end

	argon:Restore(window)

	Rectangle({
		x = hueRect.x,
		y = hueRect.y,
		width = hueRect.width,
		height = hueRect.height,
		Color = theme.SecondaryColor,
		theme = theme,
		engine_window = window,
		isOutline = true,
	}, dt)

	local hueNotchY = hueRect.y + (field.hue / 360) * hueRect.height
	Rectangle({
		x = hueRect.x - 2,
		y = hueNotchY - 2,
		width = hueRect.width + 4,
		height = 4,
		Color = theme.TextColor,
		theme = theme,
		engine_window = window,
		isOutline = true,
	}, dt)

	if alphaRect then
		argon:Save(window)
		argon:ClipRoundRect(window, alphaRect, cornerRadius, cornerRadius)

		drawCheckerboard(
			alphaRect,
			checkerSize,
			{ R = 0.8, G = 0.8, B = 0.8, A = 1 },
			theme.InputTextColor,
			window,
			theme,
			dt
		)

		local aSegments = hueSegments
		local aSegHeight = alphaRect.height / aSegments
		for i = 0, aSegments - 1 do
			local t = i / (aSegments - 1)
			local a = 1 - t
			Rectangle({
				x = alphaRect.x,
				y = alphaRect.y + i * aSegHeight,
				width = alphaRect.width,
				height = aSegHeight + 1,
				Color = { R = r, G = g, B = b, A = a },
				theme = theme,
				engine_window = window,
			}, dt)
		end

		argon:Restore(window)

		Rectangle({
			x = alphaRect.x,
			y = alphaRect.y,
			width = alphaRect.width,
			height = alphaRect.height,
			Color = theme.SecondaryColor,
			theme = theme,
			engine_window = window,
			isOutline = true,
		}, dt)

		local alphaNotchY = alphaRect.y + (1 - field.alpha) * alphaRect.height
		Rectangle({
			x = alphaRect.x - 2,
			y = alphaNotchY - 2,
			width = alphaRect.width + 4,
			height = 4,
			Color = theme.TextColor,
			theme = theme,
			engine_window = window,
			isOutline = true,
		}, dt)
	end

	if showPreview or showHex then
		local rowY = svRect.y + svRect.height + gap
		local rowX = svRect.x

		if showPreview then
			local previewRect = { x = rowX, y = rowY, width = previewHeight * 2, height = previewHeight }

			argon:Save(window)
			argon:ClipRoundRect(window, previewRect, cornerRadius, cornerRadius)

			drawCheckerboard(
				previewRect,
				checkerSize,
				{ R = 0.8, G = 0.8, B = 0.8, A = 1 },
				theme.InputTextColor,
				window,
				theme,
				dt
			)

			Rectangle({
				x = previewRect.x,
				y = previewRect.y,
				width = previewRect.width,
				height = previewRect.height,
				Color = currentColor,
				theme = theme,
				engine_window = window,
			}, dt)

			argon:Restore(window)

			Rectangle({
				x = previewRect.x,
				y = previewRect.y,
				width = previewRect.width,
				height = previewRect.height,
				Color = theme.SecondaryColor,
				theme = theme,
				engine_window = window,
				isOutline = true,
			}, dt)

			rowX += previewRect.width + gap
		end

		if showHex then
			local font = argon:CreateFont(theme.Font)
			local textHeight = argon:GetFontLineHeight(TEXT_SIZE, font)
			local textAscent = argon:GetFontAscent(TEXT_SIZE, font)
			local hexLabel = toHex(r, g, b)
				.. (showAlpha and string.format(" (%d%%)", math.floor(field.alpha * 100 + 0.5)) or "")

			Text({
				x = rowX,
				y = rowY + (previewHeight - textHeight) / 2 + textAscent,
				TextSize = TEXT_SIZE,
				theme = theme,
				Font = font,
				text = hexLabel,
				Color = theme.TextColor,
				engine_window = window,
			}, dt)
		end
	end

	return currentColor, changed
end
