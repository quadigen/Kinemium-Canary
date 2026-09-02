-- description: "Low-level character motion adapter for UnifiedPhysicsService."
local Vector3 = require("@Vector3")
local CFrame = require("@CFrame")

local ZERO = Vector3.new(0, 0, 0)

return {
	class = "CharacterMotor",
	callback = function(instance, _, datamodel)
		instance:SetProperties({
			Name = "CharacterMotor",
			Enabled = true,
			RootPart = nil,
			Velocity = ZERO,
			IsGrounded = false,
			GroundInstance = nil,
			InteractionController = nil,
		})

		local physics = datamodel and datamodel:GetService("UnifiedPhysicsService") or nil
		local nativeController = nil
		local controllerSettings = nil
		local groundRayParams = {
			FilterDescendantsInstances = {},
			RespectCanCollide = true,
			CollisionGroup = "Default",
		}

		local function moveCharacterTo(position)
			local root = instance.RootPart
			if not root or not position then
				return
			end
			local offset = position - root.CFrame.Position
			root.CFrame = root.CFrame:WithPosition(position)
			local character = instance.Parent
			if character and offset:Magnitude() > 0 then
				for _, descendant in ipairs(character:GetDescendants()) do
					if descendant ~= root and descendant.BaseClass == "BasePart" and descendant.CFrame then
						descendant.CFrame = descendant.CFrame:WithPosition(descendant.CFrame.Position + offset)
					end
				end
			end
		end

		local function destroyNative()
			if nativeController and physics and physics.DestroyCharacterController then
				physics.DestroyCharacterController(nativeController)
			elseif nativeController and physics and physics.DestroyHumanoidController then
				physics.DestroyHumanoidController(nativeController)
			end
			nativeController = nil
		end

		function instance:Configure(settings)
			controllerSettings = settings or {}
			destroyNative()
		end

		function instance:Reset(position)
			destroyNative()
			if self.RootPart and position then
				moveCharacterTo(position)
			end
			self.Velocity = ZERO
			self.IsGrounded = false
			self.GroundInstance = nil
		end

		local function ensureNative()
			if nativeController or not physics or not instance.RootPart then
				return nativeController
			end
			local create = physics.CreateCharacterController or physics.CreateHumanoidController
			if not create then
				return nil
			end
			local settings = table.clone(controllerSettings or {})
			settings.Position = instance.RootPart.CFrame.Position
			nativeController = create(settings)
			return nativeController
		end

		function instance:Step(velocity, gravity, dt)
			if not self.Enabled or not self.RootPart then
				return nil
			end
			velocity = velocity or ZERO
			gravity = gravity or Vector3.new(0, -196.2, 0)
			dt = math.max(tonumber(dt) or 0, 0)

			local native = ensureNative()
			local step = physics and (physics.StepCharacterController or physics.StepHumanoidController)
			local result = native and step and step(native, velocity, gravity, dt) or nil
			if result then
				self.Velocity = result.velocity or velocity
				self.IsGrounded = result.isGrounded == true
				self.GroundInstance = result.groundInstance
				if result.position then
					moveCharacterTo(result.position)
				end
			else
				local currentPosition = self.RootPart.CFrame.Position
				local nextVelocity = velocity + gravity * dt
				local nextPosition = currentPosition + nextVelocity * dt
				local grounded = false
				local groundInstance = nil
				local workspace = datamodel and datamodel.Workspace
				local settings = controllerSettings or {}
				local size = settings.Size or Vector3.new(2, 6, 2)
				local padding = tonumber(settings.Padding) or 0.02
				local halfHeight = math.max(tonumber(size.Y) or 6, 0) * 0.5
				groundRayParams.FilterDescendantsInstances = instance.Parent and { instance.Parent } or {}

				local horizontalTravel =
					Vector3.new(nextPosition.X - currentPosition.X, 0, nextPosition.Z - currentPosition.Z)
				if horizontalTravel:Magnitude() > 0.0001 and workspace and workspace.Raycast then
					local direction = horizontalTravel:Unit()
					local radius = math.max(tonumber(size.X) or 2, tonumber(size.Z) or 2) * 0.5
					local probeDistance = radius + horizontalTravel:Magnitude() + padding
					local closestHit = nil
					local pushed = {}
					for _, heightOffset in ipairs({ -halfHeight * 0.6, 0, halfHeight * 0.55 }) do
						local probeOrigin = currentPosition + Vector3.new(0, heightOffset, 0)
						local hit = workspace:Raycast(
							probeOrigin,
							direction * probeDistance,
							groundRayParams
						)
						if hit and (not closestHit or (tonumber(hit.Distance) or math.huge) < (tonumber(closestHit.Distance) or math.huge)) then
							closestHit = hit
						end
						local hitPart = hit and hit.Instance
						if hitPart and hitPart.Anchored == false and not pushed[hitPart] then
							pushed[hitPart] = true
							local characterMass = math.max(tonumber(settings.Mass) or 80, 1)
							local interaction = instance.InteractionController
							if interaction and interaction.Push then
								interaction:Push(hitPart, direction, velocity:Magnitude(), characterMass)
							elseif hitPart.ApplyImpulse then
								local pushMagnitude =
									math.clamp(velocity:Magnitude() * characterMass * 0.18, 20, 180)
								pcall(
									hitPart.ApplyImpulse,
									hitPart,
									direction * pushMagnitude + Vector3.new(0, pushMagnitude * 0.08, 0)
								)
							end
						end
					end
					if closestHit and closestHit.Instance then
						local hit = closestHit
						local allowedTravel = math.max((tonumber(hit.Distance) or 0) - radius - padding, 0)
						if allowedTravel < horizontalTravel:Magnitude() then
							local horizontalPosition = currentPosition + direction * allowedTravel
							nextPosition = Vector3.new(horizontalPosition.X, nextPosition.Y, horizontalPosition.Z)
							nextVelocity = Vector3.new(0, nextVelocity.Y, 0)
						end
					end
				end

				if nextVelocity.Y <= 0 and workspace and workspace.Raycast then
					local fallDistance = math.max(currentPosition.Y - nextPosition.Y, 0)
					local groundOrigin = Vector3.new(nextPosition.X, currentPosition.Y, nextPosition.Z)
					local hit = workspace:Raycast(
						groundOrigin,
						Vector3.new(0, -(halfHeight + fallDistance + padding + 0.1), 0),
						groundRayParams
					)
					if hit and hit.Position then
						local supportedY = hit.Position.Y + halfHeight + padding
						if nextPosition.Y <= supportedY then
							nextPosition = Vector3.new(nextPosition.X, supportedY, nextPosition.Z)
							nextVelocity = Vector3.new(nextVelocity.X, 0, nextVelocity.Z)
							grounded = true
							groundInstance = hit.Instance
						end
					end
				end
				self.Velocity = nextVelocity
				moveCharacterTo(nextPosition)
				self.IsGrounded = grounded
				self.GroundInstance = groundInstance
			end
			self.RootPart.AssemblyLinearVelocity = self.Velocity
			self.RootPart.Velocity = self.Velocity
			return {
				position = self.RootPart.CFrame.Position,
				velocity = self.Velocity,
				isGrounded = self.IsGrounded,
				groundInstance = self.GroundInstance,
			}
		end

		instance.Destroying:Connect(destroyNative)
		return instance
	end,
}
