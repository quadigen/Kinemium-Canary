local Studio = game:GetService("Studio")
local StudioThemeService = game:GetService("StudioThemeService")
local Immco = require("@Immco")
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
until game.CoreGui:FindFirstChild("Studio")

local Topbar = Instance.new("Frame")
Topbar.Name = "Topbar"
Topbar.Size = theme.TopbarCoordinates.Size
Topbar.Position = theme.TopbarCoordinates.Position
Topbar.Parent = game.CoreGui:FindFirstChild("Studio")
Topbar.BackgroundTransparency = 1

local icon = Argon:CreateImageFromPath("./src/assets/images/kinemium/KinemiumWhite.png")
local PlaytestService = game:GetService("PlaytestService")
local NetworkService = game:GetService("NetworkService")

local buttonCategories = {
	{
		name = "Engine",
		buttons = {
			{
				name = "File",
				type = "button",
				callback = function()
					print("Play")
				end,
			},
			{
				name = "Game",
				type = "button",
				callback = function()
					print("Stop")
				end,
			},
			{
				name = "Projects",
				type = "button",
				callback = function()
					print("Settings")
				end,
			},
		},
	},

	{
		name = "Home",
		buttons = {
			{
				name = "Collaboration",
				type = "category",
				buttons = {
					{
						name = "Host & Copy Invite",
						tooltip = "Host this project and copy an authenticated invite code",
						icon = "",
						callback = function()
							local invite, reason = NetworkService:HostCollaboration({
								InviteAddress = GetFlagValue("invite-address") or "127.0.0.1",
								Port = tonumber(GetFlagValue("port")) or 1234,
							})
							if invite then
								Argon:SetClipboard(invite.Code)
								print("Collaboration invite copied: " .. invite.Code)
							else
								warn("Could not host collaboration: " .. tostring(reason))
							end
						end,
					},
					{
						name = "Join From Clipboard",
						tooltip = "Join the collaboration invite currently on the clipboard",
						icon = "",

						callback = function()
							local active, reason = NetworkService:JoinCollaboration(
								Argon:GetClipboard(),
								GetFlagValue("username") or "Collaborator"
							)
							if not active then
								warn("Could not join collaboration: " .. tostring(reason))
							end
						end,
					},
					{
						name = "Stop Collaboration",
						icon = "",

						callback = function()
							NetworkService:StopCollaboration()
						end,
					},
				},
			},
			{
				name = "Test",
				type = "category",
				buttons = {
					{
						name = "Run Client",
						icon = "path",
						tooltip = "Run a new playtest on the client",
						callback = function() end,
					},

					{
						name = "Run Server",
						icon = "path",
						callback = function()
							print("Overview")
						end,
					},

					{
						name = "Machine Playtest",
						icon = "path",
						callback = function()
							PlaytestService.CreatePlaytestAsync("game")
						end,
					},
				},
				callback = function()
					print("Overview")
				end,
			},
			{
				name = "Plugins",
				type = "category",
				buttons = {},
				callback = function()
					print("Projects")
				end,
			},
			{
				name = "View",
				type = "category",
				buttons = {
					{
						name = "Test",
						icon = "path",
						callback = function()
							print("Overview")
						end,
					},
				},
				callback = function()
					print("Projects")
				end,
			},
		},
	},
}

local pluginCategory
for _, category in ipairs(buttonCategories) do
	for _, button in ipairs(category.buttons) do
		if button.name == "Plugins" and button.type == "category" then
			pluginCategory = button
			break
		end
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

local expandedHeight = 200

local selectedCategory = buttonCategories[2].buttons[1]

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

		local gridPadding = 8
		local itemWidth = 80
		local itemHeight = expandedHeight - 60
		local itemSpacing = 8

		local gridX = insideRect.x + gridPadding
		local gridY = insideRect.y + gridPadding
		local gridWidth = insideRect.width - gridPadding * 2

		local flyoutRects =
			layoutGrid(gridX, gridY, gridWidth, itemWidth, itemHeight, itemSpacing, itemSpacing, #flyoutButtons)

		for index, category_button in ipairs(flyoutButtons) do
			local rect = flyoutRects[index]
			local isHovered = renderer:isMouseInRect(rect)

			Immco.TopbarButton({
				x = rect.x,
				y = rect.y,
				width = rect.width,
				height = rect.height,

				Image = category_button.icon,
				text = category_button.name,

				Color = isHovered and theme.ThirdColor or theme.BgColor,
				TextColor = theme.SecondaryTextColor,

				theme = theme,
				engine_window = renderer.Window,
			}, dt)

			if category_button.tooltip then
				Immco.Tooltip({
					RetainedStorage = retained,
					id = category_button.icon,
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

	Argon:Restore(renderer.Window)

	local engineCategory = buttonCategories[1]
	local toolbarCategory = buttonCategories[2]

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
					selectedCategory = category

					if category.callback then
						category.callback()
					end

					break
				end
			end
		end,
	}, dt)
end)
