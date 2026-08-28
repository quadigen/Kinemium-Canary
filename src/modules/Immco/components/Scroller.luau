local typedefs = require("../typedefs")
local argon = require("@Argon")

local LEFT_MOUSE_BUTTON = 1

local function smoothTowards(current: number, target: number, speed: number, dt: number): number
	local t = 1 - math.exp(-speed * dt)
	return current + (target - current) * t
end

local function brighten(color: typedefs.RGBA, amount: number): typedefs.RGBA
	return {
		R = math.clamp(color.R + amount, 0, 1),
		G = math.clamp(color.G + amount, 0, 1),
		B = math.clamp(color.B + amount, 0, 1),
		A = color.A,
	}
end

return function(params: typedefs.ScrollerParams, dt: number): (number, boolean, number)
	local storage = params.RetainedStorage
	local id = params.id
	local renderer = params.renderer
	local window = params.window
	local theme = params.theme

	assert(storage, "Scroller requires RetainedStorage")
	assert(id, "Scroller requires id")

	local field = storage[id]

	if not field then
		field = {
			scroll = params.InitialScroll or 0,
			target = params.InitialScroll or 0,

			dragging = false,
			dragMouseStart = 0,
			dragScrollStart = 0,
		}

		storage[id] = field
	end

	local vertical = params.Orientation ~= "horizontal"

	-- Visible viewport
	local viewportWidth = params.width
	local viewportHeight = params.height

	local viewportSize = vertical and viewportHeight or viewportWidth

	-- Total size of the stuff inside
	local contentSize

	if vertical then
		contentSize = math.max(params.ContentHeight or viewportHeight, viewportHeight)
	else
		contentSize = math.max(params.ContentWidth or viewportWidth, viewportWidth)
	end

	local maxScroll = math.max(0, contentSize - viewportSize)

	field.target = math.clamp(field.target, 0, maxScroll)
	field.scroll = math.clamp(field.scroll, 0, maxScroll)

	-- =========================
	-- Scrollbar geometry
	-- =========================

	local scrollbarWidth = params.ScrollbarWidth or 6
	local minThumbSize = params.MinThumbSize or 20

	local trackRect

	if vertical then
		trackRect = {
			x = params.x + params.width - scrollbarWidth,
			y = params.y,
			width = scrollbarWidth,
			height = params.height,
		}
	else
		trackRect = {
			x = params.x,
			y = params.y + params.height - scrollbarWidth,
			width = params.width,
			height = scrollbarWidth,
		}
	end

	local trackLength = vertical and trackRect.height or trackRect.width

	local thumbLength

	if maxScroll <= 0 then
		thumbLength = trackLength
	else
		thumbLength = math.max(minThumbSize, trackLength * (viewportSize / contentSize))

		thumbLength = math.min(thumbLength, trackLength)
	end

	local thumbTravel = math.max(0, trackLength - thumbLength)

	local scrollRatio = if maxScroll > 0 then field.scroll / maxScroll else 0

	local thumbOffset = scrollRatio * thumbTravel

	local thumbRect

	if vertical then
		thumbRect = {
			x = trackRect.x,
			y = trackRect.y + thumbOffset,
			width = trackRect.width,
			height = thumbLength,
		}
	else
		thumbRect = {
			x = trackRect.x + thumbOffset,
			y = trackRect.y,
			width = thumbLength,
			height = trackRect.height,
		}
	end

	-- =========================
	-- Input
	-- =========================

	local mouse = argon:GetMousePosition()

	local hoveredViewport = renderer:isMouseInRect({
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
	})

	local hoveredTrack = renderer:isMouseInRect(trackRect)
	local hoveredThumb = renderer:isMouseInRect(thumbRect)

	local leftPressed = argon:IsMouseButtonPressed(LEFT_MOUSE_BUTTON)
	local leftDown = argon:IsMouseButtonDown(LEFT_MOUSE_BUTTON)

	-- Mouse wheel
	if hoveredViewport and not field.dragging and maxScroll > 0 then
		local wheel = argon:GetMouseWheelMove()

		if wheel ~= 0 then
			field.target -= wheel * (params.ScrollSpeed or 40)
			field.target = math.clamp(field.target, 0, maxScroll)
		end
	end

	-- Start dragging scrollbar
	if leftPressed and hoveredThumb and maxScroll > 0 then
		field.dragging = true

		field.dragMouseStart = if vertical then mouse.Y else mouse.X

		field.dragScrollStart = field.scroll
	end

	-- Dragging scrollbar
	if field.dragging then
		if not leftDown then
			field.dragging = false
		else
			local mousePosition = if vertical then mouse.Y else mouse.X

			local mouseDelta = mousePosition - field.dragMouseStart

			if thumbTravel > 0 then
				local pixelsToScroll = maxScroll / thumbTravel

				field.target = field.dragScrollStart + mouseDelta * pixelsToScroll

				field.target = math.clamp(field.target, 0, maxScroll)

				-- Direct movement while dragging
				field.scroll = field.target
			end
		end
	end

	-- Click scrollbar track
	if leftPressed and hoveredTrack and not hoveredThumb and not field.dragging and maxScroll > 0 then
		local mouseOnTrack

		if vertical then
			mouseOnTrack = mouse.Y - trackRect.y
		else
			mouseOnTrack = mouse.X - trackRect.x
		end

		local targetThumbPosition = mouseOnTrack - thumbLength * 0.5

		local ratio = if thumbTravel > 0 then math.clamp(targetThumbPosition / thumbTravel, 0, 1) else 0

		field.target = ratio * maxScroll
	end

	-- Smooth wheel / track scrolling
	if not field.dragging then
		field.scroll = smoothTowards(field.scroll, field.target, params.ScrollLerpSpeed or 18, dt)

		if math.abs(field.scroll - field.target) < 0.01 then
			field.scroll = field.target
		end
	end

	-- =========================
	-- Draw clipped contents
	-- =========================

	local cornerRadius = params.CornerRadius or theme.CornerRadius or 0

	local contentX = params.ContentX or params.x
	local contentY = params.ContentY or params.y

	local clipRect = {
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
	}

	argon:Save(window)

	argon:ClipRoundRect(window, clipRect, cornerRadius, cornerRadius)

	if params.callback then
		params.callback({
			x = if vertical then contentX else contentX - field.scroll,

			y = if vertical then contentY - field.scroll else contentY,

			width = params.ContentWidth or params.width,
			height = params.ContentHeight or params.height,

			viewportX = params.x,
			viewportY = params.y,
			viewportWidth = params.width,
			viewportHeight = params.height,

			scrollY = if vertical then field.scroll else 0,
			scrollX = if vertical then 0 else field.scroll,

			scroll = field.scroll,

			window = window,
			renderer = renderer,
			theme = theme,
			RetainedStorage = storage,
		})
	end

	argon:Restore(window)

	-- =========================
	-- Scrollbar
	-- =========================

	if maxScroll > 0 then
		-- Recalculate after scrolling
		scrollRatio = field.scroll / maxScroll
		thumbOffset = scrollRatio * thumbTravel

		if vertical then
			thumbRect.y = trackRect.y + thumbOffset
		else
			thumbRect.x = trackRect.x + thumbOffset
		end

		local trackColor = params.TrackColor or theme.TrackColor

		local thumbColor = params.ThumbColor or theme.SecondaryColor

		local thumbHoverColor = params.ThumbHoverColor or brighten(thumbColor, 0.10)

		local thumbActiveColor = params.ThumbActiveColor or brighten(thumbColor, 0.18)

		if trackColor then
			argon:DrawRectangle(window, {
				x = trackRect.x,
				y = trackRect.y,
				width = trackRect.width,
				height = trackRect.height,
				Color = trackColor,
			})
		end

		local color = thumbColor

		if field.dragging then
			color = thumbActiveColor
		elseif hoveredThumb then
			color = thumbHoverColor
		end

		argon:DrawRectangle(window, {
			x = thumbRect.x,
			y = thumbRect.y,
			width = thumbRect.width,
			height = thumbRect.height,
			Color = color,
		})
	end

	if params.OnScroll then
		params.OnScroll(field.scroll)
	end

	return field.scroll, field.dragging, maxScroll
end
