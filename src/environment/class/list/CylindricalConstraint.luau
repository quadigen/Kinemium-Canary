-- description: "Constrains two attachments to slide and rotate along a shared axis."
local Color3 = require("@Color3")
local NetworkOwnership = require("@NetworkOwnership")
local ConstraintVisualizer = require("@ConstraintVisualizer")
local ConstraintRetry = require("@ConstraintRetry")

local adapterOk, adapter = pcall(require, "@RaylibAdapter")
adapter = adapterOk and adapter or nil

local propTable = {
	Attachment0 = nil,
	Attachment1 = nil,
	Enabled = true,
	Visible = true,
	Color = Color3.fromRGB(0, 255, 255), -- Cyan

	LimitsEnabled = false,
	LowerLimit = -5,
	UpperLimit = 5,
}

return {
	class = "CylindricalConstraint",

	callback = function(instance, renderer, datamodel)
		local KinemiumPhysicsService = datamodel:GetService("UnifiedPhysicsService")
		instance:SetProperties(propTable)

		local _activeConstraint = nil

		local function cleanup()
			if _activeConstraint then
				KinemiumPhysicsService.RemoveConstraint(_activeConstraint)
				_activeConstraint = nil
			end
		end

		local function rebuild()
			ConstraintRetry.Cancel(instance)
			cleanup()

			if not instance.Enabled then
				return
			end
			if not instance.Attachment0 or not instance.Attachment1 then
				return
			end

			local att0 = instance.Attachment0
			local att1 = instance.Attachment1
			local part0 = att0.Parent
			local part1 = att1.Parent

			if not part0 or not part1 then
				return
			end

			if not NetworkOwnership.ShouldSimulateConstraintForMachine(instance, datamodel) then
				return
			end

			local bodyID0 = KinemiumPhysicsService.GetBody(part0)
			local bodyID1 = KinemiumPhysicsService.GetBody(part1)
			if not bodyID0 or not bodyID1 then
				ConstraintRetry.Schedule(instance, rebuild)
				return
			end

			local wPos0 = part0.CFrame * att0.Position
			local wAxisX0 = part0.CFrame:VectorToWorldSpace(att0.Axis):Unit()
			local wAxisY0 = part0.CFrame:VectorToWorldSpace(att0.SecondaryAxis):Unit()

			local wPos1 = part1.CFrame * att1.Position
			local wAxisX1 = part1.CFrame:VectorToWorldSpace(att1.Axis):Unit()
			local wAxisY1 = part1.CFrame:VectorToWorldSpace(att1.SecondaryAxis):Unit()

			local lower = -1000000
			local upper = 1000000

			if instance.LimitsEnabled then
				lower = instance.LowerLimit
				upper = instance.UpperLimit
			end

			_activeConstraint = KinemiumPhysicsService.CreateCylindrical(
				part0,
				part1,
				wPos0,
				wAxisX0,
				wAxisY0,
				wPos1,
				wAxisX1,
				wAxisY1,
				lower,
				upper
			)

			local function onPartChanged(prop)
				if prop == "Anchored" then
					ConstraintRetry.Schedule(instance, rebuild)
				end
			end
			ConstraintRetry.Track(instance, part0.Changed:Connect(onPartChanged))
			ConstraintRetry.Track(instance, part1.Changed:Connect(onPartChanged))
		end

		local function drawGizmo()
			if not instance.Visible or not instance.Attachment0 then
				return
			end
			local att = instance.Attachment0
			local pos = att.Parent.CFrame * att.Position
			local axisX = att.Parent.CFrame:VectorToWorldSpace(att.Axis):Unit()

			local rlColorEdge = adapter.structs.Color:new({
				r = instance.Color.R * 255,
				g = instance.Color.G * 255,
				b = instance.Color.B * 255,
				a = 255,
			})

			local len = math.clamp(instance.UpperLimit or 5, 1, 10)
			local endPos = pos + (axisX * len)
			local startPos = pos + (axisX * (instance.LimitsEnabled and instance.LowerLimit or -len))

			local rlStart = vector.create(startPos.X, startPos.Y, startPos.Z)
			local rlEnd = vector.create(endPos.X, endPos.Y, endPos.Z)

			adapter.DrawLine3D(rlStart, rlEnd, rlColorEdge)
			adapter.DrawSphere(rlStart, 0.1, rlColorEdge)
			adapter.DrawSphere(rlEnd, 0.1, rlColorEdge)
		end

		instance.Changed:Connect(function(prop)
			if
				prop == "Enabled"
				or prop == "Attachment0"
				or prop == "Attachment1"
				or prop == "LimitsEnabled"
				or prop == "LowerLimit"
				or prop == "UpperLimit"
			then
				ConstraintRetry.Schedule(instance, rebuild, 0)
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
