-- description: "Adds configurable room reverberation to a Sound."
local AudioEffectBridge = require("@AudioEffectBridge")

return AudioEffectBridge.Define("ReverbSoundEffect", {
	Enabled = true,
	DecayTime = 1.5,
	Density = 1,
	Diffusion = 1,
	DryLevel = 0,
	WetLevel = -20,
	Name = "ReverbSoundEffect",
	BaseClass = "AudioEffect",
})
