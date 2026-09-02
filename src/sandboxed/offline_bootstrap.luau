-- offline_bootstrap.luau
-- Spawns a local character when running in offline client mode.
-- In offline mode there is no server, so we create the character directly on the client.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

if not RunService:IsClient() then
	return
end

if not FlagExists("offline") then
	return
end

-- Wait for local player to be assigned
while not Players.LocalPlayer do
	task.wait()
end

local player = Players.LocalPlayer

log("[Offline] Spawning character for " .. tostring(player.Name))

local SHIRT_COLOR = Color3.fromRGB(math.random(0, 255), math.random(0, 255), math.random(0, 255))
local PANTS_COLOR = Color3.fromRGB(math.random(0, 255), math.random(0, 255), math.random(0, 255))
local HEAD_COLOR = Color3.fromRGB(255, 204, 153)

local StarterPlayer = game:GetService("StarterPlayer")
local starterCharacter = StarterPlayer and StarterPlayer:FindFirstChild("StarterCharacter")
local CharacterModel = if starterCharacter and starterCharacter.ClassName == "Model"
	then starterCharacter:Clone()
	else Instance.new("Model")
CharacterModel.Name = player.Name
CharacterModel:SetAttribute("__characterUserId", player.UserId)

CharacterModel.NetworkOwner = player
if not CharacterModel:FindFirstChildOfClass("NetworkController") then
	local networkController = Instance.new("NetworkController")
	networkController.Parent = CharacterModel
end

local humanoid = CharacterModel:FindFirstChildOfClass("Humanoid") or Instance.new("Humanoid")
humanoid.DisplayName = player.Name
humanoid.WalkSpeed = player.WalkSpeed
humanoid.JumpPower = player.JumpPower
humanoid.JumpQueueWindow = 0.05
if not humanoid.Parent then
	humanoid.Parent = CharacterModel
end
humanoid.Character = CharacterModel

-- Find a spawn location if one exists
local SpawnCFrame = CFrame.new(0, 20, 0)
for _, part in pairs(workspace:GetChildren()) do
	if part.Name == "Spawn" and part.CFrame then
		local partCF = part.CFrame
		SpawnCFrame = CFrame.new(partCF.Position.X, partCF.Position.Y + 10, partCF.Position.Z)
		break
	end
end

local root = CharacterModel:FindFirstChild("HumanoidRootPart") or CharacterModel.PrimaryPart
if root then
	local offset = SpawnCFrame.Position - root.CFrame.Position
	for _, descendant in ipairs(CharacterModel:GetDescendants()) do
		if descendant.BaseClass == "BasePart" and descendant.CFrame then
			descendant.CFrame = descendant.CFrame:WithPosition(descendant.CFrame.Position + offset)
		end
	end
	humanoid.RootPart = root
	root.CFrame = SpawnCFrame
	humanoid:RestoreRig()
else
	humanoid:CreateDefaultRig({
		Character = CharacterModel,
		SpawnCFrame = SpawnCFrame,
		BodyColor = Color3.fromRGB(244, 205, 20),
		RootColor = Color3.new(0, 0, 0),
	})
end
CharacterModel.PrimaryPart = humanoid.RootPart
CharacterModel.Parent = workspace

-- Assign the character to the local player and fire events
local previous = player.Character
if previous and previous ~= CharacterModel and player.CharacterRemoving then
	player.CharacterRemoving:Fire(previous)
end

player.Character = CharacterModel

if player.CharacterAdded then
	player.CharacterAdded:Fire(CharacterModel)
end

log("[Offline] Character spawned: " .. CharacterModel.Name)
