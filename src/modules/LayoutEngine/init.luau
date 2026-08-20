local LayoutEngine = {}

LayoutEngine.Direction = {
	Row = "row",
	Column = "column",
}

LayoutEngine.JustifyContent = {
	Start = "start",
	Center = "center",
	End = "end",
	SpaceBetween = "space-between",
	SpaceAround = "space-around",
	SpaceEvenly = "space-evenly",
}

LayoutEngine.AlignItems = {
	Start = "start",
	Center = "center",
	End = "end",
	Stretch = "stretch",
}

LayoutEngine.FlexWrap = {
	NoWrap = "nowrap",
	Wrap = "wrap",
}

function LayoutEngine.createItem(id, width, height, data)
	data = data or {}
	return {
		id = id,
		width = width or 0,
		height = height or 0,
		minWidth = data.minWidth or 0,
		minHeight = data.minHeight or 0,
		maxWidth = data.maxWidth or math.huge,
		maxHeight = data.maxHeight or math.huge,
		aspectRatio = data.aspectRatio,
		layoutOrder = data.layoutOrder or 0,
		flexGrow = data.flexGrow or 0,
		flexShrink = data.flexShrink or 1,
		alignSelf = data.alignSelf,
		_x = 0,
		_y = 0,
		_actualWidth = width or 0,
		_actualHeight = height or 0,
	}
end

function LayoutEngine.calculate(container, items)
	local dir = container.direction or LayoutEngine.Direction.Row
	local justify = container.justifyContent or LayoutEngine.JustifyContent.Start
	local align = container.alignItems or LayoutEngine.AlignItems.Start
	local wrap = container.flexWrap or LayoutEngine.FlexWrap.NoWrap
	local gap = container.gap or 0
	local padding = container.padding or { left = 0, right = 0, top = 0, bottom = 0 }

	local containerWidth = container.width or 0
	local containerHeight = container.height or 0

	local isRow = dir == LayoutEngine.Direction.Row

	table.sort(items, function(a, b)
		return a.layoutOrder < b.layoutOrder
	end)

	local mainAxis = isRow and "width" or "height"
	local crossAxis = isRow and "height" or "width"
	local mainPos = isRow and "_x" or "_y"
	local crossPos = isRow and "_y" or "_x"
	local actualMain = isRow and "_actualWidth" or "_actualHeight"
	local actualCross = isRow and "_actualHeight" or "_actualWidth"
	local minMain = isRow and "minWidth" or "minHeight"
	local maxMain = isRow and "maxWidth" or "maxHeight"

	local contentMainSize = isRow and (containerWidth - padding.left - padding.right)
		or (containerHeight - padding.top - padding.bottom)

	for _, item in ipairs(items) do
		if item.aspectRatio then
			if isRow then
				item.width = item.height * item.aspectRatio
			else
				item.height = item.width / item.aspectRatio
			end
		end

		item[actualMain] = math.clamp(item[mainAxis], item[minMain], item[maxMain])
	end

	local lines = { {} }
	local currentLine = lines[1]
	local currentLineMainSize = 0

	for _, item in ipairs(items) do
		local itemMainSize = item[actualMain]

		if
			wrap == LayoutEngine.FlexWrap.Wrap
			and #currentLine > 0
			and currentLineMainSize + gap + itemMainSize > contentMainSize
		then
			currentLine = {}
			table.insert(lines, currentLine)
			currentLineMainSize = 0
		end

		table.insert(currentLine, item)
		currentLineMainSize = currentLineMainSize + itemMainSize + (#currentLine > 1 and gap or 0)
	end

	local currentCrossOffset = isRow and padding.top or padding.left

	for _, line in ipairs(lines) do
		local lineMainSize = 0
		local maxCrossSize = 0
		local totalFlexGrow = 0

		for _, item in ipairs(line) do
			lineMainSize = lineMainSize + item[actualMain]
			maxCrossSize = math.max(maxCrossSize, item[crossAxis])
			totalFlexGrow = totalFlexGrow + item.flexGrow
		end

		local gapCount = #line - 1
		local totalGap = gapCount * gap
		local remainingSpace = contentMainSize - lineMainSize - totalGap

		if remainingSpace > 0 and totalFlexGrow > 0 then
			for _, item in ipairs(line) do
				local growAmount = (item.flexGrow / totalFlexGrow) * remainingSpace
				item[actualMain] = math.clamp(item[actualMain] + growAmount, item[minMain], item[maxMain])
			end
			lineMainSize = contentMainSize - totalGap
			remainingSpace = 0
		end

		local startOffset = isRow and padding.left or padding.top
		local spacing = gap

		if justify == LayoutEngine.JustifyContent.Center then
			startOffset = startOffset + remainingSpace / 2
		elseif justify == LayoutEngine.JustifyContent.End then
			startOffset = startOffset + remainingSpace
		elseif justify == LayoutEngine.JustifyContent.SpaceBetween then
			if gapCount > 0 then
				spacing = gap + remainingSpace / gapCount
			end
		elseif justify == LayoutEngine.JustifyContent.SpaceAround then
			if #line > 0 then
				spacing = gap + remainingSpace / #line
				startOffset = startOffset + (remainingSpace / #line) / 2
			end
		elseif justify == LayoutEngine.JustifyContent.SpaceEvenly then
			if #line > 0 then
				local step = remainingSpace / (#line + 1)
				spacing = gap + step
				startOffset = startOffset + step
			end
		end

		local currentMainOffset = startOffset
		for _, item in ipairs(line) do
			item[mainPos] = currentMainOffset

			local itemAlignment = item.alignSelf or align

			if itemAlignment == LayoutEngine.AlignItems.Stretch then
				item[actualCross] = maxCrossSize
				item[crossPos] = currentCrossOffset
			elseif itemAlignment == LayoutEngine.AlignItems.Center then
				item[actualCross] = item[crossAxis]
				item[crossPos] = currentCrossOffset + (maxCrossSize - item[crossAxis]) / 2
			elseif itemAlignment == LayoutEngine.AlignItems.End then
				item[actualCross] = item[crossAxis]
				item[crossPos] = currentCrossOffset + maxCrossSize - item[crossAxis]
			else
				item[actualCross] = item[crossAxis]
				item[crossPos] = currentCrossOffset
			end

			currentMainOffset = currentMainOffset + item[actualMain] + spacing
		end

		currentCrossOffset = currentCrossOffset + maxCrossSize + gap
	end

	local finalWidth = containerWidth
	local finalHeight = containerHeight

	if container.autoWidth or container.autoHeight then
		local maxX, maxY = 0, 0
		for _, item in ipairs(items) do
			maxX = math.max(maxX, item._x + item._actualWidth)
			maxY = math.max(maxY, item._y + item._actualHeight)
		end
		if container.autoWidth then
			finalWidth = maxX + padding.right
		end
		if container.autoHeight then
			finalHeight = maxY + padding.bottom
		end
	end

	return finalWidth, finalHeight
end

return LayoutEngine
