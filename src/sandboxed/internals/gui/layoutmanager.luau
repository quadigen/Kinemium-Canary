local LayoutEngine = require("@LayoutEngine")
local StudioThemeService = game:GetService("StudioThemeService")

local LayoutConfig = {
	P = 4,
	TopH = 33,
	BottomPad = 12,

	Topbar = { flexGrow = 0 },
	Content = { flexGrow = 1 },

	Left = { flexGrow = 0.78, minWidth = 0 },
	Right = { flexGrow = 0.22, minWidth = 0 },

	Viewport = { flexGrow = 0.7, layoutOrder = 1 },
	CodeEditor = { target = "Viewport" },
	Output = { flexGrow = 0.3, layoutOrder = 2 },

	Explorer = { flexGrow = 0.5, layoutOrder = 1 },
	Inspector = { flexGrow = 0.5, layoutOrder = 2 },
}

local function setWindow(name, props)
	local entry = LayoutConfig[name]
	assert(entry, ("LayoutConfig has no window named %q"):format(name))
	for key, value in pairs(props) do
		entry[key] = value
	end
end

local function computeLayout(width, height)
	local P, TopH, BottomPad = LayoutConfig.P, LayoutConfig.TopH, LayoutConfig.BottomPad

	local rootItems = {
		LayoutEngine.createItem("Topbar", width, TopH, LayoutConfig.Topbar),
		LayoutEngine.createItem("Content", width, 0, LayoutConfig.Content),
	}

	LayoutEngine.calculate({
		direction = LayoutEngine.Direction.Column,
		width = width,
		height = height,
		gap = P,
		padding = { left = P, right = P, top = P, bottom = P },
	}, rootItems)

	local topbarItem, contentItem = rootItems[1], rootItems[2]

	local rowItems = {
		LayoutEngine.createItem("Left", 0, contentItem._actualHeight, LayoutConfig.Left),
		LayoutEngine.createItem("Right", 0, contentItem._actualHeight, LayoutConfig.Right),
	}

	LayoutEngine.calculate({
		direction = LayoutEngine.Direction.Row,
		width = contentItem._actualWidth,
		height = contentItem._actualHeight,
		gap = P,
	}, rowItems)

	local leftItem, rightItem = rowItems[1], rowItems[2]

	local leftColumnItems = {
		LayoutEngine.createItem("Viewport", leftItem._actualWidth, 0, LayoutConfig.Viewport),
		LayoutEngine.createItem("Output", leftItem._actualWidth, 0, LayoutConfig.Output),
	}

	LayoutEngine.calculate({
		direction = LayoutEngine.Direction.Column,
		width = leftItem._actualWidth,
		height = leftItem._actualHeight,
		gap = P,
		padding = { left = 0, right = 0, top = 0, bottom = BottomPad },
	}, leftColumnItems)

	local rightColumnItems = {
		LayoutEngine.createItem("Explorer", rightItem._actualWidth, 0, LayoutConfig.Explorer),
		LayoutEngine.createItem("Inspector", rightItem._actualWidth, 0, LayoutConfig.Inspector),
	}

	LayoutEngine.calculate({
		direction = LayoutEngine.Direction.Column,
		width = rightItem._actualWidth,
		height = rightItem._actualHeight,
		gap = P,
		padding = { left = 0, right = 0, top = 0, bottom = BottomPad },
	}, rightColumnItems)

	local function findById(items, id)
		for _, item in ipairs(items) do
			if item.id == id then
				return item
			end
		end
		error(("no layout item with id %q"):format(id))
	end

	local viewportItem = findById(leftColumnItems, "Viewport")
	local outputItem = findById(leftColumnItems, "Output")
	local explorerItem = findById(rightColumnItems, "Explorer")
	local inspectorItem = findById(rightColumnItems, "Inspector")

	local function toCoordinates(item, offsetX, offsetY)
		return {
			Position = UDim2.new(0, offsetX + item._x, 0, offsetY + item._y),
			Size = UDim2.new(0, item._actualWidth, 0, item._actualHeight),
		}
	end

	local leftOffsetX, leftOffsetY = contentItem._x + leftItem._x, contentItem._y + leftItem._y
	local rightOffsetX, rightOffsetY = contentItem._x + rightItem._x, contentItem._y + rightItem._y

	return {
		TopbarCoordinates = toCoordinates(topbarItem, 0, 0),
		ViewportCoordinates = toCoordinates(viewportItem, leftOffsetX, leftOffsetY),
		CodeEditorCoordinates = toCoordinates(viewportItem, leftOffsetX, leftOffsetY),
		OutputCoordinates = toCoordinates(outputItem, leftOffsetX, leftOffsetY),
		ExplorerCoordinates = toCoordinates(explorerItem, rightOffsetX, rightOffsetY),
		InspectorCoordinates = toCoordinates(inspectorItem, rightOffsetX, rightOffsetY),
	}
end

local function applyLayout(width, height)
	local coordinates = computeLayout(width, height)

	local theme = StudioThemeService:GetTheme()
	LayoutConfig = theme.LayoutConfig
	for key, value in pairs(coordinates) do
		theme[key] = value
	end

	StudioThemeService:SetProperties({ SelectedTheme = theme })
end

renderer.Pool.new("2d", function()
	applyLayout(renderer.Width, renderer.Height)
end)

return {
	LayoutConfig = LayoutConfig,
	SetWindow = setWindow,
	ComputeLayout = computeLayout,
	ApplyLayout = applyLayout,
}
