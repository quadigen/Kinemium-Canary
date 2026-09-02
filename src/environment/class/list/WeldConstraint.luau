-- description: "Creates a weld constraint between two parts."
local NetworkOwnership = require("@NetworkOwnership")
local ConstraintVisualizer = require("@ConstraintVisualizer")
local ConstraintRetry = require("@ConstraintRetry")

local propTable = {
	Part0 = nil,
	Part1 = nil,

	Enabled = true,
	Visible = true,
	Name = "WeldConstraint",
	ElapsedTime = 0,
}

return {
	class = "WeldConstraint",

	callback = function(instance, renderer, datamodel)
		local KinemiumPhysicsService = datamodel:GetService("UnifiedPhysicsService")

		instance:SetProperties(propTable)

		local function rebuild()
			ConstraintRetry.Cancel(instance)
			if instance._active then
				KinemiumPhysicsService.RemoveConstraint(instance._active)
				instance._active = nil
			end

			if not instance.Enabled then
				return
			end

			if not instance.Part0 or not instance.Part1 then
				return
			end

			if not NetworkOwnership.ShouldSimulateConstraintForMachine(instance, datamodel) then
				return
			end

			local retryCount = 0
			local function tryCreate()
				if not instance.Part0 or not instance.Part1 or not instance.Enabled then
					return
				end

				if not NetworkOwnership.ShouldSimulateConstraintForMachine(instance, datamodel) then
					return
				end

				local result = KinemiumPhysicsService.CreateWeld(instance.Part0, instance.Part1)
				if result then
					instance._active = result
				else
					retryCount += 1
					if retryCount < 30 then
						ConstraintRetry.Schedule(instance, tryCreate)
					else
						warn("[WeldConstraint] Gave up waiting for physics bodies for", instance.Name)
					end
				end
			end

			tryCreate()
		end

		instance.Changed:Connect(function(property)
			if property == "Part0" or property == "Part1" or property == "Enabled" then
				ConstraintRetry.Schedule(instance, rebuild, 0)
			end
		end)
		NetworkOwnership.ObserveConstraint(instance, function()
			ConstraintRetry.Schedule(instance, rebuild, 0)
		end)
		ConstraintVisualizer.Attach(instance, renderer)

		return instance
	end,

	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
