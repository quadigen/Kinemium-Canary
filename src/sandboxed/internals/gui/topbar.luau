local Studio = game:GetService("Studio")
local StudioThemeService = game:GetService("StudioThemeService")
local Immco = require("@Immco")
local topbarModules = require("@StudioTopbar")
local categoryDefinitions = topbarModules.categories
local topbarActions = topbarModules.actions({
	game = game,
	Instance = Instance,
	Color3 = Color3,
	CFrame = CFrame,
	Enum = Enum,
	ishared = ishared,
	warn = warn,
})
local theme = StudioThemeService.SelectedTheme
local Argon = require("@Argon")
local retained = {}

if IsServer then
	return
end

if IsClient then
	return
end

repeat
	task.wait()
until game.CoreGui:FindFirstChild("Studio") and ishared.StudioSystem

local Topbar = Instance.new("Frame")
Topbar.Name = "Topbar"
Topbar.Size = theme.TopbarCoordinates.Size
Topbar.Position = theme.TopbarCoordinates.Position
Topbar.Parent = game.CoreGui:FindFirstChild("Studio")
Topbar.BackgroundTransparency = 1

local icon = Argon:CreateImageFromPath("./src/assets/images/kinemium/KinemiumWhite.png")

local function runAction(action)
	local arguments = action.arguments or {}

	if action.type == "studio-route" then
		ishared.StudioSystem:Fire(action.route, table.unpack(arguments))
		return
	end

	if action.type == "service-method" then
		local service = game:GetService(action.service)
		local method = service and service[action.method]
		if type(method) == "function" then
			method(service, table.unpack(arguments))
		end
		return
	end

	if action.type == "topbar-command" then
		topbarActions.run(action)
	end
end

local function makeButton(definition)
	if definition.type == "separator" then
		return {
			type = "separator",
		}
	end

	local button = {}

	for key, value in pairs(definition) do
		button[key] = value
	end

	if definition.iconPath then
		button.icon = Argon:CreateImageFromPath(definition.iconPath)
	end

	if definition.action then
		button.callback = function()
			runAction(definition.action)
		end
	end

	return button
end

local function makeCategory(definition)
	local buttons = {}
	for _, buttonDefinition in ipairs(definition.buttons or {}) do
		table.insert(buttons, makeButton(buttonDefinition))
	end

	return {
		name = definition.name,
		type = definition.type or "category",
		buttons = buttons,
		callback = definition.callback,
	}
end

local toolbarCategories = {}
for _, definition in ipairs(categoryDefinitions) do
	table.insert(toolbarCategories, makeCategory(definition))
end

ishared.buttonCategories = {
	{
		name = "Engine",
		buttons = {},
	},
	{
		name = "Toolbar",
		buttons = toolbarCategories,
	},
}

ishared.EngineTopbar = {
	AddCategory = function(categoryName: string, buttons: { any })
		if not categoryName or type(categoryName) ~= "string" then
			return
		end
		if not buttons or type(buttons) ~= "table" then
			return
		end

		table.insert(toolbarCategories, {
			name = categoryName,
			type = "category",
			buttons = (function()
				local builtButtons = {}
				for _, button in ipairs(buttons) do
					table.insert(builtButtons, makeButton(button))
				end
				return builtButtons
			end)(),
		})
	end,
}

local pluginCategory
for _, category in ipairs(toolbarCategories) do
	if category.name == "Plugins" then
		pluginCategory = category
		break
	end
end

local pluginButtons = {}
local pluginGroups = {}

game.EngineSignal:Connect(function(route, target, payload)
	if target ~= "Plugins" or type(payload) ~= "table" or not pluginCategory then
		return
	end
	if route == "NewToolbarGroup" then
		local groupName = tostring(payload.name or "Plugins")
		pluginGroups[groupName] = true
		return
	end
	if route ~= "AddToolbarGroupElement" then
		return
	end

	local groupName = tostring(payload.group or "Plugins")
	local elementName = tostring(payload.name or payload.text or "Plugin")
	local key = groupName .. "\0" .. elementName
	local topbarButton = pluginButtons[key]
	if not topbarButton then
		topbarButton = { group = groupName }
		pluginButtons[key] = topbarButton
		table.insert(pluginCategory.buttons, topbarButton)
	end
	topbarButton.name = tostring(payload.text or elementName)
	topbarButton.tooltip = payload.tooltip or groupName
	topbarButton.icon = payload.texture or payload.icon or ""
	topbarButton.callback = function(element, rect)
		if type(payload.callback) == "function" then
			payload.callback(element, rect)
		end
	end
end)

local function layoutRow(x: number, y: number, height: number, spacing: number, widths: { number })
	local rects = {}
	local currentX = x

	for index, width in ipairs(widths) do
		rects[index] = {
			x = currentX,
			y = y,
			width = width,
			height = height,
		}
		currentX += width + spacing
	end

	return rects, currentX
end

local function layoutGrid(
	x: number,
	y: number,
	containerWidth: number,
	itemWidth: number,
	itemHeight: number,
	spacingX: number,
	spacingY: number,
	count: number
)
	local rects = {}
	local currentX = x
	local currentY = y
	local columnCount = 0

	for index = 1, count do
		if columnCount > 0 and (currentX + itemWidth) > (x + containerWidth) then
			currentX = x
			currentY += itemHeight + spacingY
			columnCount = 0
		end

		rects[index] = {
			x = currentX,
			y = currentY,
			width = itemWidth,
			height = itemHeight,
		}

		currentX += itemWidth + spacingX
		columnCount += 1
	end

	return rects
end

local function layoutToolbarItems(
	x: number,
	y: number,
	containerWidth: number,
	items: { any },
	itemWidth: number,
	itemHeight: number,
	spacingX: number,
	spacingY: number
)
	local rects = {}

	local currentX = x
	local currentY = y

	local separatorWidth = 1
	local separatorPadding = 6

	for index, item in ipairs(items) do
		local width

		if item.type == "separator" then
			width = separatorWidth + separatorPadding * 2
		else
			width = item.width or itemWidth
		end

		if currentX > x and currentX + width > x + containerWidth then
			currentX = x
			currentY += itemHeight + spacingY
		end

		rects[index] = {
			x = currentX,
			y = currentY,
			width = width,
			height = itemHeight,
		}

		currentX += width + spacingX
	end

	return rects
end

local expandedHeight = 145

local selectedCategory = toolbarCategories[1]

renderer.Pool.new("2da", function(lib)
	local absolutePosition = Topbar.AbsolutePosition
	local absoluteSize = Topbar.AbsoluteSize
	local dt = lib.dt
	Topbar.Size = theme.TopbarCoordinates.Size
	Topbar.Position = theme.TopbarCoordinates.Position
	if not absolutePosition or not absoluteSize then
		return
	end

	local buttonX = absolutePosition.X + 30
	local buttonY = absolutePosition.Y + 2
	local buttonHeight = absoluteSize.Y - 4

	local textSize = 16
	local horizontalPadding = 12
	local buttonSpacing = 2
	local categorySpacing = 8
	local separatorWidth = 1
	local font = Argon:CreateFont(theme.Font)

	if not absoluteSize then
		return
	end

	local mainRect = {
		x = absolutePosition.X,
		y = absolutePosition.Y,
		width = absoluteSize.X,
		height = absoluteSize.Y,
		Color = theme.BgColor,
	}

	local isHovering = false

	if renderer:isMouseInRect(mainRect) or selectedCategory then
		isHovering = true
		mainRect.height = expandedHeight
	end

	Argon:Save(renderer.Window)

	Argon:ClipRoundRect(renderer.Window, mainRect, 6, 6)

	Argon:DrawRectangle(renderer.Window, mainRect)

	Immco.Image({
		x = absolutePosition.X + 3,
		y = absolutePosition.Y + 3,
		width = 23,
		height = 23,
		Image = icon,
		theme = theme,
		engine_window = renderer.Window,
	}, dt)

	if isHovering or selectedCategory then
		local padding = 10
		local headerHeight = 29

		local insideRect = {
			x = absolutePosition.X + padding,
			y = absolutePosition.Y + headerHeight + padding,
			width = absoluteSize.X - (padding * 2),
			height = expandedHeight - headerHeight - (padding * 2),
			Color = theme.SecondaryColor,
		}

		Argon:Save(renderer.Window)
		Argon:ClipRoundRect(renderer.Window, insideRect, 6, 6)
		Argon:DrawRectangle(renderer.Window, insideRect)
		Argon:Restore(renderer.Window)

		local flyoutButtons = {}
		if selectedCategory and selectedCategory.buttons then
			for _, category_button in pairs(selectedCategory.buttons) do
				flyoutButtons[#flyoutButtons + 1] = category_button
			end
		end

		local gridPadding = 6
		local itemWidth = 64
		local itemHeight = 80
		local itemSpacing = 4

		local gridX = insideRect.x + gridPadding
		local gridY = insideRect.y + gridPadding
		local gridWidth = insideRect.width - gridPadding * 2

		local flyoutRects =
			layoutToolbarItems(gridX, gridY, gridWidth, flyoutButtons, itemWidth, itemHeight, itemSpacing, itemSpacing)

		for index, category_button in ipairs(flyoutButtons) do
			local rect = flyoutRects[index]

			if category_button.type == "separator" then
				Argon:DrawRectangle(renderer.Window, {
					x = rect.x + math.floor(rect.width / 2),
					y = rect.y + 5,
					width = 1,
					height = rect.height - 10,
					Color = Argon:RGBA(70, 70, 70),
				})

				continue
			end

			if type(category_button.render) == "function" then
				category_button.render({
					rect = rect,

					button = category_button,

					renderer = renderer,
					window = renderer.Window,

					theme = theme,
					retained = retained,
					dt = dt,

					Immco = Immco,
					Argon = Argon,
				})

				continue
			end

			local isHovered = renderer:isMouseInRect(rect)

			Immco.TopbarButton({
				x = rect.x,
				y = rect.y,
				width = rect.width,
				height = rect.height,
				Image = category_button.icon,
				text = category_button.name,
				imageWidth = 43,
				imageHeight = 43,
				padding = 3,
				TextSize = 11,
				Color = isHovered and theme.ThirdColor or theme.BgColor,
				TextColor = theme.SecondaryTextColor,
				theme = theme,
				engine_window = renderer.Window,
			}, dt)
			Argon:Restore(renderer.Window)

			if category_button.tooltip then
				Immco.Tooltip({
					RetainedStorage = retained,
					id = category_button.icon or category_button.name,
					renderer = renderer,
					canvas = renderer.Window,
					window = renderer.Window,
					theme = theme,
					HoverRect = rect,
					Text = category_button.tooltip,
					HoverDelay = 0.4,
					FadeSpeed = 14,
					Placement = "below",
					Offset = { x = 0, y = 5 },
					Gap = 8,
					MaxWidth = 220,
					Padding = 6,
					CornerRadius = 6,
				}, dt)
			end

			if renderer:HasClicked(rect) and selectedCategory then
				if category_button.callback then
					category_button.callback(category_button, rect)
				end
			end
		end
	end

	local engineCategory = ishared.buttonCategories[1]
	local toolbarCategory = ishared.buttonCategories[2]

	--
	-- Engine buttons: File / Game / Projects
	--

	local widths = {}

	for index, button in ipairs(engineCategory.buttons) do
		local textWidth = Argon:MeasureText(renderer.Window, button.name, textSize, font)

		widths[index] = textWidth + horizontalPadding * 2
	end

	local rects, endX = layoutRow(buttonX, buttonY, buttonHeight, buttonSpacing, widths)

	for index, button in ipairs(engineCategory.buttons) do
		local rect = rects[index]
		local isHovered = renderer:isMouseInRect(rect)

		Immco.TextButton({
			x = rect.x,
			y = rect.y,

			width = rect.width,
			height = rect.height,

			text = button.name,

			Color = isHovered and theme.SecondaryColor or theme.BgColor,

			TextColor = theme.SecondaryTextColor,

			BgVisible = true,

			theme = theme,
			engine_window = renderer.Window,
		}, dt)

		if renderer:HasClicked(rect) then
			if button.callback then
				button.callback()
			end
		end
	end

	local separatorX = endX + (categorySpacing / 2)

	Argon:DrawRectangle(renderer.Window, {
		x = separatorX,
		y = absolutePosition.Y + 5,

		width = separatorWidth,
		height = absoluteSize.Y - 10,

		Color = Argon:RGBA(70, 70, 70),
	})

	local tabsX = separatorX + separatorWidth + categorySpacing / 2

	local tabItems = {}

	for _, category in ipairs(toolbarCategory.buttons) do
		table.insert(tabItems, {
			Value = category.name,
			Text = category.name,
		})
	end

	Immco.Tabs({
		x = tabsX,
		y = buttonY,

		engine_window = renderer.Window,
		renderer = renderer,
		theme = theme,

		Items = tabItems,

		Value = selectedCategory and selectedCategory.name or "",
		Variant = "filled",
		Orientation = "horizontal",

		TabHeight = buttonHeight,
		TextSize = textSize,
		Toggleable = true,

		PaddingX = horizontalPadding,
		Gap = buttonSpacing,
		RetainedStorage = retained,
		id = "toolbar-tabs",
		BackgroundColor = theme.SecondaryColor,

		ActiveColor = theme.AccentColor,
		HoverColor = theme.SecondaryColor,

		TextColor = theme.SecondaryTextColor,
		ActiveTextColor = theme.TextColorDimmed,

		CornerRadius = theme.ButtonCornerRadius or theme.CornerRadius,

		Animated = true,
		AnimationSpeed = 20,

		RenderContent = false,

		OnChange = function(value)
			if value == nil then
				selectedCategory = nil
				return
			end

			for _, category in ipairs(toolbarCategory.buttons) do
				if category.name == value then
					if category.type == "button" then
						selectedCategory = nil
						if retained["toolbar-tabs"] then
							retained["toolbar-tabs"].value = nil
						end
						if category.callback then
							category.callback()
						end
					else
						selectedCategory = category
						if category.callback then
							category.callback()
						end
					end

					break
				end
			end
		end,
	}, dt)
end, 10000)
