-- description: "Applies low, mid, and high frequency gain to a Sound."
local AudioEffectBridge = require("@AudioEffectBridge")

return AudioEffectBridge.Define("EqualizerSoundEffect", {
	Enabled = true,
	LowGain = 0,
	MidGain = 0,
	HighGain = 0,
	Name = "EqualizerSoundEffect",
	BaseClass = "AudioEffect",
})
