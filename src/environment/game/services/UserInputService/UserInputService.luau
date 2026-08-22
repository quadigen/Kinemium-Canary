local Instance = require("@Instance")
local signal = require("@Kinemium.signal")
local Enum = require("@EnumMap")

local UserInputService = Instance.new("UserInputService")
UserInputService._Intents = Enum.PluginIntents.Input

UserInputService.InitRenderer = function(renderer, renderer_signal)
	if IsHeadless then
		UserInputService:SetProperties({})
		return
	end
end

return UserInputService
