local typedefs = require("../typedefs")
local Rectangle = require("./Rectangle")
local Text = require("./Text")
local argon = require("@Argon")

local LEFT_MOUSE_BUTTON = 1
local DEFAULT_ROW_HEIGHT = 28
local DEFAULT_CELL_PADDING = 8
local DEFAULT_TEXT_SIZE = 13

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smoothTowards(current: number, target: number, speed: number, dt: number): number
	local t = 1 - math.exp(-speed * dt)
	return lerp(current, target, t)
end

local function cellText(cell): string
	if cell == nil then
		return ""
	elseif type(cell) == "table" then
		return cell.Text ~= nil and tostring(cell.Text) or ""
	end
	return tostring(cell)
end

local function cellColor(cell, default)
	if type(cell) == "table" and cell.Color then
		return cell.Color
	end
	return default
end

local function cellAlign(cell, default: string): string
	if type(cell) == "table" and cell.Align then
		return cell.Align
	end
	return default
end

local function getColumnCount(data): number
	local count = 0
	for _, row in data do
		count = math.max(count, #row)
	end
	return math.max(count, 1)
end

local function computeColumnWidths(totalWidth: number, colCount: number, explicit: { number }?): { number }
	local widths = table.create(colCount, 0)

	if explicit then
		local usedWidth = 0
		local explicitCount = 0
		for i = 1, colCount do
			if explicit[i] then
				widths[i] = explicit[i]
				usedWidth += explicit[i]
				explicitCount += 1
			end
		end
		local remainingCols = colCount - explicitCount
		local remainingWidth = math.max(0, totalWidth - usedWidth)
		local shareWidth = (remainingCols > 0) and (remainingWidth / remainingCols) or 0
		for i = 1, colCount do
			if not explicit[i] then
				widths[i] = shareWidth
			end
		end
	else
		local shareWidth = totalWidth / colCount
		for i = 1, colCount do
			widths[i] = shareWidth
		end
	end

	return widths
end

local function alignTextX(align: string, cellX: number, cellWidth: number, textWidth: number, padding: number): number
	if align == "center" then
		return cellX + (cellWidth - textWidth) / 2
	elseif align == "right" then
		return cellX + cellWidth - padding - textWidth
	end
	return cellX + padding
end

return function(params: typedefs.TableParams, dt: number): (number, number, number)
	local window = params.engine_window
	local theme = params.theme
	local storage = params.RetainedStorage
	local id = params.id
	local renderer = params.renderer

	assert(storage, "Table requires params.RetainedStorage")
	assert(id, "Table requires params.id")
	assert(renderer, "Table requires params.renderer")

	local data = params.Data or {}
	local hasHeader = params.HasHeader == true
	local colCount = getColumnCount(data)
	local rowCount = #data
	local bodyRowCount = hasHeader and math.max(0, rowCount - 1) or rowCount

	local rowHeight = params.RowHeight or DEFAULT_ROW_HEIGHT
	local headerHeight = params.HeaderHeight or rowHeight
	local padding = params.CellPadding or DEFAULT_CELL_PADDING
	local textSize = params.TextSize or DEFAULT_TEXT_SIZE
	local cornerRadius = params.CornerRadius or theme.CornerRadius or 0
	local showGridLines = (params.ShowGridLines == nil) or params.ShowGridLines
	local stripeRows = (params.StripeRows == nil) or params.StripeRows
	local defaultAlign = params.Align or "left"

	local field = storage[id]
	if not field then
		field = {
			scrollY = 0,
			scrollTarget = 0,
			hoverRow = 0,
			hoverCol = 0,
		}
		storage[id] = field
	end

	local columnWidths = computeColumnWidths(params.width, colCount, params.ColumnWidths)
	local columnAlign = table.create(colCount, defaultAlign)
	if params.ColumnAlign then
		for i = 1, colCount do
			columnAlign[i] = params.ColumnAlign[i] or defaultAlign
		end
	end

	local totalHeaderHeight = hasHeader and headerHeight or 0
	local maxVisibleRows = params.MaxVisibleRows
	local visibleBodyHeight = maxVisibleRows and (math.min(bodyRowCount, maxVisibleRows) * rowHeight)
		or (bodyRowCount * rowHeight)
	local scrollable = (maxVisibleRows ~= nil) and (bodyRowCount > maxVisibleRows)

	local tableRect = {
		x = params.x,
		y = params.y,
		width = params.width,
		height = totalHeaderHeight + visibleBodyHeight,
	}

	local bodyRect = {
		x = params.x,
		y = params.y + totalHeaderHeight,
		width = params.width,
		height = visibleBodyHeight,
	}

	local font = argon:CreateFont(theme.Font)
	local textHeight = argon:GetFontLineHeight(textSize, font)
	local textAscent = argon:GetFontAscent(textSize, font)

	local mousePos = argon:GetMousePosition()
	local hoveredBody = renderer:isMouseInRect(bodyRect)
	local leftPressed = argon:IsMouseButtonPressed(LEFT_MOUSE_BUTTON)

	if scrollable and hoveredBody then
		local wheelDelta = argon:GetMouseWheelMove()
		if wheelDelta ~= 0 then
			local maxScroll = math.max(0, (bodyRowCount * rowHeight) - visibleBodyHeight)
			field.scrollTarget = math.clamp(field.scrollTarget - wheelDelta * (params.ScrollSpeed or 40), 0, maxScroll)
		end
	end

	if scrollable then
		field.scrollY = smoothTowards(field.scrollY, field.scrollTarget, params.ScrollLerpSpeed or 20, dt)
		if math.abs(field.scrollY - field.scrollTarget) < 0.05 then
			field.scrollY = field.scrollTarget
		end
	else
		field.scrollY = 0
	end

	field.hoverRow, field.hoverCol = 0, 0
	if hoveredBody then
		local localY = (mousePos.Y - bodyRect.y) + field.scrollY
		local rowIndex = math.floor(localY / rowHeight) + 1
		if rowIndex >= 1 and rowIndex <= bodyRowCount then
			field.hoverRow = rowIndex

			local localX = mousePos.X - bodyRect.x
			local acc = 0
			for c = 1, colCount do
				acc += columnWidths[c]
				if localX <= acc then
					field.hoverCol = c
					break
				end
			end
		end
	end

	if leftPressed and field.hoverRow > 0 and params.OnCellClicked then
		local dataRowIndex = hasHeader and (field.hoverRow + 1) or field.hoverRow
		local row = data[dataRowIndex]
		local value = row and row[field.hoverCol]
		params.OnCellClicked(field.hoverRow, field.hoverCol, value)
	end

	argon:Save(window)
	argon:ClipRoundRect(window, tableRect, cornerRadius, cornerRadius)

	Rectangle({
		x = tableRect.x,
		y = tableRect.y,
		width = tableRect.width,
		height = tableRect.height,
		Color = theme.BgColor,
		theme = theme,
		engine_window = window,
	}, dt)

	if hasHeader then
		local headerRow = data[1]

		Rectangle({
			x = params.x,
			y = params.y,
			width = params.width,
			height = headerHeight,
			Color = params.HeaderColor or theme.ThirdColor or theme.SecondaryColor,
			theme = theme,
			engine_window = window,
		}, dt)

		local colX = params.x
		for c = 1, colCount do
			local cell = headerRow and headerRow[c]
			local text = cellText(cell)
			if text ~= "" then
				local textWidth = argon:MeasureText(window, text, textSize, font)
				local align = cellAlign(cell, params.HeaderAlign or columnAlign[c])
				Text({
					x = alignTextX(align, colX, columnWidths[c], textWidth, padding),
					y = params.y + (headerHeight - textHeight) / 2 + textAscent,
					TextSize = textSize,
					theme = theme,
					Font = font,
					text = text,
					Color = cellColor(cell, params.HeaderTextColor or theme.TextColor),
					engine_window = window,
				}, dt)
			end
			colX += columnWidths[c]
		end
	end

	argon:Save(window)
	argon:ClipRoundRect(window, bodyRect, 0, 0)

	for r = 1, bodyRowCount do
		local rowY = bodyRect.y + (r - 1) * rowHeight - field.scrollY
		if rowY + rowHeight >= bodyRect.y and rowY <= bodyRect.y + bodyRect.height then
			local dataRowIndex = hasHeader and (r + 1) or r
			local row = data[dataRowIndex] or {}

			if r == field.hoverRow then
				Rectangle({
					x = bodyRect.x,
					y = rowY,
					width = bodyRect.width,
					height = rowHeight,
					Color = params.HoverColor or theme.SecondaryColor,
					theme = theme,
					engine_window = window,
				}, dt)
			elseif stripeRows and (r % 2 == 0) then
				Rectangle({
					x = bodyRect.x,
					y = rowY,
					width = bodyRect.width,
					height = rowHeight,
					Color = params.StripeColor or theme.ThirdColor or theme.SecondaryColor,
					theme = theme,
					engine_window = window,
				}, dt)
			end

			local colX = bodyRect.x
			for c = 1, colCount do
				local cell = row[c]
				local text = cellText(cell)
				if text ~= "" then
					local textWidth = argon:MeasureText(window, text, textSize, font)
					local align = cellAlign(cell, columnAlign[c])
					Text({
						x = alignTextX(align, colX, columnWidths[c], textWidth, padding),
						y = rowY + (rowHeight - textHeight) / 2 + textAscent,
						TextSize = textSize,
						theme = theme,
						Font = font,
						text = text,
						Color = cellColor(cell, theme.TextColor),
						engine_window = window,
					}, dt)
				end
				colX += columnWidths[c]
			end

			if showGridLines and r < bodyRowCount then
				Rectangle({
					x = bodyRect.x,
					y = rowY + rowHeight - 1,
					width = bodyRect.width,
					height = 1,
					Color = theme.SecondaryColor,
					theme = theme,
					engine_window = window,
				}, dt)
			end
		end
	end

	argon:Restore(window)

	if showGridLines then
		if hasHeader then
			Rectangle({
				x = params.x,
				y = params.y + headerHeight - 1,
				width = params.width,
				height = 1,
				Color = theme.SecondaryColor,
				theme = theme,
				engine_window = window,
			}, dt)
		end

		local colX = params.x
		for c = 1, colCount - 1 do
			colX += columnWidths[c]
			Rectangle({
				x = colX - 1,
				y = params.y,
				width = 1,
				height = tableRect.height,
				Color = theme.SecondaryColor,
				theme = theme,
				engine_window = window,
			}, dt)
		end
	end

	argon:Restore(window)

	Rectangle({
		x = tableRect.x,
		y = tableRect.y,
		width = tableRect.width,
		height = tableRect.height,
		Color = theme.SecondaryColor,
		theme = theme,
		engine_window = window,
		isOutline = true,
	}, dt)

	return field.hoverRow, field.hoverCol, tableRect.height
end
