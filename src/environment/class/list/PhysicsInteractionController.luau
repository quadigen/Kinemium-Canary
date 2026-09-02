-- description: "Defines how a moving character pushes dynamic physics parts."
local Vector3 = require("@Vector3")
local NetworkOwnership = require("@NetworkOwnership")

return {
	class = "PhysicsInteractionController",
	callback = function(instance, _, datamodel)
		local lastPushAt = setmetatable({}, { __mode = "k" })

		instance:SetProperties({
			Name = "PhysicsInteractionController",
			Enabled = true,
			PushStrength = 0.05,
			MinimumImpulse = 20,
			MaximumImpulse = 180,
			VerticalLift = 0.08,
			PushInterval = 0.12,
			MinimumRelativeSpeed = 0.5,
		})

		function instance:Push(part, direction, speed, characterMass)
			if
				not self.Enabled
				or not part
				or part.Anchored ~= false
				or type(part.ApplyImpulse) ~= "function"
				or not direction
				or direction:Magnitude() <= 0.0001
			then
				return false
			end
			if not NetworkOwnership.ShouldSimulatePartForMachine(part, datamodel) then
				return false
			end

			local horizontal = Vector3.new(direction.X, 0, direction.Z)
			if horizontal:Magnitude() <= 0.0001 then
				return false
			end
			horizontal = horizontal:Unit()

			local objectVelocity = part.AssemblyLinearVelocity
			local forwardVelocity = 0
			if objectVelocity then
				forwardVelocity = objectVelocity.X * horizontal.X + objectVelocity.Z * horizontal.Z
			end
			local relativeSpeed = math.max((tonumber(speed) or 0) - forwardVelocity, 0)
			if relativeSpeed < math.max(tonumber(self.MinimumRelativeSpeed) or 0, 0) then
				return false
			end

			local now = os.clock()
			local interval = math.max(tonumber(self.PushInterval) or 0, 0)
			if now - (lastPushAt[part] or -math.huge) < interval then
				return false
			end

			local minimum = math.max(tonumber(self.MinimumImpulse) or 0, 0)
			local maximum = math.max(tonumber(self.MaximumImpulse) or minimum, minimum)
			local magnitude = math.clamp(
				relativeSpeed
					* math.max(tonumber(characterMass) or 0, 1)
					* math.max(tonumber(self.PushStrength) or 0, 0),
				minimum,
				maximum
			)
			local impulse = horizontal * magnitude
				+ Vector3.new(0, magnitude * math.max(tonumber(self.VerticalLift) or 0, 0), 0)
			local ok, applied = pcall(part.ApplyImpulse, part, impulse)
			if ok and applied ~= false then
				lastPushAt[part] = now
				return true
			end
			return false
		end

		return instance
	end,
}
