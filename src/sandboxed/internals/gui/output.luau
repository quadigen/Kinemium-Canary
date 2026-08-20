local RunService = game:GetService("RunService")
local StudioThemeService = game:GetService("StudioThemeService")
local Immco = require("@Immco")
local theme = StudioThemeService.SelectedTheme
local Argon = require("@Argon")

repeat
	task.wait()
until game.CoreGui:FindFirstChild("Studio")

local Output = Instance.new("Frame")
Output.Name = "Output"
Output.Size = theme.OutputCoordinates.Size
Output.Position = theme.OutputCoordinates.Position
Output.Parent = game.CoreGui:FindFirstChild("Studio")
Output.BackgroundTransparency = 1

local LogService = game:GetService("LogService")
local textSize = 16
local logs = {}

renderer.Pool.new("2d", function()
	local dt = renderer.RuntimeLibrary.dt
	local absolutePosition = Output.AbsolutePosition
	local absoluteSize = Output.AbsoluteSize

	Output.Size = theme.OutputCoordinates.Size
	Output.Position = theme.OutputCoordinates.Position

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
		title = "Output",
		theme = theme,
		engine_window = renderer.Window,

		callback = function(params)
			local y = params.y + 23
			local x = params.x + 10
			local history = LogService.GetLogHistory()

			for _, log in ipairs(history) do
				local timestamp = os.date("%H:%M:%S", log.timestamp)

				Immco.Text({
					x = x,
					y = y,
					TextSize = textSize,
					theme = theme,
					Font = Argon:CreateFont(theme.Font),
					text = timestamp,
					Color = theme.SecondaryTextColor,
					engine_window = renderer.Window,
				}, dt)

				Immco.Text({
					x = x + 80,
					y = y,
					TextSize = textSize,
					theme = theme,
					Font = Argon:CreateFont(theme.Font),
					text = tostring(log.message),
					Color = theme.TextColor,
					engine_window = renderer.Window,
				}, dt)

				y += 18
			end
		end,
	}, dt)
end)
