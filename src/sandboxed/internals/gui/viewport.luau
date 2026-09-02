local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
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

local widget

local Viewport = Instance.new("Frame")
Viewport.Name = "Viewport"
Viewport.Size = theme.ViewportCoordinates.Size
Viewport.Position = theme.ViewportCoordinates.Position
Viewport.Parent = game.CoreGui:FindFirstChild("Studio")
Viewport.BackgroundTransparency = 1

export type EditorButton = {
	iconPath: string,
	clicked: () -> (),
}

local buttons: { EditorButton } = {
	{
		iconPath = "./src/assets/images/icons/Move.png",
		clicked = function()
			print("hello world")
		end,
		tooltip = "Move a 3D object.",
	},
	{ iconPath = "./src/assets/images/icons/Size.png", clicked = function() end, tooltip = "Resize a 3D object." },
	{ iconPath = "./src/assets/images/icons/Rotate.png", clicked = function() end, tooltip = "Rotate a 3D object." },
	{
		iconPath = "./src/assets/images/icons/ColorEffect.png",
		clicked = function() end,
		tooltip = "Paint a 3D object.",
	},
}

local rects = {}
local guiYOffset = 32

renderer.Pool.new("2d", function()
	local dt = renderer.RuntimeLibrary.dt
	local absolutePosition = Viewport.AbsolutePosition
	local absoluteSize = Viewport.AbsoluteSize

	Viewport.Size = theme.ViewportCoordinates.Size
	Viewport.Position = theme.ViewportCoordinates.Position

	if not absolutePosition then
		return
	end
	if not absoluteSize then
		return
	end

	for _, object in pairs(game.StarterGui:GetChildren()) do
		if object:IsA("ScreenGui") then
			object.OverrideScreenSize = true
			object.Size = UDim2.new(0, absoluteSize.X, 0, absoluteSize.Y - guiYOffset)
			object.RenderOffset = Vector2.new(absolutePosition.X, absolutePosition.Y + guiYOffset + 5)
		end
	end

	Immco.Widget({
		x = absolutePosition.X,
		y = absolutePosition.Y + 5,
		width = absoluteSize.X,
		height = absoluteSize.Y,
		title = "Viewport",
		theme = theme,
		engine_window = renderer.Window,
		renderer = renderer,

		callback = function(params)
			renderer:Set3DTexProps(absolutePosition.X, absolutePosition.Y + 35, absoluteSize.X, absoluteSize.Y - 35)
			widget = params
		end,
	}, dt)
end)

renderer.Pool.new("2da", function()
	local params = widget

	if not params then
		return
	end

	local dt = renderer.RuntimeLibrary.dt
	local absolutePosition = Viewport.AbsolutePosition
	local absoluteSize = Viewport.AbsoluteSize

	local selected = Selection.Get()
	local items = {}
	local object = selected and selected[1]

	if selected and object then
		local path = object:GetFullName()
		local split = string.split(path, ".")

		for _, item in pairs(split) do
			table.insert(items, {
				Text = item,

				OnClick = function()
					Selection.Clear()
					Selection.Set({ object })
				end,
			})
		end
	end

	Immco.Breadcrumb({
		x = absolutePosition.X + 8,
		y = absolutePosition.Y + absoluteSize.Y - 35,
		height = 32,

		engine_window = renderer.Window,
		renderer = renderer,
		theme = theme,

		Collapsed = true,
		Items = items,

		OnEllipsisClick = function(hiddenItems) end,
	}, dt)

	local toolbarX = absolutePosition.X + 10
	local toolbarY = absolutePosition.Y + 40

	local buttonSize = 40
	local iconSize = 30

	local buttonItems = {}

	for i, btn in ipairs(buttons) do
		local btnRect = {
			x = toolbarX,
			y = toolbarY + ((i - 1) * buttonSize),
			width = buttonSize,
			height = buttonSize,
		}

		rects[btn.iconPath] = btnRect

		table.insert(buttonItems, {
			Icon = Argon:CreateImageFromPath(btn.iconPath),

			Width = buttonSize,
			Height = buttonSize,

			IconSize = iconSize,

			OnClick = function()
				btn.clicked()
			end,
		})
	end

	Immco.RoundedRectangle({
		x = toolbarX - 2,
		y = toolbarY - 2,

		width = buttonSize + 4,
		height = (#buttons * buttonSize) + 4,

		CornerRadius = 6,

		Color = Argon:RGBA(70, 70, 70),

		theme = theme,
		engine_window = renderer.Window,
	}, dt)

	Immco.ButtonGroup({
		x = toolbarX,
		y = toolbarY,

		width = buttonSize,

		engine_window = renderer.Window,
		renderer = renderer,
		theme = theme,

		Orientation = "vertical",

		ItemHeight = buttonSize,
		IconSize = iconSize,
		PaddingX = 0,

		CornerRadius = 4,

		BackgroundColor = Argon:RGBA(44, 44, 44),
		ButtonColor = Argon:RGBA(44, 44, 44),

		HoverColor = Argon:RGBA(33, 33, 33),
		PressedColor = Argon:RGBA(25, 25, 25),

		BorderColor = Argon:RGBA(70, 70, 70),
		DividerColor = Argon:RGBA(70, 70, 70),

		ShowBorder = false,
		ShowDividers = true,

		Items = buttonItems,
	}, dt)

	-- Tooltips
	for _, btn in pairs(buttons) do
		local btnRect = rects[btn.iconPath]

		if not btnRect then
			continue
		end

		Immco.Tooltip({
			RetainedStorage = retained,

			id = btn.iconPath,

			renderer = renderer,
			canvas = renderer.Window,
			window = renderer.Window,

			theme = theme,

			HoverRect = btnRect,
			Text = btn.tooltip,

			HoverDelay = 0.4,
			FadeSpeed = 14,

			Placement = "right",

			Offset = {
				x = 12,
				y = 40,
			},

			Gap = 8,
			MaxWidth = 220,
			Padding = 6,
			CornerRadius = 6,
		}, dt)
	end
end)
