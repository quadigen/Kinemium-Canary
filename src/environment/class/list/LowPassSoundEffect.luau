-- description: "Removes frequencies above the configured cutoff."
local AudioEffectBridge = require("@AudioEffectBridge")

return AudioEffectBridge.Define("LowPassSoundEffect", {
	Enabled = true,
	CutoffFrequency = 5000,
	Name = "LowPassSoundEffect",
	BaseClass = "AudioEffect",
})
