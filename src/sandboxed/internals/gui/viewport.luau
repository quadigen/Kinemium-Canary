local RunService = game:GetService("RunService")
local StudioThemeService = game:GetService("StudioThemeService")
local Immco = require("@Immco")
local theme = StudioThemeService.SelectedTheme
local Argon = require("@Argon")

repeat
	task.wait()
until game.CoreGui:FindFirstChild("Studio")

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
	},
	{ iconPath = "./src/assets/images/icons/Size.png", clicked = function() end },
	{ iconPath = "./src/assets/images/icons/Rotate.png", clicked = function() end },
	{ iconPath = "./src/assets/images/icons/ColorEffect.png", clicked = function() end },
}

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

	Immco.Widget({
		x = absolutePosition.X,
		y = absolutePosition.Y + 5,
		width = absoluteSize.X,
		height = absoluteSize.Y,
		title = "Viewport",
		theme = theme,
		engine_window = renderer.Window,

		callback = function(params)
			renderer:Set3DTexProps(
				absolutePosition.X + 5,
				absolutePosition.Y + 35,
				absoluteSize.X - 10,
				absoluteSize.Y - 35
			)

			Immco.RoundedRectangle({
				x = absolutePosition.X + 8,
				y = absolutePosition.Y + 38,
				width = 44,
				height = math.max(100, (#buttons * 40) + 10),
				theme = theme,
				Color = Argon:RGBA(70, 70, 70),
				engine_window = renderer.AboveCanvas,
			}, dt)

			Immco.RoundedRectangle({
				x = absolutePosition.X + 10,
				y = absolutePosition.Y + 40,
				width = 40,
				height = math.max(80, (#buttons * 40) + 5),
				theme = theme,
				Color = Argon:RGBA(44, 44, 44),
				engine_window = renderer.AboveCanvas,

				callback = function(params)
					for i, btn in ipairs(buttons) do
						local isInRect = renderer:isMouseInRect({
							x = params.x + 2.5,
							y = params.y + 5 + ((i - 1) * 40),
							width = 35,
							height = 35,
						})

						Immco.ImageButton({
							x = params.x + 2.5,
							y = params.y + 5 + ((i - 1) * 40),
							width = 35,
							height = 35,
							Image = Argon:CreateImageFromPath(btn.iconPath),
							Color = isInRect and Argon:RGBA(33, 33, 33) or Argon:RGBA(44, 44, 44),
							padding = 2.5,
							preserveAspectRatio = false,
							imageAspectRatio = 0.1,
							imageWidth = 80,
							imageHeight = 80,
							theme = theme,
							engine_window = renderer.AboveCanvas,
						}, dt)

						if
							renderer:HasClicked({
								x = params.x + 2.5,
								y = params.y + 5 + ((i - 1) * 40),
								width = 35,
								height = 35,
							})
						then
							btn.clicked()
						end

						if i < #buttons then
							Immco.RoundedRectangle({
								x = (params.x + 2.5) - 3,
								y = params.y + 40 + ((i - 1) * 40),
								width = 40,
								height = 2,
								CornerRadius = 1,
								Color = Argon:RGBA(70, 70, 70),
								theme = theme,
								engine_window = renderer.AboveCanvas,
							})
						end
					end
				end,
			}, dt)
		end,
	}, dt)
end)
