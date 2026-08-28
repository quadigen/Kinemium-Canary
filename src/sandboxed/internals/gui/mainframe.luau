local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme
local Argon = require("@Argon")

-- engine isnt server nor client? its in editor mode then!
if IsServer then
	return
end

if IsClient then
	return
end

ishared.StudioSystem = Signal.new()

local Guis = Instance.new("ScreenGui")
Guis.Name = "Studio"
Guis.Parent = game.CoreGui

renderer.Pool.new("2d", function()
	Argon:DrawRectangle(renderer.Window, {
		x = 0,
		y = 0,
		width = renderer.Width,
		height = renderer.Height,
		Color = theme.BaseColor,
	})
end, -99999)
