-- description: "Adds a delayed echo to a Sound."
local AudioEffectBridge = require("@AudioEffectBridge")

return AudioEffectBridge.Define("EchoSoundEffect", {
	Enabled = true,
	Delay = 0.25,
	Feedback = 0.25,
	DryLevel = 0,
	WetLevel = -10,
	Name = "EchoSoundEffect",
	BaseClass = "AudioEffect",
})
