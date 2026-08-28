local Instance = require("@Instance")
local GuiMirror = require("./GuiMirror")

local PlayerGui = Instance.new("PlayerGui")
local guiMirroringBound = false
local guiMirrorController = nil

PlayerGui.InitRenderer = function(renderer, renderer_signal, datamodel)
	PlayerGui:SetProperties({
		ResetOnSpawn = true,
	})
	GuiMirror.MarkTreeLocalOnly(PlayerGui)

	renderer.Pool.new("2da", function()
		for _, child in pairs(PlayerGui:GetChildren()) do
			if child["render"] then
				child.render()
			end
		end
	end)

	if datamodel and guiMirroringBound == false then
		guiMirroringBound = true
		guiMirrorController = GuiMirror.new(PlayerGui)
		guiMirrorController:BindContainer(datamodel.StarterGui, "StarterGui")
	end

	return PlayerGui
end

return PlayerGui
