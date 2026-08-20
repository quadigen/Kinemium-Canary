local typedefs = require("../typedefs")
local argon = require("@Argon")
local Text = require("./Text")

local function resolveFocus(storage, id, x, y, width, height, clicks, onClickInside)
	if not clicks then
		return storage.focusedId == id
	end
	for _, click in clicks do
		if click.Button == 1 and not click.Down then
			local hit = click.X >= x and click.X <= x + width and click.Y >= y and click.Y <= y + height
			if hit then
				storage.focusedId = id
				if onClickInside then
					onClickInside(click)
				end
			elseif storage.focusedId == id then
				storage.focusedId = nil
			end
		end
	end
	return storage.focusedId == id
end

local function isContinuationByte(byte: number?): boolean
	return byte ~= nil and bit32.band(byte, 0xC0) == 0x80
end

local function clampCursor(text: string, pos: number): number
	if pos < 0 then
		pos = 0
	elseif pos > #text then
		pos = #text
	end
	while pos > 0 and isContinuationByte(string.byte(text, pos + 1)) do
		pos -= 1
	end
	return pos
end

local function prevCharPos(text: string, pos: number): number
	pos = clampCursor(text, pos)
	if pos <= 0 then
		return 0
	end
	pos -= 1
	while pos > 0 and isContinuationByte(string.byte(text, pos + 1)) do
		pos -= 1
	end
	return pos
end

local function nextCharPos(text: string, pos: number): number
	pos = clampCursor(text, pos)
	if pos >= #text then
		return #text
	end
	pos += 1
	while pos < #text and isContinuationByte(string.byte(text, pos + 1)) do
		pos += 1
	end
	return pos
end

local function insertAt(text: string, pos: number, insert: string): (string, number)
	pos = clampCursor(text, pos)
	return text:sub(1, pos) .. insert .. text:sub(pos + 1), pos + #insert
end

local function backspaceAt(text: string, pos: number): (string, number)
	pos = clampCursor(text, pos)
	if pos <= 0 then
		return text, pos
	end
	local newPos = prevCharPos(text, pos)
	return text:sub(1, newPos) .. text:sub(pos + 1), newPos
end

local function deleteAt(text: string, pos: number): string
	pos = clampCursor(text, pos)
	if pos >= #text then
		return text
	end
	local nxt = nextCharPos(text, pos)
	return text:sub(1, pos) .. text:sub(nxt + 1)
end

local function trimToMaxLength(text: string, insert: string, maxLength: number): string
	local currentLen = utf8.len(text) or #text
	local remaining = maxLength - currentLen
	if remaining <= 0 then
		return ""
	end
	local insertLen = utf8.len(insert) or #insert
	if insertLen <= remaining then
		return insert
	end
	local cut = utf8.offset(insert, remaining + 1)
	return cut and insert:sub(1, cut - 1) or insert
end

local function cursorPosFromX(window, text: string, font, textSize: number, relativeX: number): number
	if relativeX <= 0 or text == "" then
		return 0
	end

	local bestPos = #text
	local bestDist = math.huge
	local pos = 0
	while true do
		local width = argon:MeasureText(window, text:sub(1, pos), textSize, font)
		local dist = math.abs(width - relativeX)
		if dist < bestDist then
			bestDist = dist
			bestPos = pos
		end
		if pos >= #text then
			break
		end
		pos = nextCharPos(text, pos)
	end
	return bestPos
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smoothTowards(current: number, target: number, speed: number, dt: number): number
	local t = 1 - math.exp(-speed * dt)
	return lerp(current, target, t)
end

return function(params: typedefs.TextInputParams, dt: number)
	local window = params.engine_window
	local theme = params.theme
	local cornerRadius = theme.InputCornerRadius or 4
	local storage = params.RetainedStorage
	local id = params.id
	local renderer = params.renderer

	assert(storage, "TextInput requires params.RetainedStorage")
	assert(id, "TextInput requires params.id")
	assert(renderer, "TextInput requires params.renderer")

	local readOnly = params.ReadOnly == true
	local padding = params.padding or 10
	local textSize = params.TextSize or 14
	local font = argon:CreateFont(theme.Font)
	local innerWidth = math.max(0, params.width - padding * 2)

	local field = storage[id]
	if not field then
		local initialText = params.text or ""
		field = {
			text = initialText,
			wasFocused = false,
			cursorPos = #initialText,
			caretX = 0,
			scrollOffset = 0,
			scrollTarget = 0,
			lastBlinkReset = os.clock(),
		}
		storage[id] = field
	end

	local focused = resolveFocus(
		storage,
		id,
		params.x,
		params.y,
		params.width,
		params.height,
		renderer.PendingClicks,
		function(click)
			local relativeX = (click.X - (params.x + padding)) + field.scrollOffset
			field.cursorPos = cursorPosFromX(window, field.text, font, textSize, relativeX)
			field.lastBlinkReset = os.clock()
		end
	)

	if focused and not field.wasFocused then
		if not readOnly then
			argon:StartTextInput(renderer.Window)
		end
		field.caretX = argon:MeasureText(window, field.text:sub(1, field.cursorPos), textSize, font)
		field.lastBlinkReset = os.clock()
	elseif not focused and field.wasFocused then
		if not readOnly then
			argon:StopTextInput(renderer.Window)
		end
	end
	field.wasFocused = focused

	local changed = false

	if focused then
		if not readOnly then
			local textInputs = renderer.TextInputs
			if textInputs then
				for _, str in textInputs do
					if params.MaxLength then
						str = trimToMaxLength(field.text, str, params.MaxLength)
					end
					if str ~= "" then
						local newText, newPos = insertAt(field.text, field.cursorPos, str)
						field.text = newText
						field.cursorPos = newPos
						field.lastBlinkReset = os.clock()
						changed = true
					end
				end
			end
		end

		local keyDowns = renderer.Keydowns
		if keyDowns then
			for _, key in keyDowns do
				if key == 0x25 then -- left arrow
					field.cursorPos = prevCharPos(field.text, field.cursorPos)
					field.lastBlinkReset = os.clock()
				elseif key == 0x27 then -- right arrow
					field.cursorPos = nextCharPos(field.text, field.cursorPos)
					field.lastBlinkReset = os.clock()
				elseif key == 0x24 then -- home
					field.cursorPos = 0
					field.lastBlinkReset = os.clock()
				elseif key == 0x23 then -- end
					field.cursorPos = #field.text
					field.lastBlinkReset = os.clock()
				elseif key == 0x08 and not readOnly then -- backspace
					local newText, newPos = backspaceAt(field.text, field.cursorPos)
					if newText ~= field.text then
						field.text = newText
						field.cursorPos = newPos
						field.lastBlinkReset = os.clock()
						changed = true
					end
				elseif key == 0x2E and not readOnly then -- delete
					local newText = deleteAt(field.text, field.cursorPos)
					if newText ~= field.text then
						field.text = newText
						field.lastBlinkReset = os.clock()
						changed = true
					end
				elseif key == 0x1B then -- escape
					storage.focusedId = nil
					field.wasFocused = false
					if not readOnly then
						argon:StopTextInput(renderer.Window)
					end
				elseif key == 0x0D then -- return/enter
					if params.OnSubmit then
						params.OnSubmit(field.text)
					end
				end
			end
		end
	end

	if changed and params.OnChange then
		params.OnChange(field.text)
	end

	argon:Save(window)

	argon:ClipRoundRect(window, {
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
	}, cornerRadius, cornerRadius)

	local bgColor = focused and (params.FocusColor or params.Color) or params.Color
	argon:DrawRectangle(window, {
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
		Color = bgColor,
	})

	local hasText = field.text ~= ""
	local displayText = hasText and field.text or (params.placeholder or "")
	local textColor = hasText and params.TextColor or (params.PlaceholderColor or params.TextColor)

	local textHeight = argon:GetFontLineHeight(textSize, font)
	local textAscent = argon:GetFontAscent(textSize, font)

	local caretTarget = argon:MeasureText(window, field.text:sub(1, field.cursorPos), textSize, font)

	if focused then
		local scrollTarget = field.scrollTarget
		if caretTarget - scrollTarget > innerWidth then
			scrollTarget = caretTarget - innerWidth
		end
		if caretTarget - scrollTarget < 0 then
			scrollTarget = caretTarget
		end
		local fullWidth = hasText and argon:MeasureText(window, field.text, textSize, font) or 0
		field.scrollTarget = math.clamp(scrollTarget, 0, math.max(0, fullWidth - innerWidth))
	else
		field.scrollTarget = 0
	end

	local scrollSpeed = params.ScrollLerpSpeed or 20
	field.scrollOffset = smoothTowards(field.scrollOffset, field.scrollTarget, scrollSpeed, dt)
	if math.abs(field.scrollOffset - field.scrollTarget) < 0.05 then
		field.scrollOffset = field.scrollTarget
	end

	local textX = params.x + padding - field.scrollOffset
	local textY = params.y + (params.height - textHeight) / 2 + textAscent

	if displayText ~= "" then
		Text({
			x = textX,
			y = textY,
			TextSize = textSize,
			theme = theme,
			Font = font,
			text = displayText,
			Color = textColor,
			engine_window = window,
		}, dt)
	end

	if focused then
		local caretSpeed = params.CaretLerpSpeed or 20
		field.caretX = smoothTowards(field.caretX, caretTarget, caretSpeed, dt)
		if math.abs(field.caretX - caretTarget) < 0.05 then
			field.caretX = caretTarget
		end

		local blinkOn = (os.clock() - field.lastBlinkReset) % 1 < 0.5
		if blinkOn then
			local cursorX = textX + field.caretX

			argon:DrawRectangle(window, {
				x = cursorX,
				y = params.y + (params.height - textHeight) / 2,
				width = 2,
				height = textHeight,
				Color = params.CursorColor or params.TextColor,
			})
		end
	end

	argon:Restore(window)

	return field.text
end
