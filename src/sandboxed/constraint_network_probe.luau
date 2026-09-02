if not FlagExists("constraint_probe") then
	return
end

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatorService = game:GetService("ReplicatorService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local spawnPartRemoteName = "ConstraintProbeSpawnPart"

local cases = {
	"BallSocketConstraint",
	"HingeConstraint",
	"PrismaticConstraint",
	"CylindricalConstraint",
	"UniversalConstraint",
	"PlaneConstraint",
	"RodConstraint",
	"RopeConstraint",
	"SpringConstraint",
	"TorsionSpringConstraint",
	"RigidConstraint",
	"WeldConstraint",
	"Weld",
}

local laneSpacing = 14
local caseDuration = 3
local buildingUnanchorDelay = 3
local function casePosition(index)
	return Vector3.new((index - (#cases + 1) / 2) * laneSpacing, 9, 0)
end

if RunService:IsServer() then
	local scene = Instance.new("Model")
	scene.Name = "ConstraintNetworkProbe"
	scene.Parent = workspace

	local spawnPartRemote = Instance.new("RemoteEvent")
	spawnPartRemote.Name = spawnPartRemoteName
	spawnPartRemote.Parent = ReplicatedStorage

	local spawnedPartCount = 0
	spawnPartRemote.OnServerEvent:Connect(function(player)
		spawnedPartCount += 1
		local part = Instance.new("Part")
		part.Name = `SpawnedServerPart{spawnedPartCount}`
		part.Size = Vector3.new(4, 4, 4)
		part.CFrame = CFrame.new(0, 10, 0)
		part.Anchored = false
		part.CanCollide = true
		part.Color = Color3.fromRGB(235, 165, 55)
		part.Parent = workspace
		print(`[ConstraintProbe][Server] {player.Name} spawned {part.Name}`)
	end)

	local ground = Instance.new("Part")
	ground.Name = "ConstraintProbeGround"
	ground.Size = Vector3.new(1000, 2, 1000)
	ground.CFrame = CFrame.new(0, -1, 10)
	ground.Anchored = true
	ground.Material = Enum.Material.Grass
	ground.Parent = scene

	local ownedParts = {}
	local function makePart(name, position, anchored, color)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = Vector3.new(3, 3, 3)
		part.CFrame = CFrame.new(position)
		part.Anchored = anchored
		part.CanCollide = true
		part.Color = color
		part.Parent = scene
		if not anchored then
			table.insert(ownedParts, part)
		end
		return part
	end

	local function makeAttachment(part, name, position)
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.Position = position
		attachment.Axis = Vector3.new(1, 0, 0)
		attachment.SecondaryAxis = Vector3.new(0, 1, 0)
		attachment.Parent = part
		return attachment
	end

	local function makeCase(className, index)
		local center = casePosition(index)
		local anchor = makePart(className .. "Anchor", center + Vector3.new(0, 3, 0), true, Color3.fromRGB(55, 80, 130))
		local moving = makePart(className .. "Body", center, false, Color3.fromRGB(230, 145, 45))
		local attachment0 = makeAttachment(anchor, className .. "Attachment0", Vector3.new(0, -1.5, 0))
		local attachment1 = makeAttachment(moving, className .. "Attachment1", Vector3.new(0, 1.5, 0))
		local constraint = Instance.new(className)
		constraint.Name = className .. "Probe"

		if className == "WeldConstraint" or className == "Weld" then
			constraint.Part0 = anchor
			constraint.Part1 = moving
		else
			constraint.Attachment0 = attachment0
			constraint.Attachment1 = attachment1
		end

		if className == "HingeConstraint" then
			constraint.ActuatorType = Enum.ActuatorType.Motor
			constraint.AngularVelocity = 1.5
			constraint.MotorMaxTorque = 5000
		elseif className == "PrismaticConstraint" then
			constraint.ActuatorType = Enum.ActuatorType.Servo
			constraint.LimitsEnabled = true
			constraint.LowerLimit = -2
			constraint.UpperLimit = 2
			constraint.TargetPosition = 1.5
		elseif className == "CylindricalConstraint" then
			constraint.LimitsEnabled = true
			constraint.LowerLimit = -2
			constraint.UpperLimit = 2
		elseif className == "UniversalConstraint" then
			constraint.LimitsEnabled = true
			constraint.MaxAngle = 35
		elseif className == "RodConstraint" then
			constraint.Length = 3
		elseif className == "RopeConstraint" then
			constraint.Length = 4
		elseif className == "SpringConstraint" then
			constraint.LimitsEnabled = true
			constraint.MinLength = 2
			constraint.MaxLength = 5
			constraint.Frequency = 2
			constraint.Damping = 0.35
		elseif className == "TorsionSpringConstraint" then
			constraint.Stiffness = 15
			constraint.Damping = 0.7
		end

		constraint.Parent = scene
		print(`[ConstraintProbe][Server] created {className}`)
	end

	for index, className in ipairs(cases) do
		makeCase(className, index)
	end

	-- A separate server-owned large scene remains at the end of the probe.
	-- Disabled weld records add realistic replication volume without preventing
	-- the blocks from independently collapsing.
	local building = Instance.new("Model")
	building.Name = "LargeReplicatedBuilding"
	building.Parent = scene
	local buildingParts = {}
	local core = nil
	for floor = 1, 8 do
		for x = -2, 2 do
			for z = -2, 2 do
				local block = Instance.new("Part")
				block.Name = `Floor{floor}_Block{x + 3}_{z + 3}`
				block.Size = Vector3.new(3.8, 2.8, 3.8)
				block.CFrame = CFrame.new(x * 4, floor * 3 + 1, 45 + z * 4)
				block.Anchored = true
				block.CanCollide = true
				block.Color = if (x + z + floor) % 2 == 0
					then Color3.fromRGB(105, 125, 155)
					else Color3.fromRGB(150, 170, 195)
				block.Parent = building
				core = core or block
				table.insert(buildingParts, block)
			end
		end
	end
	for index = 2, #buildingParts do
		local weld = Instance.new("WeldConstraint")
		weld.Name = `BuildingWeld{index}`
		weld.Part0 = core
		weld.Part1 = buildingParts[index]
		weld.Enabled = false
		weld.Visible = false
		weld.Parent = building
	end

	local buildingScheduled = false
	local function scheduleBuildingCollapse()
		if buildingScheduled then
			return
		end
		buildingScheduled = true
		-- Give the joining client a moment to receive the anchored building, then
		-- release it without applying any artificial impulses.
		task.delay(buildingUnanchorDelay, function()
			print(`[ConstraintProbe][Server] unanchoring building parts={#buildingParts}`)
			for _, part in ipairs(buildingParts) do
				part.Anchored = false
			end
			-- Keep the hidden construction welds disabled. Enabling all 199 as a
			-- single star around the core creates a pathological fixed island and
			-- defeats this test's purpose: a large burst of independently moving
			-- server-owned transforms.
			local startPosition = core.CFrame.Position
			task.spawn(function()
				for sample = 1, 5 do
					task.wait(1)
					print(
						`[ConstraintProbe][Server] building sample={sample} anchored={core.Anchored} displacement={(
							core.CFrame.Position - startPosition
						):Magnitude()}`
					)
				end
			end)
		end)
	end

	local function assignProbeOwnership(player)
		scheduleBuildingCollapse()
		task.delay(1, function()
			for _, part in ipairs(ownedParts) do
				ReplicatorService:AssignOwnership(part, player)
			end
			print(`[ConstraintProbe][Server] assigned {#ownedParts} bodies to {player.Name}`)
		end)
	end
	Players.PlayerAdded:Connect(assignProbeOwnership)
	for _, player in ipairs(Players:GetPlayers()) do
		assignProbeOwnership(player)
	end
else
	local PhysicsService = game:GetService("UnifiedPhysicsService")
	local spawnPartRemote = ReplicatedStorage:WaitForChild(spawnPartRemoteName, 10)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ConstraintProbeControls"
	screenGui.Parent = Players.LocalPlayer.PlayerGui

	local spawnPartButton = Instance.new("TextButton")
	spawnPartButton.Name = "Spawn Part"
	spawnPartButton.Text = "Spawn Part"
	spawnPartButton.Position = UDim2.fromOffset(16, 16)
	spawnPartButton.Size = UDim2.fromOffset(150, 44)
	spawnPartButton.BackgroundColor3 = Color3.fromRGB(45, 105, 185)
	spawnPartButton.BackgroundTransparency = 0.5
	spawnPartButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	spawnPartButton.TextSize = 20
	spawnPartButton.Parent = screenGui
	spawnPartButton.Activated:Connect(function()
		spawnPartRemote:FireServer()
	end)

	local backdrop = Instance.new("UIBackdrop")
	backdrop.Parent = spawnPartRemote

	local camera = workspace.Camera
	local function focusCamera(target, distance, height)
		if not camera then
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(target + Vector3.new(0, height or 5, distance or 14), target)
	end
	local forceProfiles = {
		BallSocketConstraint = {
			impulse = Vector3.new(0, 0, 130),
			torque = Vector3.new(700, 350, 0),
		},
		HingeConstraint = {
			impulse = Vector3.new(0, 0, 110),
			torque = Vector3.new(1200, 0, 0),
		},
		PrismaticConstraint = {
			impulse = Vector3.new(220, 0, 0),
			torque = Vector3.new(0, 700, 0),
		},
		CylindricalConstraint = {
			impulse = Vector3.new(180, 0, 0),
			torque = Vector3.new(1000, 0, 0),
		},
		UniversalConstraint = {
			impulse = Vector3.new(0, 0, 90),
			torque = Vector3.new(700, 700, 0),
		},
		PlaneConstraint = {
			impulse = Vector3.new(170, 60, 0),
			torque = Vector3.new(0, 0, 500),
		},
		RodConstraint = {
			impulse = Vector3.new(0, 0, 170),
			torque = Vector3.new(0, 500, 0),
		},
		RopeConstraint = {
			impulse = Vector3.new(0, -100, 150),
			torque = Vector3.new(0, 400, 0),
		},
		SpringConstraint = {
			impulse = Vector3.new(0, -190, 70),
			torque = Vector3.new(0, 250, 0),
		},
		TorsionSpringConstraint = {
			impulse = Vector3.new(0, 0, 70),
			torque = Vector3.new(1500, 0, 0),
		},
		RigidConstraint = {
			impulse = Vector3.new(0, 0, 220),
			torque = Vector3.new(900, 700, 500),
		},
		WeldConstraint = {
			impulse = Vector3.new(0, 0, 220),
			torque = Vector3.new(900, 700, 500),
		},
		Weld = {
			impulse = Vector3.new(0, 0, 220),
			torque = Vector3.new(900, 700, 500),
		},
	}

	local function disturbConstraint(scene, className)
		local startedAt = os.clock()
		local body = scene:FindFirstChild(className .. "Body")
		local profile = forceProfiles[className]
		if not body or not profile then
			warn(`[ConstraintProbe][Client] missing force target for {className}`)
			task.wait(caseDuration)
			return
		end
		local startingPosition = body.CFrame.Position
		local startingCFrame = body.CFrame
		local maxDisplacement = 0
		local maxAngularSpeed = 0

		-- The constraint bodies are client-owned. Give the reliable ownership
		-- grant a short moment to arrive before disturbing local Jolt state.
		local ownershipDeadline = os.clock() + 0.8
		while body.NetworkOwner ~= Players.LocalPlayer and os.clock() < ownershipDeadline do
			task.wait(0.05)
		end
		task.wait(0.2)

		for pulse = 1, 3 do
			local direction = if pulse % 2 == 1 then 1 else -1
			body:ApplyImpulse(profile.impulse * direction)
			if PhysicsService.ApplyTorque then
				PhysicsService.ApplyTorque(body, profile.torque * direction)
			end
			print(`[ConstraintProbe][Client] force pulse={pulse} constraint={className}`)
			task.wait(0.55)
			maxDisplacement = math.max(maxDisplacement, (body.CFrame.Position - startingPosition):Magnitude())
			maxAngularSpeed = math.max(maxAngularSpeed, body.AssemblyAngularVelocity:Magnitude())
		end
		print(
			`[ConstraintProbe][Client] result constraint={className} displacement={maxDisplacement} rotated={not body.CFrame:IsSameRotation(
				startingCFrame,
				1e-3
			)} angularSpeed={maxAngularSpeed} owner={body.NetworkOwner and body.NetworkOwner.Name or "server"}`
		)

		task.wait(math.max(0, caseDuration - (os.clock() - startedAt)))
	end

	task.spawn(function()
		local scene = workspace:FindFirstChild("ConstraintNetworkProbe")
		while not scene do
			task.wait(0.25)
			scene = workspace:FindFirstChild("ConstraintNetworkProbe")
		end
		for index, className in ipairs(cases) do
			print(`[ConstraintProbe][Client] viewing {className} index={index}`)
			focusCamera(casePosition(index), 14, 5)
			disturbConstraint(scene, className)
		end
		print("[ConstraintProbe][Client] viewing LargeReplicatedBuilding")
		focusCamera(Vector3.new(0, 13, 45), 48, 22)
		local building = scene:FindFirstChild("LargeReplicatedBuilding")
		local buildingCore = building and building:FindFirstChild("Floor1_Block1_1")
		local buildingStart = buildingCore and buildingCore.CFrame.Position
		while true do
			local stats = ReplicatorService:GetStats()
			local anchoredParts = 0
			if building then
				for _, part in ipairs(building:GetChildren()) do
					if part.BaseClass == "BasePart" and part.Anchored then
						anchoredParts += 1
					end
				end
			end
			local buildingDisplacement = if buildingCore and buildingStart
				then (buildingCore.CFrame.Position - buildingStart):Magnitude()
				else 0
			print(
				`[ConstraintProbe][Client] entities={stats.replicatedEntities or 0} buildingAnchored={anchoredParts} buildingDisplacement={buildingDisplacement} bytesReceived={stats.bytesReceived or 0} ownedSent={stats.ownedPhysicsPacketsSent or 0} ownedSkipped={stats.ownedPhysicsPacketsSkipped or 0} fullSnapshots={stats.fullSnapshotsReceived or 0} resyncs={stats.resyncs or 0} malformed={stats.malformedPackets or 0}`
			)
			task.wait(3)
		end
	end)
end
