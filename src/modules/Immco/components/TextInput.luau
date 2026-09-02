local typedefs = require("../typedefs")
local argon = require("@Argon")
local Text = require("./Text")

local DEFAULT_AUTO_CLOSE_PAIRS = {
	["("] = ")",
	["["] = "]",
	["{"] = "}",
	['"'] = '"',
	["'"] = "'",
}

local BRACKET_PAIRS = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local BRACKET_PAIRS_REVERSE = { [")"] = "(", ["]"] = "[", ["}"] = "{" }

local isModifierDown

local SDLK_BACKSPACE = 0x08
local SDLK_TAB = 0x09
local SDLK_RETURN = 0x0D
local SDLK_ESCAPE = 0x1B
local SDLK_A = string.byte("a")
local SDLK_C = string.byte("c")
local SDLK_D = string.byte("d")
local SDLK_K = string.byte("k")
local SDLK_SLASH = 0x2F
local SDLK_V = string.byte("v")
local SDLK_X = string.byte("x")
local SDLK_Y = string.byte("y")
local SDLK_Z = string.byte("z")
local SDLK_RIGHT = 0x4000004F
local SDLK_LEFT = 0x40000050
local SDLK_DOWN = 0x40000051
local SDLK_UP = 0x40000052
local SDLK_HOME = 0x4000004A
local SDLK_PAGEUP = 0x4000004B
local SDLK_END = 0x4000004D
local SDLK_PAGEDOWN = 0x4000004E
local SDLK_DELETE = 0x4000004C

local LUAU_KEYWORDS = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
	["type"] = true,
	["export"] = true,
	["continue"] = true,
}

local DEFAULT_SYNTAX_COLORS = {
	Keyword = argon:RGBA(197, 134, 192),
	String = argon:RGBA(206, 145, 120),
	Comment = argon:RGBA(106, 153, 85),
	Number = argon:RGBA(181, 206, 168),
}

local function resolveFocus(storage, id, x, y, width, height, clicks, onClickInside)
	if not clicks then
		return storage.focusedId == id
	end
	for _, click in clicks do
		if click.Button == 1 then
			local hit = click.X >= x and click.X <= x + width and click.Y >= y and click.Y <= y + height
			if hit then
				storage.focusedId = id
				if onClickInside then
					onClickInside(click)
				end
			elseif not click.Down and storage.focusedId == id then
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

local function charAt(text: string, pos: number): string
	if pos < 0 or pos >= #text then
		return ""
	end
	local nxt = nextCharPos(text, pos)
	return text:sub(pos + 1, nxt)
end

local function isWordByteChar(ch: string): boolean
	return ch ~= "" and ch:match("^[%w_]$") ~= nil
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

local function selectionRange(field): (number?, number?)
	local anchor = field.selectionAnchor
	if anchor == nil or anchor == field.cursorPos then
		return nil, nil
	end
	return math.min(anchor, field.cursorPos), math.max(anchor, field.cursorPos)
end

local function selectedText(field): string
	local startPos, endPos = selectionRange(field)
	if not startPos or not endPos then
		return ""
	end
	return field.text:sub(startPos + 1, endPos)
end

local function deleteSelection(field): boolean
	local startPos, endPos = selectionRange(field)
	if not startPos or not endPos then
		return false
	end
	field.text = field.text:sub(1, startPos) .. field.text:sub(endPos + 1)
	field.cursorPos = startPos
	field.selectionAnchor = nil
	field.preferredCaretX = nil
	return true
end

local function updateSelectionAfterMove(field, oldCursor: number)
	if isModifierDown("Shift") then
		if field.selectionAnchor == nil then
			field.selectionAnchor = oldCursor
		end
	else
		field.selectionAnchor = nil
	end
end

local function snapshotField(field)
	return {
		text = field.text,
		cursorPos = field.cursorPos,
		selectionAnchor = field.selectionAnchor,
		scrollOffset = field.scrollOffset,
		scrollTarget = field.scrollTarget,
		scrollY = field.scrollY,
		scrollTargetY = field.scrollTargetY,
	}
end

local function restoreSnapshot(field, snapshot)
	field.text = snapshot.text or ""
	field.cursorPos = clampCursor(field.text, snapshot.cursorPos or #field.text)
	field.selectionAnchor = snapshot.selectionAnchor
	field.scrollOffset = snapshot.scrollOffset or 0
	field.scrollTarget = snapshot.scrollTarget or field.scrollOffset
	field.scrollY = snapshot.scrollY or 0
	field.scrollTargetY = snapshot.scrollTargetY or field.scrollY
	field.preferredCaretX = nil
end

local function pushUndoSnapshot(field, snapshot, limit: number?)
	field.undoStack = field.undoStack or {}
	field.redoStack = field.redoStack or {}
	local last = field.undoStack[#field.undoStack]
	if last and last.text == snapshot.text and last.cursorPos == snapshot.cursorPos then
		return
	end
	table.insert(field.undoStack, snapshot)
	local maxUndo = limit or 100
	while #field.undoStack > maxUndo do
		table.remove(field.undoStack, 1)
	end
	table.clear(field.redoStack)
end

local function undo(field): boolean
	field.undoStack = field.undoStack or {}
	field.redoStack = field.redoStack or {}
	local snapshot = table.remove(field.undoStack)
	if not snapshot then
		return false
	end
	table.insert(field.redoStack, snapshotField(field))
	restoreSnapshot(field, snapshot)
	return true
end

local function redo(field): boolean
	field.undoStack = field.undoStack or {}
	field.redoStack = field.redoStack or {}
	local snapshot = table.remove(field.redoStack)
	if not snapshot then
		return false
	end
	table.insert(field.undoStack, snapshotField(field))
	restoreSnapshot(field, snapshot)
	return true
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

local function buildLines(text: string)
	local lines = {}
	local startPos = 0
	local index = 1

	while index <= #text do
		if text:sub(index, index) == "\n" then
			table.insert(lines, {
				Text = text:sub(startPos + 1, index - 1),
				Start = startPos,
				End = index - 1,
			})
			startPos = index
		end
		index += 1
	end

	table.insert(lines, {
		Text = text:sub(startPos + 1),
		Start = startPos,
		End = #text,
	})

	return lines
end

local function lineIndexFromCursor(lines, cursorPos: number): number
	for index, line in lines do
		if cursorPos <= line.End then
			return index
		end
	end
	return #lines
end

local function cursorFromPoint(window, lines, font, textSize: number, relativeX: number, lineIndex: number): number
	local line = lines[math.clamp(lineIndex, 1, #lines)]
	return line.Start + cursorPosFromX(window, line.Text, font, textSize, relativeX)
end

local function cursorXInLine(window, line, cursorPos: number, font, textSize: number): number
	local localPos = math.clamp(cursorPos - line.Start, 0, #line.Text)
	return argon:MeasureText(window, line.Text:sub(1, localPos), textSize, font)
end

local function moveCursorVertical(
	window,
	lines,
	cursorPos: number,
	delta: number,
	preferredX: number?,
	font,
	textSize: number
): (number, number)
	local lineIndex = lineIndexFromCursor(lines, cursorPos)
	local line = lines[lineIndex]
	local desiredX = preferredX or cursorXInLine(window, line, cursorPos, font, textSize)
	local targetLineIndex = math.clamp(lineIndex + delta, 1, #lines)
	local targetLine = lines[targetLineIndex]
	return cursorFromPoint(window, lines, font, textSize, desiredX, targetLineIndex), desiredX
end

local function lineStartForCursor(lines, cursorPos: number): number
	return lines[lineIndexFromCursor(lines, cursorPos)].Start
end

local function lineEndForCursor(lines, cursorPos: number): number
	return lines[lineIndexFromCursor(lines, cursorPos)].End
end

local function fullLineRange(lines, cursorPos: number, textLength: number): (number, number, number)
	local lineIndex = lineIndexFromCursor(lines, cursorPos)
	local line = lines[lineIndex]
	local startPos = line.Start
	local endPos = line.End
	if lineIndex < #lines then
		endPos += 1
	elseif lineIndex > 1 and startPos > 0 then
		startPos -= 1
	end
	return startPos, math.clamp(endPos, startPos, textLength), lineIndex
end

local function leadingIndent(text: string): string
	return text:match("^[ \t]*") or ""
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smoothTowards(current: number, target: number, speed: number, dt: number): number
	local t = 1 - math.exp(-speed * dt)
	return lerp(current, target, t)
end

local function withTransparency(color, transparency: number?)
	if not color or transparency == nil then
		return color
	end

	local alpha = math.clamp(1 - transparency, 0, 1)
	return {
		R = color.R,
		G = color.G,
		B = color.B,
		A = (color.A or 1) * alpha,
	}
end

local function isVisibleColor(color): boolean
	return color ~= nil and (color.A == nil or color.A > 0)
end

local function prevWordPos(text: string, pos: number): number
	pos = clampCursor(text, pos)
	if pos <= 0 then
		return 0
	end
	local p = pos
	while p > 0 do
		local prevP = prevCharPos(text, p)
		if charAt(text, prevP):match("%s") then
			p = prevP
		else
			break
		end
	end
	if p <= 0 then
		return 0
	end
	local firstCh = charAt(text, prevCharPos(text, p))
	local wantWord = isWordByteChar(firstCh)
	while p > 0 do
		local pp = prevCharPos(text, p)
		local ch = charAt(text, pp)
		if ch == "" or ch:match("%s") or isWordByteChar(ch) ~= wantWord then
			break
		end
		p = pp
	end
	return p
end

local function nextWordPos(text: string, pos: number): number
	pos = clampCursor(text, pos)
	local len = #text
	if pos >= len then
		return len
	end
	local p = pos
	while p < len and charAt(text, p):match("%s") do
		p = nextCharPos(text, p)
	end
	if p >= len then
		return len
	end
	local wantWord = isWordByteChar(charAt(text, p))
	while p < len do
		local ch = charAt(text, p)
		if ch == "" or ch:match("%s") or isWordByteChar(ch) ~= wantWord then
			break
		end
		p = nextCharPos(text, p)
	end
	return p
end

local function getAutoClosePairs(params)
	if params.AutoCloseBrackets == true then
		return DEFAULT_AUTO_CLOSE_PAIRS
	elseif type(params.AutoCloseBrackets) == "table" then
		return params.AutoCloseBrackets
	end
	return nil
end

local function getClosingCharsSet(autoClosePairs)
	local set = {}
	for _, closeChar in autoClosePairs do
		set[closeChar] = true
	end
	return set
end

local function findMatchingBracket(text: string, cursorPos: number): (number?, number?)
	local candidates = {}
	if cursorPos > 0 then
		table.insert(candidates, cursorPos)
	end
	if cursorPos < #text then
		table.insert(candidates, cursorPos + 1)
	end

	for _, charPos in candidates do
		local ch = text:sub(charPos, charPos)
		if BRACKET_PAIRS[ch] then
			local target = BRACKET_PAIRS[ch]
			local depth = 0
			for i = charPos, #text do
				local c2 = text:sub(i, i)
				if c2 == ch then
					depth += 1
				elseif c2 == target then
					depth -= 1
					if depth == 0 then
						return charPos, i
					end
				end
			end
		elseif BRACKET_PAIRS_REVERSE[ch] then
			local openCh = BRACKET_PAIRS_REVERSE[ch]
			local depth = 0
			for i = charPos, 1, -1 do
				local c2 = text:sub(i, i)
				if c2 == ch then
					depth += 1
				elseif c2 == openCh then
					depth -= 1
					if depth == 0 then
						return i, charPos
					end
				end
			end
		end
	end

	return nil, nil
end

-- Code editor customization: lightweight built-in Luau syntax highlighter --------------------

local function tokenizeLuau(text: string, colors)
	local segments = {}
	local pos = 1
	local len = #text

	while pos <= len do
		local c = text:sub(pos, pos)
		if c == '"' or c == "'" then
			local quote = c
			local start = pos
			pos += 1
			while pos <= len and text:sub(pos, pos) ~= quote do
				if text:sub(pos, pos) == "\\" then
					pos += 1
				end
				pos += 1
			end
			pos = math.min(pos, len)
			table.insert(segments, { Start = start, End = pos, Color = colors.String })
			pos += 1
		elseif text:sub(pos, pos + 1) == "--" then
			table.insert(segments, { Start = pos, End = len, Color = colors.Comment })
			pos = len + 1
		elseif c:match("%d") then
			local start = pos
			while pos <= len and text:sub(pos, pos):match("[%d%.xXa-fA-F]") do
				pos += 1
			end
			table.insert(segments, { Start = start, End = pos - 1, Color = colors.Number })
		elseif c:match("[%a_]") then
			local start = pos
			while pos <= len and text:sub(pos, pos):match("[%w_]") do
				pos += 1
			end
			local word = text:sub(start, pos - 1)
			if LUAU_KEYWORDS[word] then
				table.insert(segments, { Start = start, End = pos - 1, Color = colors.Keyword })
			end
		else
			pos += 1
		end
	end

	return segments
end

local function getSyntaxHighlighter(params)
	if type(params.SyntaxHighlight) == "function" then
		return params.SyntaxHighlight
	elseif params.Language == "luau" or params.Language == "lua" then
		return tokenizeLuau
	end
	return nil
end

function isModifierDown(name: "Shift" | "Ctrl" | "Alt"): boolean
	if name == "Shift" then
		return argon:IsKeyDown(argon.Key.LeftShift) or argon:IsKeyDown(argon.Key.RightShift)
	elseif name == "Ctrl" then
		return argon:IsKeyDown(argon.Key.LeftCtrl) or argon:IsKeyDown(argon.Key.RightCtrl)
	elseif name == "Alt" then
		return argon:IsKeyDown(argon.Key.LeftAlt) or argon:IsKeyDown(argon.Key.RightAlt)
	end
	return false
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
	local syntaxColors = params.SyntaxColors or theme.SyntaxColors or DEFAULT_SYNTAX_COLORS
	local multiline = params.MultiLine == true or params.CodeEditor == true
	local topAligned = multiline or params.TextYAlignment == "top"

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
			scrollY = 0,
			scrollTargetY = 0,
			preferredCaretX = nil,
			selectionAnchor = nil,
			isSelecting = false,
			minimapDragging = false,
			undoStack = {},
			redoStack = {},
			lastBlinkReset = os.clock(),
		}
		storage[id] = field
	end

	local lines = buildLines(field.text)
	local lineHeight = argon:GetFontLineHeight(textSize, font)
	local textAscent = argon:GetFontAscent(textSize, font)
	local gutterEnabled = params.Gutter == true or params.ShowLineNumbers == true
	local gutterPadding = gutterEnabled and (params.GutterPadding or 8) or 0
	local lineCountWidth = argon:MeasureText(window, tostring(math.max(1, #lines)), textSize, font)
	local gutterWidth = gutterEnabled and math.max(params.GutterWidth or 0, lineCountWidth + gutterPadding * 2) or 0
	local minimapEnabled = multiline and (params.Minimap == true or params.EnableMinimap == true)
	local minimapWidth = minimapEnabled and (params.MinimapWidth or 72) or 0
	local minimapGap = minimapEnabled and (params.MinimapGap or 8) or 0
	local minimapX = params.x + params.width - padding - minimapWidth
	local minimapY = params.y + padding
	local textAreaX = params.x + padding + gutterWidth
	local textAreaRight = minimapEnabled and (minimapX - minimapGap) or (params.x + params.width - padding)
	local innerWidth = math.max(0, textAreaRight - textAreaX)
	local innerHeight = math.max(0, params.height - padding * 2)

	local focused = resolveFocus(
		storage,
		id,
		params.x,
		params.y,
		params.width,
		params.height,
		renderer.PendingClicks,
		function(click)
			local oldCursor = field.cursorPos
			local hitMinimap = minimapEnabled
				and click.X >= minimapX
				and click.X <= minimapX + minimapWidth
				and click.Y >= minimapY
				and click.Y <= minimapY + innerHeight
			if hitMinimap then
				local maxScrollY = math.max(0, #lines * lineHeight - innerHeight)
				local ratio = if innerHeight > 0 then (click.Y - minimapY) / innerHeight else 0
				field.scrollTargetY = math.clamp(ratio * maxScrollY, 0, maxScrollY)
				field.scrollY = field.scrollTargetY
				field.isSelecting = false
				field.minimapDragging = click.Down == true
			else
				local relativeX = (click.X - textAreaX) + field.scrollOffset
				if multiline then
					local clickedLine = math.floor((click.Y - (params.y + padding) + field.scrollY) / lineHeight) + 1
					field.cursorPos = cursorFromPoint(window, lines, font, textSize, relativeX, clickedLine)
				else
					field.cursorPos = cursorPosFromX(window, field.text, font, textSize, relativeX)
				end
				if click.Down then
					field.isSelecting = true
					if isModifierDown("Shift") then
						field.selectionAnchor = field.selectionAnchor or oldCursor
					else
						field.selectionAnchor = field.cursorPos
					end
				elseif field.selectionAnchor == field.cursorPos then
					field.selectionAnchor = nil
				end
			end
			field.preferredCaretX = nil
			field.lastBlinkReset = os.clock()
		end
	)

	if minimapEnabled and field.minimapDragging then
		if argon:IsMouseButtonDown(argon.MouseButton.Left) then
			local mousePos = argon:GetMousePosition()
			local maxScrollY = math.max(0, #lines * lineHeight - innerHeight)
			local ratio = if innerHeight > 0 then (mousePos.Y - minimapY) / innerHeight else 0
			field.scrollTargetY = math.clamp(ratio * maxScrollY, 0, maxScrollY)
			field.scrollY = field.scrollTargetY
		else
			field.minimapDragging = false
		end
	end

	if focused and field.isSelecting then
		if argon:IsMouseButtonDown(argon.MouseButton.Left) then
			local mousePos = argon:GetMousePosition()
			local relativeX = (mousePos.X - textAreaX) + field.scrollOffset
			if multiline then
				local lineIndex = math.floor((mousePos.Y - (params.y + padding) + field.scrollY) / lineHeight) + 1
				field.cursorPos = cursorFromPoint(window, lines, font, textSize, relativeX, lineIndex)
			else
				field.cursorPos = cursorPosFromX(window, field.text, font, textSize, relativeX)
			end
			field.preferredCaretX = nil
			field.lastBlinkReset = os.clock()
		else
			field.isSelecting = false
			if field.selectionAnchor == field.cursorPos then
				field.selectionAnchor = nil
			end
		end
	end

	if focused and not field.wasFocused then
		if not readOnly then
			argon:StartTextInput(renderer.Window)
		end
		local focusedLine = lines[lineIndexFromCursor(lines, field.cursorPos)]
		field.caretX = cursorXInLine(window, focusedLine, field.cursorPos, font, textSize)
		field.lastBlinkReset = os.clock()
	elseif not focused and field.wasFocused then
		if not readOnly then
			argon:StopTextInput(renderer.Window)
		end
	end
	field.wasFocused = focused

	local changed = false
	local beforeEdit = snapshotField(field)
	local skipHistory = false

	if focused then
		if not readOnly then
			local textInputs = renderer.TextInputs
			if textInputs then
				local autoClosePairs = getAutoClosePairs(params)
				local closingCharSet = autoClosePairs and getClosingCharsSet(autoClosePairs) or nil

				for _, str in textInputs do
					if str ~= "" then
						if deleteSelection(field) then
							changed = true
						end
						if params.MaxLength then
							str = trimToMaxLength(field.text, str, params.MaxLength)
						end
						local nextChar = field.text:sub(field.cursorPos + 1, field.cursorPos + 1)
						if
							closingCharSet
							and #str == 1
							and closingCharSet[str]
							and nextChar == str
							and params.AutoCloseSkip ~= false
						then
							-- Code editor customization: step over an already-present closing char
							field.cursorPos = nextCharPos(field.text, field.cursorPos)
							field.preferredCaretX = nil
							field.lastBlinkReset = os.clock()
						else
							local newText, newPos = insertAt(field.text, field.cursorPos, str)
							if autoClosePairs and #str == 1 and autoClosePairs[str] then
								-- Code editor customization: auto-insert the matching closer
								local closeChar = autoClosePairs[str]
								newText = newText:sub(1, newPos) .. closeChar .. newText:sub(newPos + 1)
							end
							field.text = newText
							field.cursorPos = newPos
							field.preferredCaretX = nil
							field.lastBlinkReset = os.clock()
							changed = true
						end
					end
				end
			end
		end

		local keyDowns = renderer.Keydowns
		if keyDowns then
			for _, key in keyDowns do
				local oldCursor = field.cursorPos
				if isModifierDown("Ctrl") and key == SDLK_Z then
					if isModifierDown("Shift") then
						if redo(field) then
							changed = true
							skipHistory = true
							field.lastBlinkReset = os.clock()
						end
					elseif undo(field) then
						changed = true
						skipHistory = true
						field.lastBlinkReset = os.clock()
					end
				elseif isModifierDown("Ctrl") and key == SDLK_Y then
					if redo(field) then
						changed = true
						skipHistory = true
						field.lastBlinkReset = os.clock()
					end
				elseif isModifierDown("Ctrl") and isModifierDown("Shift") and key == SDLK_K and not readOnly then
					lines = buildLines(field.text)
					local startPos, endPos = fullLineRange(lines, field.cursorPos, #field.text)
					field.text = field.text:sub(1, startPos) .. field.text:sub(endPos + 1)
					field.cursorPos = math.min(startPos, #field.text)
					field.selectionAnchor = nil
					field.preferredCaretX = nil
					field.lastBlinkReset = os.clock()
					changed = true
				elseif isModifierDown("Ctrl") and key == SDLK_D and multiline and not readOnly then
					lines = buildLines(field.text)
					local startPos, endPos = fullLineRange(lines, field.cursorPos, #field.text)
					local lineText = field.text:sub(startPos + 1, endPos)
					local insertPos = endPos
					local duplicateText = lineText
					if duplicateText:sub(#duplicateText, #duplicateText) ~= "\n" then
						duplicateText = "\n" .. duplicateText
					end
					field.text = field.text:sub(1, insertPos) .. duplicateText .. field.text:sub(insertPos + 1)
					field.cursorPos = insertPos + #duplicateText
					field.selectionAnchor = nil
					field.preferredCaretX = nil
					field.lastBlinkReset = os.clock()
					changed = true
				elseif isModifierDown("Ctrl") and key == SDLK_A then
					field.selectionAnchor = 0
					field.cursorPos = #field.text
					field.preferredCaretX = nil
					field.lastBlinkReset = os.clock()
				elseif isModifierDown("Ctrl") and key == SDLK_C then
					local text = selectedText(field)
					if text ~= "" then
						argon:SetClipboard(text)
					end
				elseif isModifierDown("Ctrl") and key == SDLK_X and not readOnly then
					local text = selectedText(field)
					if text ~= "" then
						argon:SetClipboard(text)
						deleteSelection(field)
						field.lastBlinkReset = os.clock()
						changed = true
					end
				elseif isModifierDown("Ctrl") and key == SDLK_V and not readOnly then
					local pasteText = argon:GetClipboard() or ""
					if pasteText ~= "" then
						deleteSelection(field)
						if params.MaxLength then
							pasteText = trimToMaxLength(field.text, pasteText, params.MaxLength)
						end
						if pasteText ~= "" then
							local newText, newPos = insertAt(field.text, field.cursorPos, pasteText)
							field.text = newText
							field.cursorPos = newPos
							field.selectionAnchor = nil
							field.preferredCaretX = nil
							field.lastBlinkReset = os.clock()
							changed = true
						end
					end
				elseif key == SDLK_LEFT then -- left arrow
					if params.WordNavigation and isModifierDown("Ctrl") then
						field.cursorPos = prevWordPos(field.text, field.cursorPos)
					else
						field.cursorPos = prevCharPos(field.text, field.cursorPos)
					end
					updateSelectionAfterMove(field, oldCursor)
					field.lastBlinkReset = os.clock()
				elseif key == SDLK_RIGHT then -- right arrow
					if params.WordNavigation and isModifierDown("Ctrl") then
						field.cursorPos = nextWordPos(field.text, field.cursorPos)
					else
						field.cursorPos = nextCharPos(field.text, field.cursorPos)
					end
					updateSelectionAfterMove(field, oldCursor)
					field.lastBlinkReset = os.clock()
				elseif key == SDLK_UP and multiline then -- up arrow
					lines = buildLines(field.text)
					field.cursorPos, field.preferredCaretX =
						moveCursorVertical(window, lines, field.cursorPos, -1, field.preferredCaretX, font, textSize)
					updateSelectionAfterMove(field, oldCursor)
					field.lastBlinkReset = os.clock()
				elseif key == SDLK_DOWN and multiline then -- down arrow
					lines = buildLines(field.text)
					field.cursorPos, field.preferredCaretX =
						moveCursorVertical(window, lines, field.cursorPos, 1, field.preferredCaretX, font, textSize)
					updateSelectionAfterMove(field, oldCursor)
					field.lastBlinkReset = os.clock()
				elseif key == SDLK_PAGEUP and multiline then -- page up
					lines = buildLines(field.text)
					local pageLines = math.max(1, math.floor(innerHeight / lineHeight) - 1)
					field.cursorPos, field.preferredCaretX = moveCursorVertical(
						window,
						lines,
						field.cursorPos,
						-pageLines,
						field.preferredCaretX,
						font,
						textSize
					)
					field.scrollTargetY = math.max(0, field.scrollTargetY - pageLines * lineHeight)
					updateSelectionAfterMove(field, oldCursor)
					field.lastBlinkReset = os.clock()
				elseif key == SDLK_PAGEDOWN and multiline then -- page down
					lines = buildLines(field.text)
					local pageLines = math.max(1, math.floor(innerHeight / lineHeight) - 1)
					field.cursorPos, field.preferredCaretX = moveCursorVertical(
						window,
						lines,
						field.cursorPos,
						pageLines,
						field.preferredCaretX,
						font,
						textSize
					)
					field.scrollTargetY = math.min(
						math.max(0, #lines * lineHeight - innerHeight),
						field.scrollTargetY + pageLines * lineHeight
					)
					updateSelectionAfterMove(field, oldCursor)
					field.lastBlinkReset = os.clock()
				elseif key == SDLK_HOME then -- home
					if multiline then
						lines = buildLines(field.text)
						field.cursorPos = lineStartForCursor(lines, field.cursorPos)
					else
						field.cursorPos = 0
					end
					field.preferredCaretX = nil
					updateSelectionAfterMove(field, oldCursor)
					field.lastBlinkReset = os.clock()
				elseif key == SDLK_END then -- end
					if multiline then
						lines = buildLines(field.text)
						field.cursorPos = lineEndForCursor(lines, field.cursorPos)
					else
						field.cursorPos = #field.text
					end
					field.preferredCaretX = nil
					updateSelectionAfterMove(field, oldCursor)
					field.lastBlinkReset = os.clock()
				elseif key == SDLK_TAB and not readOnly and params.AllowTab then -- tab
					-- Code editor customization: indent / outdent
					local tabSize = params.TabSize or 4
					local insertSpaces = params.InsertSpacesForTab ~= false
					if field.selectionAnchor ~= nil and not isModifierDown("Shift") then
						deleteSelection(field)
						changed = true
					end
					if isModifierDown("Shift") then
						local removed = 0
						local newText = field.text
						local removeAt = 0
						if multiline then
							lines = buildLines(field.text)
							local line = lines[lineIndexFromCursor(lines, field.cursorPos)]
							removeAt = line.Start
							local lineText = line.Text
							if insertSpaces then
								while removed < tabSize and lineText:sub(removed + 1, removed + 1) == " " do
									removed += 1
								end
							elseif lineText:sub(1, 1) == "\t" then
								removed = 1
							end
							newText = field.text:sub(1, removeAt) .. field.text:sub(removeAt + removed + 1)
						else
							removeAt = 0
							if insertSpaces then
								while removed < tabSize and newText:sub(1, 1) == " " do
									newText = newText:sub(2)
									removed += 1
								end
							elseif newText:sub(1, 1) == "\t" then
								newText = newText:sub(2)
								removed = 1
							end
						end
						if removed > 0 then
							field.text = newText
							if multiline and field.cursorPos >= removeAt + removed then
								field.cursorPos -= removed
							else
								field.cursorPos = math.max(0, field.cursorPos - removed)
							end
							field.preferredCaretX = nil
							field.lastBlinkReset = os.clock()
							changed = true
						end
					else
						local insertStr = insertSpaces and string.rep(" ", tabSize) or "\t"
						if params.MaxLength then
							insertStr = trimToMaxLength(field.text, insertStr, params.MaxLength)
						end
						if insertStr ~= "" then
							local newText, newPos = insertAt(field.text, field.cursorPos, insertStr)
							field.text = newText
							field.cursorPos = newPos
							field.preferredCaretX = nil
							field.lastBlinkReset = os.clock()
							changed = true
						end
					end
				elseif
					params.CommentPrefix
					and not readOnly
					and key == (params.CommentToggleKey or SDLK_SLASH)
					and isModifierDown("Ctrl")
				then
					-- Code editor customization: toggle a leading comment prefix
					local prefix = params.CommentPrefix
					local lineStart = 0
					local lineEnd = #field.text
					if multiline then
						lines = buildLines(field.text)
						local line = lines[lineIndexFromCursor(lines, field.cursorPos)]
						lineStart = line.Start
						lineEnd = line.End
					end
					local lineText = field.text:sub(lineStart + 1, lineEnd)
					local leadingWhitespace = lineText:match("^[ \t]*") or ""
					local rest = lineText:sub(#leadingWhitespace + 1)
					local beforeLine = field.text:sub(1, lineStart)
					local afterLine = field.text:sub(lineEnd + 1)
					if rest:sub(1, #prefix) == prefix then
						local newRest = rest:sub(#prefix + 1)
						if newRest:sub(1, 1) == " " then
							newRest = newRest:sub(2)
						end
						local removed = #rest - #newRest
						field.cursorPos = math.max(lineStart, field.cursorPos - removed)
						field.text = beforeLine .. leadingWhitespace .. newRest .. afterLine
					else
						field.text = beforeLine .. leadingWhitespace .. prefix .. " " .. rest .. afterLine
						field.cursorPos = field.cursorPos + (#prefix + 1)
					end
					field.preferredCaretX = nil
					field.lastBlinkReset = os.clock()
					changed = true
				elseif key == SDLK_BACKSPACE and not readOnly then -- backspace
					if deleteSelection(field) then
						field.lastBlinkReset = os.clock()
						changed = true
					elseif params.WordNavigation and isModifierDown("Ctrl") then
						local wordStart = prevWordPos(field.text, field.cursorPos)
						if wordStart < field.cursorPos then
							field.text = field.text:sub(1, wordStart) .. field.text:sub(field.cursorPos + 1)
							field.cursorPos = wordStart
							field.preferredCaretX = nil
							field.lastBlinkReset = os.clock()
							changed = true
						end
					else
						-- Code editor customization: delete an empty auto-closed pair together
						local autoClosePairs = getAutoClosePairs(params)
						local prevCh = field.cursorPos > 0 and field.text:sub(field.cursorPos, field.cursorPos) or ""
						local nextCh = field.text:sub(field.cursorPos + 1, field.cursorPos + 1)
						if autoClosePairs and prevCh ~= "" and autoClosePairs[prevCh] == nextCh then
							field.text = field.text:sub(1, field.cursorPos - 1) .. field.text:sub(field.cursorPos + 2)
							field.cursorPos -= 1
							field.preferredCaretX = nil
							field.lastBlinkReset = os.clock()
							changed = true
						else
							local newText, newPos = backspaceAt(field.text, field.cursorPos)
							if newText ~= field.text then
								field.text = newText
								field.cursorPos = newPos
								field.preferredCaretX = nil
								field.lastBlinkReset = os.clock()
								changed = true
							end
						end
					end
				elseif key == SDLK_DELETE and not readOnly then -- delete
					if deleteSelection(field) then
						field.lastBlinkReset = os.clock()
						changed = true
					elseif params.WordNavigation and isModifierDown("Ctrl") then
						local wordEnd = nextWordPos(field.text, field.cursorPos)
						if wordEnd > field.cursorPos then
							field.text = field.text:sub(1, field.cursorPos) .. field.text:sub(wordEnd + 1)
							field.preferredCaretX = nil
							field.lastBlinkReset = os.clock()
							changed = true
						end
					else
						local newText = deleteAt(field.text, field.cursorPos)
						if newText ~= field.text then
							field.text = newText
							field.preferredCaretX = nil
							field.lastBlinkReset = os.clock()
							changed = true
						end
					end
				elseif key == SDLK_ESCAPE then -- escape
					storage.focusedId = nil
					field.wasFocused = false
					if not readOnly then
						argon:StopTextInput(renderer.Window)
					end
				elseif key == SDLK_RETURN then -- return/enter
					if multiline and not readOnly then
						if deleteSelection(field) then
							changed = true
						end
						lines = buildLines(field.text)
						local line = lines[lineIndexFromCursor(lines, field.cursorPos)]
						local insertText = "\n"
						if params.AutoIndent ~= false then
							insertText ..= leadingIndent(line.Text)
						end
						local newText, newPos = insertAt(field.text, field.cursorPos, insertText)
						field.text = newText
						field.cursorPos = newPos
						field.preferredCaretX = nil
						field.lastBlinkReset = os.clock()
						changed = true
					elseif params.OnSubmit then
						params.OnSubmit(field.text)
					end
				end
			end
		end
	end

	if changed then
		if not skipHistory and beforeEdit.text ~= field.text then
			pushUndoSnapshot(field, beforeEdit, params.UndoLimit)
		end
		if params.OnChange then
			params.OnChange(field.text)
		end
	end

	argon:Save(window)

	argon:ClipRoundRect(window, {
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
	}, cornerRadius, cornerRadius)

	local bgColor =
		withTransparency(focused and (params.FocusColor or params.Color) or params.Color, params.BackgroundTransparency)
	if isVisibleColor(bgColor) then
		argon:DrawRectangle(window, {
			x = params.x,
			y = params.y,
			width = params.width,
			height = params.height,
			Color = bgColor,
		})
	end

	lines = buildLines(field.text)
	local hasText = field.text ~= ""
	local currentLineIndex = lineIndexFromCursor(lines, field.cursorPos)
	local currentLine = lines[currentLineIndex]
	local caretTarget = cursorXInLine(window, currentLine, field.cursorPos, font, textSize)

	if
		multiline
		and renderer:isMouseInRect({
			x = params.x,
			y = params.y,
			width = params.width,
			height = params.height,
		})
	then
		local wheelDelta = argon:GetMouseWheelMove()
		if wheelDelta ~= 0 then
			local maxScrollY = math.max(0, #lines * lineHeight - innerHeight)
			field.scrollTargetY =
				math.clamp(field.scrollTargetY - wheelDelta * (params.ScrollSpeed or lineHeight * 3), 0, maxScrollY)
		end
	end

	if focused then
		local scrollTarget = field.scrollTarget
		if caretTarget - scrollTarget > innerWidth then
			scrollTarget = caretTarget - innerWidth
		end
		if caretTarget - scrollTarget < 0 then
			scrollTarget = caretTarget
		end
		local fullWidth = argon:MeasureText(window, currentLine.Text, textSize, font)
		field.scrollTarget = math.clamp(scrollTarget, 0, math.max(0, fullWidth - innerWidth))

		if multiline then
			local caretTop = (currentLineIndex - 1) * lineHeight
			local scrollTargetY = field.scrollTargetY
			if caretTop + lineHeight - scrollTargetY > innerHeight then
				scrollTargetY = caretTop + lineHeight - innerHeight
			end
			if caretTop - scrollTargetY < 0 then
				scrollTargetY = caretTop
			end
			field.scrollTargetY = math.clamp(scrollTargetY, 0, math.max(0, #lines * lineHeight - innerHeight))
		end
	else
		field.scrollTarget = 0
		if not multiline then
			field.scrollTargetY = 0
		end
	end

	local scrollSpeed = params.ScrollLerpSpeed or 20
	field.scrollOffset = smoothTowards(field.scrollOffset, field.scrollTarget, scrollSpeed, dt)
	field.scrollY = smoothTowards(field.scrollY or 0, field.scrollTargetY or 0, scrollSpeed, dt)
	if math.abs(field.scrollOffset - field.scrollTarget) < 0.05 then
		field.scrollOffset = field.scrollTarget
	end
	if math.abs(field.scrollY - field.scrollTargetY) < 0.05 then
		field.scrollY = field.scrollTargetY
	end

	local textX = params.x + padding + gutterWidth - field.scrollOffset
	local firstBaselineY = if topAligned
		then params.y + padding + textAscent - field.scrollY
		else params.y + (params.height - lineHeight) / 2 + textAscent
	local textColor = if hasText then params.TextColor else (params.PlaceholderColor or params.TextColor)
	local visibleFirstLine = if multiline then math.max(1, math.floor(field.scrollY / lineHeight) + 1) else 1
	local visibleLastLine = if multiline
		then math.min(#lines, math.ceil((field.scrollY + innerHeight) / lineHeight) + 1)
		else 1

	if multiline and params.HighlightCurrentLine ~= false then
		argon:DrawRectangle(window, {
			x = textAreaX,
			y = firstBaselineY + (currentLineIndex - 1) * lineHeight - textAscent,
			width = innerWidth,
			height = lineHeight,
			Color = params.CurrentLineColor or argon:RGBA(255, 255, 255, 0.06),
		})
	end

	if gutterEnabled then
		local gutterColor = withTransparency(
			params.GutterColor or params.Color,
			params.GutterBackgroundTransparency or params.BackgroundTransparency
		)
		if isVisibleColor(gutterColor) then
			argon:DrawRectangle(window, {
				x = params.x,
				y = params.y,
				width = gutterWidth,
				height = params.height,
				Color = gutterColor,
			})
		end

		for lineIndex = visibleFirstLine, visibleLastLine do
			local label = tostring(lineIndex)
			local labelWidth = argon:MeasureText(window, label, textSize, font)
			Text({
				x = params.x + gutterWidth - gutterPadding - labelWidth,
				y = firstBaselineY + (lineIndex - 1) * lineHeight,
				TextSize = textSize,
				theme = theme,
				Font = font,
				text = label,
				Color = params.GutterTextColor or params.PlaceholderColor or params.TextColor,
				engine_window = window,
			}, dt)
		end
	end

	if minimapEnabled then
		local minimapBg = withTransparency(
			params.MinimapColor or params.Color or argon:RGBA(0, 0, 0, 0.2),
			params.MinimapBackgroundTransparency
		)
		if isVisibleColor(minimapBg) then
			argon:DrawRectangle(window, {
				x = minimapX,
				y = minimapY,
				width = minimapWidth,
				height = innerHeight,
				Color = minimapBg,
			})
		end

		local mapScale = if #lines > 0 then innerHeight / #lines else innerHeight
		local mapLineHeight = math.max(1, math.min(params.MinimapLineHeight or 2, mapScale))
		local mapPadding = params.MinimapPadding or 4
		local maxMapWidth = math.max(1, minimapWidth - mapPadding * 2)
		local mapTextColor = params.MinimapTextColor or params.PlaceholderColor or params.TextColor

		for lineIndex, line in lines do
			local y = minimapY + (lineIndex - 1) * mapScale
			if y > minimapY + innerHeight then
				break
			end
			if line.Text ~= "" and y + mapLineHeight >= minimapY then
				local lineWidth = math.clamp(#line.Text * (params.MinimapCharWidth or 0.7), 2, maxMapWidth)
				local color = mapTextColor
				local trimmed = line.Text:match("^%s*(.-)%s*$") or line.Text
				if trimmed:sub(1, 2) == "--" then
					color = syntaxColors.Comment
				elseif trimmed:match("^local%s") or trimmed:match("^function%s") or trimmed:match("^return%s") then
					color = syntaxColors.Keyword
				end
				argon:DrawRectangle(window, {
					x = minimapX + mapPadding,
					y = y,
					width = lineWidth,
					height = mapLineHeight,
					Color = color,
				})
			end
		end

		local maxScrollY = math.max(0, #lines * lineHeight - innerHeight)
		local viewportRatio = if #lines * lineHeight > 0 then innerHeight / (#lines * lineHeight) else 1
		local viewportHeight = math.clamp(innerHeight * viewportRatio, 14, innerHeight)
		local viewportY = if maxScrollY > 0
			then minimapY + (field.scrollY / maxScrollY) * math.max(0, innerHeight - viewportHeight)
			else minimapY
		argon:DrawRectangle(window, {
			x = minimapX,
			y = viewportY,
			width = minimapWidth,
			height = viewportHeight,
			Color = params.MinimapViewportColor or argon:RGBA(255, 255, 255, 0.13),
		})

		argon:DrawRectangle(window, {
			x = minimapX,
			y = minimapY + (currentLineIndex - 1) * mapScale,
			width = minimapWidth,
			height = math.max(1, mapLineHeight),
			Color = params.MinimapCursorLineColor or params.CursorColor or params.TextColor,
		})
	end

	if params.IndentGuides then
		local tabSize = params.TabSize or 4
		local guideColor = params.IndentGuideColor or params.PlaceholderColor or params.TextColor
		local unitWidth = argon:MeasureText(window, string.rep(" ", tabSize), textSize, font)
		if unitWidth > 0 then
			for lineIndex = visibleFirstLine, visibleLastLine do
				local line = lines[lineIndex]
				local leading = line.Text:match("^[ \t]*") or ""
				local indentColumns = 0
				for index = 1, #leading do
					if leading:sub(index, index) == "\t" then
						indentColumns += tabSize
					else
						indentColumns += 1
					end
				end
				local guideCount = math.floor(indentColumns / tabSize)
				for guideIndex = 1, guideCount do
					local xPos = textX + guideIndex * unitWidth
					argon:DrawRectangle(window, {
						x = xPos,
						y = firstBaselineY + (lineIndex - 1) * lineHeight - textAscent,
						width = 1,
						height = lineHeight,
						Color = guideColor,
					})
				end
			end
		end
	end

	local selectionStart, selectionEnd = selectionRange(field)
	if selectionStart and selectionEnd then
		local selectionColor = params.SelectionColor or argon:RGBA(51, 103, 209, 0.45)
		for lineIndex = visibleFirstLine, visibleLastLine do
			local line = lines[lineIndex]
			local startPos = math.max(selectionStart, line.Start)
			local endPos = math.min(selectionEnd, line.End)
			if startPos < endPos or (selectionEnd > line.End and selectionStart <= line.End) then
				local localStart = math.clamp(startPos - line.Start, 0, #line.Text)
				local localEnd = math.clamp(endPos - line.Start, localStart, #line.Text)
				local prefixWidth = argon:MeasureText(window, line.Text:sub(1, localStart), textSize, font)
				local selectionWidth =
					argon:MeasureText(window, line.Text:sub(localStart + 1, localEnd), textSize, font)
				if selectionWidth <= 0 then
					selectionWidth = argon:MeasureText(window, " ", textSize, font)
				end
				argon:DrawRectangle(window, {
					x = textX + prefixWidth,
					y = firstBaselineY + (lineIndex - 1) * lineHeight - textAscent,
					width = selectionWidth,
					height = lineHeight,
					Color = selectionColor,
				})
			end
		end
	end

	if params.HighlightMatchingBracket and focused and hasText then
		local openPos, closePos = findMatchingBracket(field.text, field.cursorPos)
		if openPos and closePos then
			local matchColor = params.MatchingBracketColor or params.CursorColor or params.TextColor
			for _, bracketPos in { openPos, closePos } do
				local lineIndex = lineIndexFromCursor(lines, bracketPos - 1)
				local line = lines[lineIndex]
				local localPos = math.clamp(bracketPos - 1 - line.Start, 0, #line.Text)
				local charWidth = argon:MeasureText(window, field.text:sub(bracketPos, bracketPos), textSize, font)
				local prefixWidth = argon:MeasureText(window, line.Text:sub(1, localPos), textSize, font)
				argon:DrawRectangle(window, {
					x = textX + prefixWidth,
					y = firstBaselineY + (lineIndex - 1) * lineHeight - textAscent,
					width = charWidth,
					height = lineHeight,
					Color = matchColor,
				})
			end
		end
	end

	if hasText then
		local highlightFn = getSyntaxHighlighter(params)
		for lineIndex = visibleFirstLine, visibleLastLine do
			local line = lines[lineIndex]
			local lineY = firstBaselineY + (lineIndex - 1) * lineHeight
			if line.Text ~= "" then
				Text({
					x = textX,
					y = lineY,
					TextSize = textSize,
					theme = theme,
					Font = font,
					text = line.Text,
					Color = textColor,
					engine_window = window,
				}, dt)

				if highlightFn then
					local segments = highlightFn(line.Text, syntaxColors)
					for _, segment in segments do
						if segment.Start >= 1 and segment.End >= segment.Start and segment.End <= #line.Text then
							local prefixWidth =
								argon:MeasureText(window, line.Text:sub(1, segment.Start - 1), textSize, font)
							Text({
								x = textX + prefixWidth,
								y = lineY,
								TextSize = textSize,
								theme = theme,
								Font = font,
								text = line.Text:sub(segment.Start, segment.End),
								Color = segment.Color,
								engine_window = window,
							}, dt)
						end
					end
				end
			end
		end
	elseif params.placeholder and params.placeholder ~= "" then
		Text({
			x = textX,
			y = firstBaselineY,
			TextSize = textSize,
			theme = theme,
			Font = font,
			text = params.placeholder,
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
			local cursorY = firstBaselineY + (currentLineIndex - 1) * lineHeight - textAscent

			argon:DrawRectangle(window, {
				x = cursorX,
				y = cursorY,
				width = 2,
				height = lineHeight,
				Color = params.CursorColor or params.TextColor,
			})
		end
	end

	argon:Restore(window)

	return field.text
end
