-- description: "Rigidly connects two attachments, preventing any relative movement between them."
local propTable = {
	Name = "RigidConstraint",
	BaseClass = "Kinemium.constraint",

	Attachment0 = nil,
	Attachment1 = nil,
	Enabled = true,
	Visible = true,
}
local NetworkOwnership = require("@NetworkOwnership")
local ConstraintVisualizer = require("@ConstraintVisualizer")
local ConstraintRetry = require("@ConstraintRetry")

return {
	class = "RigidConstraint",
	callback = function(instance, renderer, datamodel)
		local physics = datamodel:GetService("UnifiedPhysicsService")
		instance:SetProperties(propTable)
		local activeConstraint = nil

		local function cleanup()
			if activeConstraint then
				physics.RemoveConstraint(activeConstraint)
				activeConstraint = nil
			end
		end

		local function rebuild()
			ConstraintRetry.Cancel(instance)
			cleanup()
			local part0 = instance.Attachment0 and instance.Attachment0.Parent
			local part1 = instance.Attachment1 and instance.Attachment1.Parent
			if not instance.Enabled or not part0 or not part1 then
				return
			end
			if not NetworkOwnership.ShouldSimulateConstraintForMachine(instance, datamodel) then
				return
			end

			local attempts = 0
			local function tryCreate()
				if not NetworkOwnership.ShouldSimulateConstraintForMachine(instance, datamodel) then
					return
				end
				activeConstraint = physics.CreateWeld(part0, part1)
				if not activeConstraint then
					attempts += 1
					if attempts < 30 then
						ConstraintRetry.Schedule(instance, tryCreate)
					else
						warn("[RigidConstraint] Gave up waiting for physics bodies")
					end
				end
			end
			tryCreate()
		end

		instance.Changed:Connect(function(property)
			if property == "Attachment0" or property == "Attachment1" or property == "Enabled" then
				ConstraintRetry.Schedule(instance, rebuild, 0)
			end
		end)
		instance.AncestryChanged:Connect(function(_, parent)
			if not parent then
				ConstraintRetry.Cancel(instance)
				cleanup()
			end
		end)
		NetworkOwnership.ObserveConstraint(instance, function()
			ConstraintRetry.Schedule(instance, rebuild, 0)
		end)
		ConstraintVisualizer.Attach(instance, renderer)
		ConstraintRetry.Schedule(instance, rebuild, 0)
		return instance
	end,
	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
