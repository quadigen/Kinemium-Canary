-- description: "Creates a ball-and-socket joint between two attachments."
local _Vector3 = require("@Vector3")
local _signal = require("@Kinemium.signal")
local Color3 = require("@Color3")
local NetworkOwnership = require("@NetworkOwnership")
local ConstraintVisualizer = require("@ConstraintVisualizer")
local ConstraintRetry = require("@ConstraintRetry")

local propTable = {
	Attachment0 = nil,
	Attachment1 = nil,
	Enabled = true,
	Visible = true,
	Color = Color3.fromRGB(255, 255, 0),
	Radius = 0.1,
	Name = "BallSocketConstraint",
}

return {
	class = "BallSocketConstraint",

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
			local attachment0, attachment1 = instance.Attachment0, instance.Attachment1
			local part0 = attachment0 and attachment0.Parent
			local part1 = attachment1 and attachment1.Parent
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
				local point0 = part0.CFrame * attachment0.Position
				local point1 = part1.CFrame * attachment1.Position
				activeConstraint = physics.CreateBallSocket(part0, part1, point0, point1)
				if not activeConstraint then
					attempts += 1
					if attempts < 30 then
						ConstraintRetry.Schedule(instance, tryCreate)
					else
						warn("[BallSocketConstraint] Gave up waiting for physics bodies")
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
		for property, value in pairs(propTable) do
			tble[property] = value
		end
	end,
}
