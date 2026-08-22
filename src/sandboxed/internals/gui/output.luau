local RunService = game:GetService("RunService")
local StudioThemeService = game:GetService("StudioThemeService")
local Immco = require("@Immco")
local theme = StudioThemeService.SelectedTheme
local Argon = require("@Argon")
local storage = {}

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
local search = ""
local contentHeight = 0

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

	contentHeight = 0

	Immco.Widget({
		x = absolutePosition.X,
		y = absolutePosition.Y + 5,
		width = absoluteSize.X,
		height = absoluteSize.Y,
		title = "Output",
		theme = theme,
		engine_window = renderer.Window,

		callback = function(params)
			Immco.TextInput({
				x = params.x + 80,
				y = params.y - 28,
				width = params.width - 90,
				height = 20,
				id = "OutputSearch",
				RetainedStorage = storage,
				renderer = renderer,
				theme = theme,

				Color = { R = 0.15, G = 0.15, B = 0.15, A = 1 },
				FocusColor = { R = 0.2, G = 0.2, B = 0.25, A = 1 },
				TextColor = theme.TextColor,
				PlaceholderColor = { R = 0.5, G = 0.5, B = 0.5, A = 1 },

				placeholder = "Search Output..",
				OnSubmit = function(text)
					search = text
				end,

				engine_window = renderer.Window,
			}, dt)

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

				RetainedStorage = storage,
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
						contentHeight += 18
					end
				end,
			}, dt)
		end,
	}, dt)
end)
