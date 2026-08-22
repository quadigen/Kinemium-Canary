local typedefs = require("../typedefs")
local argon = require("@Argon")

local LEFT_MOUSE_BUTTON = 1

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smoothTowards(current: number, target: number, speed: number, dt: number): number
	local t = 1 - math.exp(-speed * dt)
	return lerp(current, target, t)
end

local function clampColor(v: number): number
	return math.clamp(v, 0, 1)
end

local function brighten(color: typedefs.RGBA, amount: number): typedefs.RGBA
	return {
		R = clampColor(color.R + amount),
		G = clampColor(color.G + amount),
		B = clampColor(color.B + amount),
		A = color.A,
	}
end

return function(params: typedefs.ScrollerParams, dt: number): (number, boolean, number)
	local storage = params.RetainedStorage
	local id = params.id
	local renderer = params.renderer
	local window = params.window
	local theme = params.theme

	local field = storage[id]
	if not field then
		field = {
			scrollY = params.InitialScroll or 0,
			scrollTarget = params.InitialScroll or 0,
			dragging = false,
			dragStartMouse = 0,
			dragStartScroll = 0,
		}
		storage[id] = field
	end

	local vertical = params.Orientation ~= "horizontal"
	local trackLength = vertical and params.height or params.width
	local viewSize = params.ViewHeight or trackLength
	local contentSize = math.max(params.ContentHeight or viewSize, viewSize)
	local maxScroll = math.max(0, contentSize - viewSize)
	local minThumb = params.MinThumbSize or 20
	local thumbLength = math.clamp(trackLength * (viewSize / contentSize), minThumb, trackLength)
	local scrollableTrack = math.max(trackLength - thumbLength, 0)

	field.scrollTarget = math.clamp(field.scrollTarget, 0, maxScroll)

	local scrollbarWidth = params.ScrollbarWidth or 8
	local scrollbarX = vertical and (params.x + params.width - scrollbarWidth) or params.x

	local trackRect = {
		x = scrollbarX,
		y = params.y,
		width = vertical and scrollbarWidth or params.width,
		height = vertical and params.height or scrollbarWidth,
	}

	local thumbOffset = maxScroll > 0 and (field.scrollY / maxScroll) * scrollableTrack or 0
	local thumbRect
	if vertical then
		thumbRect = {
			x = scrollbarX,
			y = params.y + thumbOffset,
			width = scrollbarWidth,
			height = thumbLength,
		}
	else
		thumbRect = { x = params.x, y = params.y, width = thumbLength, height = params.height }
	end

	local mousePos = argon:GetMousePosition()
	local hoveredTrack = renderer:isMouseInRect(trackRect)
	local hoveredThumb = renderer:isMouseInRect(thumbRect)
	local hoveredRegion = params.ScrollRegion and renderer:isMouseInRect(params.ScrollRegion) or false

	local leftDown = argon:IsMouseButtonDown(LEFT_MOUSE_BUTTON)
	local leftPressed = argon:IsMouseButtonPressed(LEFT_MOUSE_BUTTON)

	if leftPressed and hoveredThumb and not field.dragging then
		field.dragging = true
		field.dragStartMouse = vertical and mousePos.Y or mousePos.X
		field.dragStartScroll = field.scrollTarget
	end

	if field.dragging then
		if not leftDown then
			field.dragging = false
		else
			local mouseNow = vertical and mousePos.Y or mousePos.X
			local delta = mouseNow - field.dragStartMouse
			local scrollRatio = scrollableTrack > 0 and (maxScroll / scrollableTrack) or 0
			field.scrollTarget = math.clamp(field.dragStartScroll + delta * scrollRatio, 0, maxScroll)
			field.scrollY = field.scrollTarget -- 1:1 tracking feels better than lerp while actively dragging
		end
	elseif leftPressed and hoveredTrack and not hoveredThumb then
		local clickPos = vertical and (mousePos.Y - params.y) or (mousePos.X - params.x)
		local ratio = scrollableTrack > 0 and math.clamp((clickPos - thumbLength / 2) / scrollableTrack, 0, 1) or 0
		field.scrollTarget = ratio * maxScroll
	end

	if not field.dragging and (hoveredTrack or hoveredRegion) then
		local wheelDelta = argon:GetMouseWheelMove()
		if wheelDelta ~= 0 then
			field.scrollTarget = math.clamp(field.scrollTarget - wheelDelta * (params.ScrollSpeed or 40), 0, maxScroll)
		end
	end

	if not field.dragging then
		field.scrollY = smoothTowards(field.scrollY, field.scrollTarget, params.ScrollLerpSpeed or 20, dt)
		if math.abs(field.scrollY - field.scrollTarget) < 0.05 then
			field.scrollY = field.scrollTarget
		end
	end

	thumbOffset = maxScroll > 0 and (field.scrollY / maxScroll) * scrollableTrack or 0
	if vertical then
		thumbRect.y = params.y + thumbOffset
	else
		thumbRect.x = params.x + thumbOffset
	end

	local trackColor = params.TrackColor or theme.TrackColor or theme.BackgroundColor
	local thumbColor = params.ThumbColor or theme.SecondaryColor
	local thumbHoverColor = params.ThumbHoverColor or brighten(thumbColor, 0.12)
	local thumbActiveColor = params.ThumbActiveColor or brighten(thumbColor, 0.2)

	local drawnThumbColor = thumbColor
	if field.dragging then
		drawnThumbColor = thumbActiveColor
	elseif hoveredThumb then
		drawnThumbColor = thumbHoverColor
	end

	if maxScroll > 0 then
		if trackColor then
			argon:DrawRectangle(window, {
				x = trackRect.x,
				y = trackRect.y,
				width = trackRect.width,
				height = trackRect.height,
				Color = trackColor,
			})
		end

		argon:DrawRectangle(window, {
			x = thumbRect.x,
			y = thumbRect.y,
			width = scrollbarWidth,
			height = thumbRect.height,
			Color = drawnThumbColor,
		})
	end

	if params.OnScroll then
		params.OnScroll(field.scrollY)
	end

	if params.callback then
		local contentX = params.ContentX or params.x
		local contentY = params.ContentY or params.y
		local cornerRadius = params.CornerRadius or theme.CornerRadius or 0

		local clipRect
		if vertical then
			clipRect = { x = contentX, y = params.y, width = params.ContentWidth or params.width, height = viewSize }
		else
			clipRect = { x = params.x, y = contentY, width = viewSize, height = params.ContentWidth or params.height }
		end

		argon:Save(window)
		argon:ClipRoundRect(window, clipRect, cornerRadius, cornerRadius)

		params.callback({
			x = vertical and contentX or (contentX - field.scrollY),
			y = vertical and (contentY - field.scrollY) or contentY,
			width = params.ContentWidth or params.width,
			height = contentSize,
			window = window,
			theme = theme,
			renderer = renderer,
			RetainedStorage = storage,
			scrollY = field.scrollY,
		})

		argon:Restore(window)
	end

	return field.scrollY, field.dragging, maxScroll
end
