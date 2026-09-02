local StudioThemeService = game:GetService("StudioThemeService")
local Immco = require("@Immco")
local theme = StudioThemeService.SelectedTheme
local Selection = game:GetService("Selection")
local Argon = require("@Argon")

if IsServer then
	return
end

if IsClient then
	return
end

repeat
	task.wait()
until game.CoreGui:FindFirstChild("Studio")

local Explorer = Instance.new("Frame")
Explorer.Name = "Explorer"
Explorer.Size = theme.ExplorerCoordinates.Size
Explorer.Position = theme.ExplorerCoordinates.Position
Explorer.Parent = game.CoreGui:FindFirstChild("Studio")
Explorer.BackgroundTransparency = 1

local retainedStorage = {}

local iconCache = {}
local iconPath = "./src/assets/images/icons/"
local textBoxStorage = {}
local contextMenuStorage = {}

local arrowRight = Argon:CreateImageFromPath(iconPath .. "ArrowRight.png")
local expandedIcon = Argon:CreateImageFromPath(iconPath .. "ArrowDown.png")
local plusIcon = Argon:CreateImageFromPath("./src/assets/images/plus.png")

local expanded = {}
local createMenu = {
	visible = false,
	x = 0,
	y = 0,
	parent = nil,
	suppressInput = false,
}
local createClassItems = nil

local canInteract = true

local nonCreatableClassNames = {
	DataModel = true,
	Instance = true,
	GuiObject = true,
	ValueBase = true,
	WorldObject2D = true,
}

local function getCreateClassItems()
	if createClassItems then
		return createClassItems
	end

	local classes = if Instance.getClasses then Instance.getClasses() else {}
	local names = {}

	for className, classData in pairs(classes) do
		if not classData.non_creatable and not nonCreatableClassNames[className] then
			table.insert(names, className)
		end
	end

	table.sort(names)

	createClassItems = {}
	for _, className in ipairs(names) do
		local itemClassName = className
		table.insert(createClassItems, {
			text = itemClassName,
			callback = function()
				local parent = createMenu.parent
				if not parent or parent.Destroyed then
					return
				end

				local ok, created = pcall(Instance.new, itemClassName)
				if not ok or not created then
					warn(`Failed to create {itemClassName}: {created}`)
					return
				end

				created.Parent = parent
				expanded[parent] = true
				Selection.Set({ created })
			end,
		})
	end

	return createClassItems
end

local uiScale = 1

local textSize = 16 * uiScale
local imageSize = 16 * uiScale
local rowHeight = 20 * uiScale
local indentSize = 16 * uiScale
local contentPadding = 10 * uiScale
local yOffset = 45

local serviceOrder = {
	"Workspace",
	"Players",
	"Lighting",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"Teams",
	"SoundService",
	"Chat",
	"TextChatService",
	"MaterialService",
	"TestService",
}

local visibleRowCount = 0
local contentHeight = 0
local explorerSearch = ""

local lastClickedInstance = nil
local lastClickTime = 0
local DOUBLE_CLICK_TIME = 0.3

local function textMatches(value, query)
	return string.find(string.lower(tostring(value or "")), query, 1, true) ~= nil
end

local function instanceMatchesTree(instance, query)
	if instance.ExplorerHidden then
		return false
	end
	if textMatches(instance.Name, query) or textMatches(instance.ClassName, query) then
		return true
	end
	for _, child in ipairs(instance:GetChildren()) do
		if instanceMatchesTree(child, query) then
			return true
		end
	end
	return false
end

local function clickedInstance(instance)
	local now = os.clock()

	if lastClickedInstance == instance and (now - lastClickTime) <= DOUBLE_CLICK_TIME then
		lastClickedInstance = nil
		lastClickTime = 0
		return true
	end

	lastClickedInstance = instance
	lastClickTime = now

	return false
end

renderer.Pool.new("2d", function()
	local dt = renderer.RuntimeLibrary.dt
	local absolutePosition = Explorer.AbsolutePosition
	local absoluteSize = Explorer.AbsoluteSize
	visibleRowCount = 0
	Explorer.Size = theme.ExplorerCoordinates.Size
	Explorer.Position = theme.ExplorerCoordinates.Position

	if not absolutePosition then
		return
	end
	if not absoluteSize then
		return
	end

	Immco.Widget({
		x = absolutePosition.X,
		y = absolutePosition.Y + 5,
		width = absoluteSize.X,
		height = absoluteSize.Y,
		title = "Explorer",
		theme = theme,
		engine_window = renderer.Window,
		renderer = renderer,

		callback = function(params)
			Immco.Scroller({
				id = "main-explorer",

				x = params.x,
				y = params.y,
				width = params.width,
				height = params.height,

				ViewHeight = params.height - 40,
				ContentHeight = contentHeight,

				ScrollSpeed = 50,
				ScrollLerpSpeed = 20,

				renderer = renderer,
				window = renderer.Window,
				theme = theme,

				RetainedStorage = retainedStorage,
				callback = function(params)
					local rowHeightStep = rowHeight
					local viewportRect = {
						x = params.viewportX,
						y = params.viewportY,
						width = params.viewportWidth,
						height = params.viewportHeight,
					}

					local function clipHitboxToViewport(rect)
						local left = math.max(rect.x, viewportRect.x)
						local top = math.max(rect.y, viewportRect.y)
						local right = math.min(rect.x + rect.width, viewportRect.x + viewportRect.width)
						local bottom = math.min(rect.y + rect.height, viewportRect.y + viewportRect.height)
						if right <= left or bottom <= top then
							return nil
						end
						return { x = left, y = top, width = right - left, height = bottom - top }
					end

					Immco.TextInput({
						x = params.x + 6,
						y = params.y + 4,
						width = params.width - 15 * uiScale,
						height = 20,
						id = "ExplorerSearch",
						RetainedStorage = textBoxStorage,
						renderer = renderer,
						theme = theme,

						Color = theme.InputColor,
						FocusColor = theme.InputFocusColor,
						TextColor = theme.InputTextColor,
						PlaceholderColor = theme.InputPlaceholderColor,

						ReadOnly = not canInteract,

						placeholder = "Search Objects...",
						OnChange = function(text)
							explorerSearch = text
						end,
						OnSubmit = function(text)
							explorerSearch = text
						end,

						engine_window = renderer.Window,
					}, dt)

					local function walkVisible(instance, depth, state, visit)
						if instance.ExplorerHidden then
							return
						end

						local searchQuery = string.lower(explorerSearch)
						local searching = searchQuery ~= ""
						local selfMatches = not searching
							or textMatches(instance.Name, searchQuery)
							or textMatches(instance.ClassName, searchQuery)
						local childMatches = false
						local children = instance:GetChildren()

						if searching then
							for _, child in ipairs(children) do
								if instanceMatchesTree(child, searchQuery) then
									childMatches = true
									break
								end
							end
						end

						if searching and not selfMatches and not childMatches then
							return false
						end

						visit(instance, depth, state.y, state.rowIndex)

						if not state.countOnly then
							state.y += rowHeightStep
							state.rowIndex += 1
							visibleRowCount += 1
						end

						if searching or expanded[instance] then
							for _, child in ipairs(children) do
								walkVisible(child, depth + 1, state, visit)
							end
						end

						return true
					end

					local services = game:GetChildren()

					local order = {}
					for index, name in ipairs(serviceOrder) do
						order[name] = index
					end

					table.sort(services, function(a, b)
						local aOrder = order[a.Name]
						local bOrder = order[b.Name]

						if aOrder and bOrder then
							return aOrder < bOrder
						elseif aOrder then
							return true
						elseif bOrder then
							return false
						end

						return a.Name < b.Name
					end)

					local stripeRects = {}
					local state = { y = params.y + yOffset, rowIndex = 0 }

					for _, service in ipairs(services) do
						walkVisible(service, 0, state, function(instance, depth, rowY, idx)
							table.insert(stripeRects, {
								y = rowY,
								color = (idx % 2 == 0) and theme.AlternatingColor1 or theme.AlternatingColor2,
							})
						end)
					end
					contentHeight = yOffset + (visibleRowCount * rowHeight)

					if #stripeRects > 0 then
						local x = params.x + (6 * uiScale)
						local width = params.width - (15 * uiScale)
						local top = stripeRects[1].y - (18 * uiScale)
						local bottom = stripeRects[#stripeRects].y - (18 * uiScale) + (25 * uiScale)
						local height = bottom - top

						Argon:Save(renderer.Window)

						Argon:ClipRoundRect(renderer.Window, {
							x = x,
							y = top,
							width = width,
							height = height,
						}, 6, 6)

						for _, stripe in ipairs(stripeRects) do
							Argon:DrawRectangle(renderer.Window, {
								x = x,
								y = stripe.y - (18 * uiScale),
								width = width,
								height = 25 * uiScale,
								Color = stripe.color,
							})
						end

						Argon:Restore(renderer.Window)
					end

					local function renderInstance(instance, depth, rowY)
						if instance.ExplorerHidden then
							return
						end

						local children = instance:GetChildren()
						local hasChildren = false

						for _, child in ipairs(children) do
							if not child.ExplorerHidden then
								hasChildren = true
								break
							end
						end

						if not iconCache[instance.ClassName] then
							local path = iconPath .. instance.ClassName .. ".png"
							iconCache[instance.ClassName] = Argon:CreateImageFromPath(path)
						end

						local indent = params.x + contentPadding + (depth * indentSize)
						local selection = Selection.Get()
						local isSelected = selection and selection[1] == instance or false
						local textX = indent + (36 * uiScale)

						local rowRect = {
							x = params.x + (6 * uiScale),
							y = rowY - (18 * uiScale),
							width = params.width - (12 * uiScale),
							height = rowHeight,
						}
						local rowHitbox = clipHitboxToViewport(rowRect)
						local isInRect = rowHitbox and renderer:isMouseInRect(rowHitbox) or false
						if isInRect and canInteract then
							local x = params.x + (6 * uiScale)
							local y = rowY - (18 * uiScale)
							local width = params.width - (12 * uiScale)
							local height = 25 * uiScale
							local border = 5 * uiScale

							Argon:Save(renderer.Window)

							Argon:ClipRoundRect(renderer.Window, {
								x = x + border,
								y = y + border,
								width = width - border * 2,
								height = height - border * 2,
							}, 4, 4)

							Argon:DrawRectangle(renderer.Window, {
								x = x + border,
								y = y + border,
								width = width - border * 2,
								height = height - border * 2,
								Color = Argon:RGBA(55, 55, 55),
								isOutline = true,
							})

							Argon:DrawRectangle(renderer.Window, {
								x = x + border,
								y = y + border,
								width = width - border * 2,
								height = height - border * 2,
								Color = Argon:RGBA(44, 44, 44),
							})

							local textWidth = Argon:MeasureText(renderer.Window, instance.Name, textSize, theme.Font)
							local plusRect = {
								x = textX + textWidth + (6 * uiScale),
								y = rowY - (14 * uiScale),
								width = imageSize,
								height = imageSize,
							}

							Immco.Image({
								x = plusRect.x,
								y = plusRect.y,
								width = plusRect.width,
								height = plusRect.height,
								Image = plusIcon,
								theme = theme,
								engine_window = renderer.Window,
							}, dt)

							local plusHitbox = clipHitboxToViewport(plusRect)
							if plusHitbox and renderer:HasClicked(plusHitbox) and canInteract then
								Selection.Set({ instance })
								createMenu.visible = true
								createMenu.x = plusRect.x + plusRect.width + (4 * uiScale)
								createMenu.y = plusRect.y
								createMenu.parent = instance
								createMenu.suppressInput = true
								canInteract = false
								renderer.UpdateCamera = false
							end

							Argon:Restore(renderer.Window)
						end

						if isSelected then
							local x = params.x + (6 * uiScale)
							local y = rowY - (18 * uiScale)
							local width = params.width - (12 * uiScale)
							local height = 25 * uiScale
							local border = 5 * uiScale

							Argon:Save(renderer.Window)

							Argon:ClipRoundRect(renderer.Window, {
								x = x,
								y = y,
								width = width,
								height = height,
							}, 6, 6)

							Argon:DrawRectangle(renderer.Window, {
								x = x,
								y = y,
								width = width,
								height = height,
								Color = Argon:RGBA(45, 125, 255, 255),
							})

							Argon:Restore(renderer.Window)

							Argon:Save(renderer.Window)

							Argon:ClipRoundRect(renderer.Window, {
								x = x + border,
								y = y + border,
								width = width - border * 2,
								height = height - border * 2,
							}, 4, 4)

							Argon:DrawRectangle(renderer.Window, {
								x = x + border,
								y = y + border,
								width = width - border * 2,
								height = height - border * 2,
								Color = Argon:RGBA(45, 125, 255, 100),
							})

							Argon:Restore(renderer.Window)
						end

						if rowHitbox and renderer:HasClicked(rowHitbox) and canInteract then
							if clickedInstance(instance) then
								-- Double click
								if instance:IsA("ScriptContainer") then
									ishared.StudioSystem:Fire("toggle_code_editor", true)
									return
								end

								ishared.StudioSystem:Fire("toggle_code_editor", false)

								if hasChildren then
									expanded[instance] = not expanded[instance]
								end
							else
								-- First click
								Selection.Set({ instance })
							end
						end

						if hasChildren then
							local arrow = expanded[instance] and expandedIcon or arrowRight

							Immco.Image({
								x = indent,
								y = rowY - (14 * uiScale),
								width = imageSize,
								height = imageSize,
								Image = arrow,
								theme = theme,
								engine_window = renderer.Window,
							}, dt)

							local arrowHitbox = clipHitboxToViewport({
								x = indent,
								y = rowY - (14 * uiScale),
								width = imageSize,
								height = imageSize,
							})
							if arrowHitbox and renderer:HasClicked(arrowHitbox) and canInteract then
								expanded[instance] = not expanded[instance]
							end
						end

						Immco.Image({
							x = indent + imageSize,
							y = rowY - (14 * uiScale),
							width = imageSize,
							height = imageSize,
							Image = iconCache[instance.ClassName],
							theme = theme,
							engine_window = renderer.Window,
						}, dt)

						Immco.Text({
							x = textX,
							y = rowY,
							TextSize = textSize,
							theme = theme,
							text = instance.Name,
							Color = theme.TextColor,
							engine_window = renderer.Window,
						}, dt)
					end

					local renderState = { y = params.y + yOffset, rowIndex = 0 }
					for _, service in ipairs(services) do
						walkVisible(service, 0, renderState, function(instance, depth, rowY, idx)
							renderInstance(instance, depth, rowY)
						end)
					end
				end,
			}, dt)

			if createMenu.visible then
				local menuHeight = math.max(120, math.min(absoluteSize.Y - 55, 420))
				local menuX = math.min(createMenu.x, absolutePosition.X + absoluteSize.X - 230)
				local menuY = math.min(createMenu.y, absolutePosition.Y + absoluteSize.Y - menuHeight - 8)

				Immco.ContextMenu({
					id = "explorer-create-instance",
					x = math.max(absolutePosition.X + 8, menuX),
					y = math.max(absolutePosition.Y + 35, menuY),
					width = 220,
					MaxHeight = menuHeight,
					items = getCreateClassItems(),
					EnableSearch = true,
					SearchPlaceholder = "Search classes...",
					SuppressInput = createMenu.suppressInput,
					RetainedStorage = contextMenuStorage,
					renderer = renderer,
					engine_window = renderer.Window,
					theme = theme,
					onClose = function()
						createMenu.visible = false
						createMenu.parent = nil
						canInteract = true
						renderer.UpdateCamera = true
					end,
				}, dt)
				createMenu.suppressInput = false
			end
		end,
	}, dt)
end)
