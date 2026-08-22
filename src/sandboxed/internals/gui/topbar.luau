local RunService = game:GetService("RunService")
local StudioThemeService = game:GetService("StudioThemeService")
local Immco = require("@Immco")
local theme = StudioThemeService.SelectedTheme
local Argon = require("@Argon")
local retained = {}

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

local buttonCategories = {
	{
		name = "Engine",
		buttons = {
			{
				name = "File",
				callback = function()
					print("Play")
				end,
			},
			{
				name = "Game",
				callback = function()
					print("Stop")
				end,
			},
			{
				name = "Projects",
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
				name = "Test",
				callback = function()
					print("Overview")
				end,
			},
			{
				name = "Plugins",
				callback = function()
					print("Projects")
				end,
			},
			{
				name = "View",
				callback = function()
					print("Projects")
				end,
			},
		},
	},
}

renderer.Pool.new("2d", function(lib)
	local absolutePosition = Topbar.AbsolutePosition
	local absoluteSize = Topbar.AbsoluteSize
	local dt = lib.dt
	Topbar.Size = theme.TopbarCoordinates.Size
	Topbar.Position = theme.TopbarCoordinates.Position

	local buttonX = absolutePosition.X + 30
	local buttonY = absolutePosition.Y + 2
	local buttonHeight = absoluteSize.Y - 4

	local textSize = 16
	local horizontalPadding = 12
	local buttonSpacing = 2
	local categorySpacing = 8
	local separatorWidth = 1
	local font = Argon:CreateFont(theme.Font)

	if not absolutePosition then
		return
	end
	if not absoluteSize then
		return
	end

	Argon:Save(renderer.Window)

	Argon:ClipRoundRect(renderer.Window, {
		x = absolutePosition.X,
		y = absolutePosition.Y,
		width = absoluteSize.X,
		height = absoluteSize.Y,
	}, 6, 6)

	Argon:DrawRectangle(renderer.Window, {
		x = absolutePosition.X,
		y = absolutePosition.Y,
		width = absoluteSize.X,
		height = absoluteSize.Y,
		Color = theme.BgColor,
	})

	Immco.Image({
		x = absolutePosition.X + 3,
		y = absolutePosition.Y + 3,
		width = 23,
		height = 23,
		Image = icon,
		theme = theme,
		engine_window = renderer.Window,
	}, dt)

	Argon:Restore(renderer.Window)

	for categoryIndex, category in ipairs(buttonCategories) do
		local categoryStartX = buttonX
		local currentX = categoryStartX

		for _, button in ipairs(category.buttons) do
			local textWidth = Argon:MeasureText(renderer.Window, button.name, textSize, font)

			local buttonWidth = textWidth + horizontalPadding * 2

			local btnRect = {
				x = currentX,
				y = buttonY,
				width = buttonWidth,
				height = buttonHeight,
			}

			local isHovered = renderer:isMouseInRect(btnRect)

			Immco.TextButton({
				x = currentX,
				y = buttonY,
				width = buttonWidth,
				height = buttonHeight,

				text = button.name,

				Color = isHovered and theme.SecondaryColor or theme.BgColor,

				TextColor = theme.SecondaryTextColor,

				BgVisible = categoryIndex ~= 1,

				theme = theme,
				engine_window = renderer.Window,

				callback = function()
					button.callback()
				end,
			}, dt)

			currentX += buttonWidth + buttonSpacing
		end

		if categoryIndex < #buttonCategories then
			local separatorX = currentX + (categorySpacing / 2)

			Argon:DrawRectangle(renderer.Window, {
				x = separatorX,
				y = absolutePosition.Y + 5,
				width = separatorWidth,
				height = absoluteSize.Y - 10,
				Color = Argon:RGBA(70, 70, 70),
			})

			buttonX = separatorX + separatorWidth + categorySpacing / 2
		end
	end
end)
