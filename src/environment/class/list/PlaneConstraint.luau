-- description: "Constrains an attachment to move within a two-dimensional plane."
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
	Color = Color3.fromRGB(0, 0, 255),
}

return {
	class = "PlaneConstraint",

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

			_activeConstraint =
				KinemiumPhysicsService.CreatePlane(part0, part1, wPos0, wAxisX0, wAxisY0, wPos1, wAxisX1, wAxisY1)

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
			local axisY = att.Parent.CFrame:VectorToWorldSpace(att.SecondaryAxis):Unit()

			local rlPos = vector.create(pos.X, pos.Y, pos.Z)
			local rlColorPlane = adapter.structs.Color:new({
				r = instance.Color.R * 255,
				g = instance.Color.G * 255,
				b = instance.Color.B * 255,
				a = 50,
			})
			local rlColorEdge = adapter.structs.Color:new({
				r = instance.Color.R * 255,
				g = instance.Color.G * 255,
				b = instance.Color.B * 255,
				a = 200,
			})

			local size = 2
			local p1 = vector.create(
				pos.X + axisX.X * size + axisY.X * size,
				pos.Y + axisX.Y * size + axisY.Y * size,
				pos.Z + axisX.Z * size + axisY.Z * size
			)
			local p2 = vector.create(
				pos.X - axisX.X * size + axisY.X * size,
				pos.Y - axisX.Y * size + axisY.Y * size,
				pos.Z - axisX.Z * size + axisY.Z * size
			)
			local p3 = vector.create(
				pos.X - axisX.X * size - axisY.X * size,
				pos.Y - axisX.Y * size - axisY.Y * size,
				pos.Z - axisX.Z * size - axisY.Z * size
			)
			local p4 = vector.create(
				pos.X + axisX.X * size - axisY.X * size,
				pos.Y + axisX.Y * size - axisY.Y * size,
				pos.Z + axisX.Z * size - axisY.Z * size
			)

			adapter.DrawTriangle3D(p1, p2, p3, rlColorPlane)
			adapter.DrawTriangle3D(p1, p3, p4, rlColorPlane)
			adapter.DrawLine3D(p1, p2, rlColorEdge)
			adapter.DrawLine3D(p2, p3, rlColorEdge)
			adapter.DrawLine3D(p3, p4, rlColorEdge)
			adapter.DrawLine3D(p4, p1, rlColorEdge)
		end

		instance.Changed:Connect(function(prop)
			if prop == "Enabled" or prop == "Attachment0" or prop == "Attachment1" then
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
