local RunService = game:GetService("RunService")
local StudioThemeService = game:GetService("StudioThemeService")
local Immco = require("@Immco")
local theme = StudioThemeService.SelectedTheme
local Selection = game:GetService("Selection")
local Argon = require("@Argon")

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

local arrowRight = Argon:CreateImageFromPath(iconPath .. "ArrowRight.png")
local expandedIcon = Argon:CreateImageFromPath(iconPath .. "ArrowDown.png")
local expanded = {}

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

local explorerSearch = ""
local visibleRowCount = 0
local contentHeight = 0

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

					Immco.TextInput({
						x = params.x + 6,
						y = params.y + 4,
						width = params.width - 15 * uiScale,
						height = 20,
						id = "ExplorerSearch",
						RetainedStorage = textBoxStorage,
						renderer = renderer,
						theme = theme,

						Color = { R = 0.15, G = 0.15, B = 0.15, A = 1 },
						FocusColor = { R = 0.2, G = 0.2, B = 0.25, A = 1 },
						TextColor = { R = 1, G = 1, B = 1, A = 1 },
						PlaceholderColor = { R = 0.5, G = 0.5, B = 0.5, A = 1 },

						placeholder = "Search Objects...",
						OnSubmit = function(text)
							explorerSearch = text
						end,

						engine_window = renderer.Window,
					}, dt)

					local function walkVisible(instance, depth, state, visit)
						if instance.ExplorerHidden then
							return
						end

						visit(instance, depth, state.y, state.rowIndex)

						state.y += rowHeightStep
						state.rowIndex += 1
						visibleRowCount += 1

						if expanded[instance] then
							for _, child in ipairs(instance:GetChildren()) do
								walkVisible(child, depth + 1, state, visit)
							end
						end
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
								color = (idx % 2 == 0) and Argon:RGBA(50, 50, 50) or Argon:RGBA(45, 45, 45),
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

						local isInRect = renderer:isMouseInRect({
							x = params.x + (6 * uiScale),
							y = rowY - (18 * uiScale),
							width = params.width - (12 * uiScale),
							height = rowHeight,
						})
						if isInRect then
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

						if
							renderer:HasClicked({
								x = params.x + (6 * uiScale),
								y = rowY - (18 * uiScale),
								width = params.width - (12 * uiScale),
								height = rowHeight,
							})
						then
							Selection.Set({ instance })
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

							if
								renderer:HasClicked({
									x = indent,
									y = rowY - (14 * uiScale),
									width = imageSize,
									height = imageSize,
								})
							then
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
							x = indent + (36 * uiScale),
							y = rowY,
							TextSize = textSize,
							theme = theme,
							Font = Argon:CreateFont(theme.Font),
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
		end,
	}, dt)
end)
