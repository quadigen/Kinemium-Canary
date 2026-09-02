-- description: "High-level modular character controller."
local Vector3 = require("@Vector3")
local CFrame = require("@CFrame")
local signal = require("@Kinemium.signal")

local ZERO = Vector3.new(0, 0, 0)

local COMPONENTS = {
	{ "MovementController", "MovementController" },
	{ "StateMachine", "StateMachine" },
	{ "GroundDetector", "GroundDetector" },
	{ "CollisionController", "CollisionController" },
	{ "RotationController", "RotationController" },
	{ "JumpController", "JumpController" },
	{ "GravityController", "GravityController" },
	{ "PhysicsInteractionController", "PhysicsInteractionController" },
}

return {
	class = "CharacterController",
	callback = function(instance, renderer, datamodel)
		instance:SetProperties({
			Name = "CharacterController",
			Enabled = true,
			WalkSpeed = 16,
			JumpPower = 50,
			JumpHeight = 7.2,
			UseJumpPower = true,
			AutoRotate = true,
			TurnSpeed = 18,
			SprintMultiplier = 1.5,
			MoveDirection = ZERO,
			RootPart = nil,
			Character = nil,
			IsGrounded = false,
			GroundInstance = nil,
			JumpQueueWindow = 0.1,
			CoyoteTime = 0.1,
			GravityScale = 1,
			TerminalVelocity = 500,
		})
		instance.Jumping = signal.new()
		instance.StateChanged = signal.new()
		instance.MovementRequested = signal.new()
		instance.JumpRequested = signal.new()
		instance.SprintingChanged = signal.new()

		local components = {}
		local motor = nil
		local motorConfigurationKey = nil
		local animator = nil
		local stateConnection = nil

		local function newObject(className)
			-- Class modules are loaded by InstanceRegistry itself. Requiring the
			-- registry at module scope creates a circular require and stalls class
			-- discovery before CharacterController has finished loading.
			local Registry = require("@InstanceRegistry")
			local ok, object = pcall(Registry.new, className, renderer, datamodel)
			return ok and object or nil
		end

		local function ensureArchitecture()
			local character = instance.Parent
			if not character or character.ClassName ~= "Model" then
				return false
			end
			instance.Character = character
			if datamodel and rawget(datamodel, "_ApplyingReplicationHierarchy") then
				return false
			end
			instance.RootPart = instance.RootPart
				or character:FindFirstChild("HumanoidRootPart")
				or character.PrimaryPart

			for _, definition in ipairs(COMPONENTS) do
				local className, name = definition[1], definition[2]
				local component = instance:FindFirstChild(name) or instance:FindFirstChildOfClass(className)
				local createdComponent = false
				if not component then
					component = newObject(className)
					if component then
						createdComponent = true
						component.Name = name
						component.Parent = instance
					end
				end
				components[name] = component
				if createdComponent and name == "JumpController" then
					component.UseJumpPower = instance.UseJumpPower
					component.JumpPower = instance.JumpPower
					component.JumpHeight = instance.JumpHeight
					component.BufferTime = instance.JumpQueueWindow
					component.CoyoteTime = instance.CoyoteTime
				elseif createdComponent and name == "GravityController" then
					component.GravityScale = instance.GravityScale
					component.TerminalVelocity = instance.TerminalVelocity
				end
			end

			motor = character:FindFirstChildOfClass("CharacterMotor")
			if not motor then
				motor = newObject("CharacterMotor")
				if motor then
					motor.Parent = character
				end
			end
			if motor then
				motor.RootPart = instance.RootPart
				motor.InteractionController = components.PhysicsInteractionController
				local collision = components.CollisionController
				local configurationKey = collision
						and table.concat({
							tostring(collision.Size),
							tostring(collision.Mass),
							tostring(collision.MaxSlopeAngle),
							tostring(collision.CollisionGroup),
							tostring(collision.Padding),
						}, ":")
					or "default"
				if configurationKey ~= motorConfigurationKey then
					motor:Configure(collision and {
						Size = collision.Size,
						Mass = collision.Mass,
						MaxSlopeAngle = collision.MaxSlopeAngle,
						CollisionGroup = collision.CollisionGroup,
						Padding = collision.Padding,
					} or nil)
					motorConfigurationKey = configurationKey
				end
			end

			animator = character:FindFirstChildOfClass("CharacterAnimator")
			if not animator then
				animator = newObject("CharacterAnimator")
				if animator then
					animator.Parent = character
				end
			end
			if animator then
				animator.Controller = instance
				animator.Animator = character:FindFirstChildWhichIsA("Animator", true)
			end

			local stateMachine = components.StateMachine
			if stateMachine and not stateConnection then
				stateConnection = stateMachine.StateChanged:Connect(function(nextState, previousState)
					instance.StateChanged:Fire(nextState, previousState)
				end)
			end
			return motor ~= nil and instance.RootPart ~= nil
		end

		function instance:Move(direction)
			ensureArchitecture()
			components.MovementController:SetMoveDirection(direction or ZERO)
			self.MoveDirection = components.MovementController.MoveDirection
			self.MovementRequested:Fire(self.MoveDirection)
		end

		function instance:MoveRelative(direction, basis)
			direction = direction or ZERO
			if basis and basis.VectorToWorldSpace then
				direction = basis:VectorToWorldSpace(direction)
			elseif basis then
				direction = basis * direction
			end
			self:Move(direction)
		end

		function instance:Jump()
			ensureArchitecture()
			local accepted = components.JumpController and components.JumpController:Request()
			if not accepted then
				return false
			end
			self.JumpRequested:Fire()
			return true
		end

		function instance:RequestJump()
			return self:Jump()
		end

		function instance:SetSprinting(sprinting)
			ensureArchitecture()
			local enabled = sprinting == true
			if components.MovementController.Sprinting ~= enabled then
				components.MovementController.Sprinting = enabled
				self.SprintingChanged:Fire(enabled)
			end
		end

		function instance:Face(direction)
			ensureArchitecture()
			components.RotationController:Face(direction)
		end

		function instance:ClearFacingDirection()
			ensureArchitecture()
			components.RotationController:ClearFacingDirection()
		end

		function instance:GetState()
			ensureArchitecture()
			return components.StateMachine and components.StateMachine:GetState() or "Freefall"
		end

		function instance:ChangeState(nextState)
			ensureArchitecture()
			return components.StateMachine and components.StateMachine:ChangeState(nextState) or false
		end

		function instance:GetMotor()
			ensureArchitecture()
			return motor
		end

		function instance:GetComponent(name)
			ensureArchitecture()
			return components[name]
		end

		function instance:Step(dt)
			if not self.Enabled or not ensureArchitecture() then
				return nil
			end
			if components.StateMachine:GetState() == "Dead" then
				components.MovementController:SetMoveDirection(ZERO)
				return motor:Step(ZERO, ZERO, dt)
			end
			dt = math.max(tonumber(dt) or 0, 0)
			local movement = components.MovementController
			movement.WalkSpeed = self.WalkSpeed
			movement.SprintMultiplier = self.SprintMultiplier
			components.RotationController.AutoRotate = self.AutoRotate
			components.RotationController.TurnSpeed = self.TurnSpeed
			local jump = components.JumpController
			local gravity = components.GravityController

			-- Workspace stores gravity as a signed Y acceleration (currently -9.81),
			-- while GravityController exposes a consistently downward vector.
			local configuredGravity = datamodel and datamodel.Workspace and datamodel.Workspace.Gravity or -196.2
			local gravityAcceleration = gravity:GetAcceleration(configuredGravity)
			local vertical, didJump = jump:Resolve(
				motor.Velocity and motor.Velocity.Y or 0,
				math.abs(gravityAcceleration.Y),
				motor.IsGrounded
			)
			vertical = gravity:ClampVerticalVelocity(vertical)
			if didJump then
				self.Jumping:Fire(true)
			end

			local velocity = movement:GetTargetVelocity(vertical)
			local result = motor:Step(velocity, gravityAcceleration, dt)
			components.GroundDetector:Update(result and result.isGrounded, result and result.groundInstance)
			self.IsGrounded = components.GroundDetector.IsGrounded
			self.GroundInstance = components.GroundDetector.GroundInstance

			local speed = movement.MoveDirection:Magnitude()
			if didJump then
				components.StateMachine:ChangeState("Jumping")
			elseif not self.IsGrounded then
				components.StateMachine:ChangeState("Freefall")
			elseif speed > 0.0001 then
				components.StateMachine:ChangeState("Running")
			else
				components.StateMachine:ChangeState("Idle")
			end
			components.RotationController:Step(self.RootPart, movement.MoveDirection, dt)
			if animator then
				animator:Step(dt)
			end
			return result
		end

		instance:_SetPropertyHandler("Parent", ensureArchitecture)
		instance:_SetPropertyHandler("RootPart", function(root)
			if motor then
				motor.RootPart = root
			end
		end)
		local function bindComponentProperty(property, componentName, componentProperty)
			instance:_SetPropertyHandler(property, function(value)
				local component = components[componentName]
				if component then
					component[componentProperty] = value
				end
			end)
		end
		for property, componentProperty in pairs({
			UseJumpPower = "UseJumpPower",
			JumpPower = "JumpPower",
			JumpHeight = "JumpHeight",
			JumpQueueWindow = "BufferTime",
			CoyoteTime = "CoyoteTime",
		}) do
			bindComponentProperty(property, "JumpController", componentProperty)
		end
		for property, componentProperty in pairs({
			GravityScale = "GravityScale",
			TerminalVelocity = "TerminalVelocity",
		}) do
			bindComponentProperty(property, "GravityController", componentProperty)
		end

		local runService = datamodel and datamodel:GetService("RunService") or nil
		if runService and runService.BindToSimulation then
			runService:BindToSimulation(function(dt)
				if instance.Parent then
					instance:Step(dt)
				end
			end)
		end

		return instance
	end,
}
