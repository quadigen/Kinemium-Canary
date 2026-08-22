local StudioThemeService = game:GetService("StudioThemeService")
local Immco = require("@Immco")
local theme = StudioThemeService.SelectedTheme
local Argon = require("@Argon")
local Selection = game:GetService("Selection")
local PropertyCategories = require("@propertyCategories")
local inspectorStorage = {}

repeat
	task.wait()
until game.CoreGui:FindFirstChild("Studio")

local Inspector = Instance.new("Frame")
Inspector.Name = "Inspector"
Inspector.Size = theme.InspectorCoordinates.Size
Inspector.Position = theme.InspectorCoordinates.Position
Inspector.Parent = game.CoreGui:FindFirstChild("Studio")
Inspector.BackgroundTransparency = 1

local uiScale = 1
local textSize = 15 * uiScale
local headerTextSize = 15 * uiScale
local rowHeight = 25 * uiScale
local headerHeight = 24 * uiScale
local contentPadding = 10 * uiScale
local imageSize = 14 * uiScale
local groupBottomPadding = 8 * uiScale
local propertyPadding = 2 * uiScale
local propertySeparatorWidth = 1 * uiScale
local searchBoxHeight = 20

local iconPath = "./src/assets/images/icons/"
local arrowRight = Argon:CreateImageFromPath(iconPath .. "ArrowRight.png")
local expandedIcon = Argon:CreateImageFromPath(iconPath .. "ArrowDown.png")

local categoryExpanded = setmetatable({}, {
	__index = function()
		return true
	end,
})

local function truncate(str, maxLength)
	if #str <= maxLength then
		return str
	end

	return string.sub(str, 1, maxLength) .. "...."
end

local readonly = {
	["ClassName"] = true,
}

local categoryOrder = {
	"Object",
	"Transform",
	"Appearance",
	"Behavior",
	"Network",
	"Shader",
}

local adapters = {
	boolean = function(prop, firstObj, prop_x, prop_y, dt)
		Immco.Checkbox({
			x = prop_x,
			y = prop_y,
			bool = prop.value,
			height = 20,
			width = 20,
			theme = theme,
			Color = Argon:RGBA(33, 33, 33),
			isOutline = false,
			engine_window = renderer.Window,
		}, dt)

		Immco.Text({
			x = prop_x + 30,
			y = prop_y + 15,
			TextSize = headerTextSize,
			theme = theme,
			Font = Argon:CreateFont(theme.Font),
			text = prop.value == true and "true" or "false",
			Color = theme.TextColor,
			engine_window = renderer.Window,
		}, dt)

		if renderer:HasClicked({
			x = prop_x,
			y = prop_y,
			width = 20,
			height = 20,
		}) then
			firstObj[prop.name] = not prop.value
		end
	end,

	string = function(prop, firstObj, prop_x, prop_y, dt, width)
		Immco.TextInput({
			x = prop_x,
			y = prop_y,
			width = width,
			height = 16,
			id = prop.name,
			RetainedStorage = inspectorStorage,
			renderer = renderer,
			theme = theme,
			ReadOnly = readonly[prop.name] ~= nil,
			Color = { R = 0.15, G = 0.15, B = 0.15, A = 1 },
			FocusColor = { R = 0.2, G = 0.2, B = 0.25, A = 1 },
			TextColor = { R = 1, G = 1, B = 1, A = 1 },
			PlaceholderColor = { R = 0.5, G = 0.5, B = 0.5, A = 1 },
			placeholder = tostring(prop.value),
			OnSubmit = function(text)
				firstObj[prop.name] = text
			end,
			engine_window = renderer.Window,
		}, dt)
	end,

	Vector3 = function(prop, firstObj, prop_x, prop_y, dt, width)
		local value = prop.value

		local boxWidth = (width - 8) / 3

		local function input(id, x, component, color)
			Immco.TextInput({
				x = x,
				y = prop_y,
				width = boxWidth,
				height = 16,
				id = prop.name .. "_" .. id,
				RetainedStorage = inspectorStorage,
				renderer = renderer,
				theme = theme,

				Color = {
					R = color.R,
					G = color.G,
					B = color.B,
					A = 1,
				},

				FocusColor = {
					R = color.R + 0.05,
					G = color.G + 0.05,
					B = color.B + 0.05,
					A = 1,
				},

				TextColor = { R = 1, G = 1, B = 1, A = 1 },
				PlaceholderColor = { R = 0.5, G = 0.5, B = 0.5, A = 1 },

				placeholder = tostring(value[component]),

				OnSubmit = function(text)
					local number = tonumber(text)
					if not number then
						return
					end

					local current = firstObj[prop.name]
					firstObj[prop.name] = Vector3.new(
						component == "X" and number or current.X,
						component == "Y" and number or current.Y,
						component == "Z" and number or current.Z
					)
				end,

				engine_window = renderer.Window,
			}, dt)
		end

		input("R", prop_x, "X", { R = 0.35, G = 0.08, B = 0.08 })
		input("G", prop_x + boxWidth + 4, "Y", { R = 0.08, G = 0.35, B = 0.08 })
		input("B", prop_x + (boxWidth + 4) * 2, "Z", { R = 0.08, G = 0.15, B = 0.35 })
	end,

	Color3 = function(prop, firstObj, prop_x, prop_y, dt, width)
		local value = prop.value

		local boxWidth = (width - 8) / 3

		local function input(id, x, component, color)
			Immco.TextInput({
				x = x,
				y = prop_y,
				width = boxWidth,
				height = 16,
				id = prop.name .. "_" .. id,
				RetainedStorage = inspectorStorage,
				renderer = renderer,
				theme = theme,

				Color = {
					R = color.R,
					G = color.G,
					B = color.B,
					A = 1,
				},

				FocusColor = {
					R = color.R + 0.05,
					G = color.G + 0.05,
					B = color.B + 0.05,
					A = 1,
				},

				TextColor = { R = 1, G = 1, B = 1, A = 1 },
				PlaceholderColor = { R = 0.5, G = 0.5, B = 0.5, A = 1 },

				placeholder = tostring(value[component]),

				OnSubmit = function(text)
					local number = tonumber(text)
					if not number then
						return
					end

					local current = firstObj[prop.name]

					firstObj[prop.name] = Color3.new(
						component == "R" and number or current.R,
						component == "G" and number or current.G,
						component == "B" and number or current.B
					)
				end,

				engine_window = renderer.Window,
			}, dt)
		end

		input("R", prop_x, "R", { R = 0.35, G = 0.08, B = 0.08 })
		input("G", prop_x + boxWidth + 4, "G", { R = 0.08, G = 0.35, B = 0.08 })
		input("B", prop_x + (boxWidth + 4) * 2, "B", { R = 0.08, G = 0.15, B = 0.35 })
	end,

	EnumItem = function(prop, firstObj, prop_x, prop_y, dt, width)
		local val = prop.value
		if val.EnumType then
			local items = val.EnumType:GetEnumItems()
			local result = {}

			for _, item in pairs(items) do
				table.insert(result, item.Name)
			end

			Immco.Dropdown({
				RetainedStorage = inspectorStorage,
				id = prop.name .. "_dropdown",
				renderer = renderer,
				window = renderer.Window,
				theme = theme,

				x = prop_x,
				y = prop_y,
				width = width,
				height = 16,

				Options = result,
				Placeholder = val.Name,
				MaxVisibleOptions = 4,

				OnChanged = function(index, chosenValue)
					firstObj[prop.name] = val.EnumType[chosenValue]
				end,
			}, dt)
		end
	end,
}

renderer.Pool.new("2d", function()
	local dt = renderer.RuntimeLibrary.dt
	local absolutePosition = Inspector.AbsolutePosition
	local absoluteSize = Inspector.AbsoluteSize

	Inspector.Size = theme.InspectorCoordinates.Size
	Inspector.Position = theme.InspectorCoordinates.Position

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
		title = "Inspector",
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
				ContentHeight = 500,

				ScrollSpeed = 50,
				ScrollLerpSpeed = 20,

				renderer = renderer,
				window = renderer.Window,
				theme = theme,

				RetainedStorage = inspectorStorage,
				callback = function(params)
					Immco.TextInput({
						x = params.x + 6,
						y = params.y + 4,
						width = params.width - 12 * uiScale,
						height = searchBoxHeight,
						id = "InspectorSearch",
						RetainedStorage = inspectorStorage,
						renderer = renderer,
						theme = theme,

						Color = { R = 0.15, G = 0.15, B = 0.15, A = 1 },
						FocusColor = { R = 0.2, G = 0.2, B = 0.25, A = 1 },
						TextColor = theme.TextColor,
						PlaceholderColor = { R = 0.5, G = 0.5, B = 0.5, A = 1 },

						placeholder = "Search Properties..",
						OnSubmit = function(text) end,

						engine_window = renderer.Window,
					}, dt)

					local object = Selection.Get()

					if not object or not object[1] then
						return
					end

					local firstObj = object[1]

					local grouped = {}
					local seenCategories = {}

					for property, value in pairs(firstObj:GetProperties()) do
						local category = PropertyCategories.getPropertyCategory(property) or "Uncategorized"

						if type(value) == "function" then
							continue
						end

						local list = grouped[category]
						if not list then
							list = {}
							grouped[category] = list
						end

						list[#list + 1] = { name = property, value = value }
						seenCategories[category] = true
					end

					for _, list in pairs(grouped) do
						table.sort(list, function(a, b)
							return a.name < b.name
						end)
					end

					local orderedCategories = {}
					local placed = {}

					for _, category in ipairs(categoryOrder) do
						if seenCategories[category] then
							orderedCategories[#orderedCategories + 1] = category
							placed[category] = true
						end
					end

					local leftovers = {}
					for category in pairs(seenCategories) do
						if not placed[category] then
							leftovers[#leftovers + 1] = category
						end
					end
					table.sort(leftovers)

					for _, category in ipairs(leftovers) do
						orderedCategories[#orderedCategories + 1] = category
					end

					-- render
					local rowY = params.y + 28 + searchBoxHeight

					for _, category in ipairs(orderedCategories) do
						local props = grouped[category]
						local isExpanded = categoryExpanded[category]
						local propCount = isExpanded and #props or 0

						local x = params.x + (6 * uiScale)
						local groupTop = rowY - (18 * uiScale)
						local width = params.width - (12 * uiScale)
						local groupHeight = headerHeight + (propCount * rowHeight) + groupBottomPadding

						Argon:Save(renderer.Window)

						Argon:ClipRoundRect(renderer.Window, {
							x = x,
							y = groupTop,
							width = width,
							height = groupHeight,
						}, 6, 6)

						Argon:DrawRectangle(renderer.Window, {
							x = x,
							y = groupTop,
							width = width,
							height = groupHeight,
							Color = Argon:RGBA(45, 45, 45),
						})

						Argon:DrawRectangle(renderer.Window, {
							x = x,
							y = groupTop,
							width = width,
							height = headerHeight,
							Color = Argon:RGBA(33, 33, 33),
							isOutline = true,
						})

						Argon:DrawRectangle(renderer.Window, {
							x = x,
							y = groupTop,
							width = width,
							height = headerHeight,
							Color = Argon:RGBA(45, 45, 45),
						})

						Argon:Restore(renderer.Window)

						-- toggle arrow
						local arrow = isExpanded and expandedIcon or arrowRight

						Immco.Image({
							x = x + (6 * uiScale),
							y = rowY - (14 * uiScale),
							width = imageSize,
							height = imageSize,
							Image = arrow,
							theme = theme,
							engine_window = renderer.Window,
						}, dt)

						-- header label
						Immco.Text({
							x = x + (6 * uiScale) + imageSize + (6 * uiScale),
							y = rowY,
							TextSize = headerTextSize,
							theme = theme,
							Font = Argon:CreateFont(theme.Font),
							text = category,
							Color = theme.TextColor,
							engine_window = renderer.Window,
						}, dt)

						-- whole header row is clickable to toggle
						if
							renderer:HasClicked({
								x = x,
								y = groupTop,
								width = width,
								height = headerHeight,
							})
						then
							categoryExpanded[category] = not isExpanded
						end

						rowY += headerHeight

						if isExpanded then
							local propertiesTop = rowY - 15
							local propertiesHeight = #props * rowHeight

							Argon:Save(renderer.Window)

							Argon:ClipRoundRect(renderer.Window, {
								x = x,
								y = propertiesTop,
								width = width,
								height = propertiesHeight,
							}, 6, 6)

							for _, prop in ipairs(props) do
								local truncated = truncate(prop.name, 15)

								local propertyX = x + propertyPadding
								local propertyY = rowY - 15
								local propertyWidth = width - (propertyPadding * 2)
								local propertyHeight = rowHeight

								local separatorX = propertyX + (propertyWidth * 0.5)

								Argon:DrawRectangle(renderer.Window, {
									x = separatorX,
									y = propertyY,
									width = propertySeparatorWidth,
									height = propertyHeight,
									Color = Argon:RGBA(60, 60, 60),
								})

								-- Property name
								Immco.Text({
									x = propertyX + contentPadding,
									y = rowY,
									TextSize = textSize,
									theme = theme,
									Font = Argon:CreateFont(theme.Font),
									text = tostring(truncated),
									Color = theme.TextColor,
									engine_window = renderer.Window,
								}, dt)

								local prop_x = separatorX + (4 * uiScale)
								local prop_y = rowY - 15

								if adapters[typeof(prop.value)] then
									adapters[typeof(prop.value)](
										prop,
										firstObj,
										prop_x,
										prop_y,
										dt,
										(propertyWidth * 0.5) - 10
									)
								end

								rowY += rowHeight
							end

							Argon:Restore(renderer.Window)
						end

						rowY += groupBottomPadding
						rowY += 6 * uiScale
					end
				end,
			}, dt)
		end,
	}, dt)
end)
