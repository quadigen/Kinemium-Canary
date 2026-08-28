-- description: "A force that applies a constant vector to a part."
local Vector3 = require("@Vector3")
local Enum = require("@EnumMap")

local propTable = {
	Attachment0 = nil,

	Force = Vector3.new(0, 0, 0),
	RelativeTo = Enum.ActuatorRelativeTo.World,

	Enabled = true,
	Name = "VectorForce",
	ElapsedTime = 0,
}

return {
	class = "VectorForce",

	callback = function(instance, renderer, game)
		instance:SetProperties(propTable)

		local PhysicsService = game:GetService("UnifiedPhysicsService")

		renderer.Pool.new("3d", function()
			if not instance.Enabled then
				return
			end
			local attach = instance.Attachment0
			if attach and attach:IsA("Attachment") then
				local parent = attach.Parent
				if parent.BaseClass == "BasePart" then
					PhysicsService.ApplyImpulse(parent, instance.Force)
				end
			end
		end)
		return instance
	end,

	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
