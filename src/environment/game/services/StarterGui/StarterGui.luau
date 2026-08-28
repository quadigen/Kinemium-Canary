local Instance = require("@Instance")
local StarterGui = Instance.new("StarterGui")
local Enum = require("@EnumMap")

StarterGui:SetProperties({
	Enabled = true,
	ResetOnSpawn = true,
	ZIndexBehavior = "Sibling",
	CoreGuiEnabled = true,
})

StarterGui._Intents = Enum.PluginIntents.UI

StarterGui.InitRenderer = function(renderer, signal, datamodel)
	task.spawn(function()
		repeat
			task.wait()
		until datamodel.Loaded == true

		local CoreGui = datamodel:GetService("CoreGui")

		function StarterGui:SetCoreGuiEnabled(coreGuiType, enabled: boolean)
			CoreGui:SetCoreGuiEnabled(coreGuiType, enabled)
		end

		function StarterGui:GetCore(coreName)
			return CoreGui:GetCore(coreName)
		end

		function StarterGui:SetCore(parameterName: string, value)
			CoreGui:SetCore(parameterName, value)
		end

		function StarterGui:GetCoreGuiEnabled(coreGuiType)
			return CoreGui:GetCoreGuiEnabled(coreGuiType)
		end

		renderer.Pool.new("2da", function()
			for _, child in pairs(StarterGui:GetChildren()) do
				if child["render"] then
					child.render()
				end
			end
		end)
	end)

	return StarterGui
end

return StarterGui
