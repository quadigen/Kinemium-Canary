local Instance = require("@Instance")
local signal = require("@Kinemium.signal")
local Enum = require("@EnumMap")

local Localization = Instance.new("Localization")
Localization._Intents = Enum.PluginIntents.Input

local argon = require("@Argon")
local yaml = zune.serde.yaml

Localization.InitRenderer = function(renderer, renderer_signal)
	if IsHeadless then
		Localization:SetProperties({})
		return
	end

	function Localization:AddLayer(filePath: string)
		local read = zune.fs.readFile(filePath)
		if read then
			local decoded = yaml.decode(read)
			if decoded then
				local locale = decoded.locale
				local translations = decoded.translations
				argon:CreateTranslationLayer(locale, translations)
			end
		end
	end

	function Localization:Use(locale: string)
		argon:SetActiveTranslationLayer(name)
	end
end

return Localization
