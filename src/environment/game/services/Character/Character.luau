-- description: "Owns character creation, templates, and player character lifecycle."
local Instance = require("@Instance")
local Registry = require("@InstanceRegistry")
local Enum = require("@EnumMap")
local Color3 = require("@Color3")
local CFrame = require("@CFrame")
local StarterCharacterResolver = require("@StarterCharacterResolver")

local Character = Instance.new("Character")
Character.CharacterTemplate = nil
Character.CharacterFactory = nil
Character.ControllerFactory = nil

Character.InitRenderer = function(renderer, _, game)
	local function newObject(className)
		local ok, object = pcall(Registry.new, className, renderer, game)
		return ok and object or Instance.new(className)
	end

	local function getSpawnCFrame(datamodel)
		local spawnCFrame = CFrame.new(0, 50, 0)
		for _, part in ipairs(datamodel.Workspace:GetChildren()) do
			if part.Name == "Spawn" and part.CFrame then
				local position = part.CFrame.Position
				return CFrame.new(position.X, position.Y + 10, position.Z)
			end
		end
		return spawnCFrame
	end

	local function assignCharacter(player, character)
		local previous = player.Character
		if previous and previous ~= character and player.CharacterRemoving then
			player.CharacterRemoving:Fire(previous)
		end
		player.Character = character
		if character and player.CharacterAdded then
			player.CharacterAdded:Fire(character)
		end
	end

	function Character:LoadPlayer(player, datamodel)
		datamodel = datamodel or game
		if not player then
			error("Character:LoadPlayer requires a Player", 2)
		end
		if not IsServer then
			return nil
		end

		local starterCharacter = StarterCharacterResolver.Resolve(datamodel)
		local character
		if type(self.CharacterFactory) == "function" then
			character = self.CharacterFactory(player, datamodel)
		elseif self.CharacterTemplate then
			character = self.CharacterTemplate:Clone()
		elseif starterCharacter then
			character = starterCharacter:Clone()
		else
			character = newObject("Model")
		end
		if not character then
			error("Character factory did not return a Model", 2)
		end

		character.Name = player.Name
		character:SetAttribute("__characterUserId", player.UserId)
		character.NetworkOwner = player
		character.NetworkOwnerType = Enum.MachineNetworkOwner.Client
		if not character:FindFirstChildOfClass("NetworkController") then
			local networkController = newObject("NetworkController")
			networkController.Parent = character
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			humanoid = newObject("Humanoid")
			humanoid.Parent = character
		end
		humanoid.DisplayName = player.Name
		humanoid.WalkSpeed = player.WalkSpeed
		humanoid.JumpPower = player.JumpPower
		humanoid.Character = character

		local spawnCFrame = getSpawnCFrame(datamodel)
		local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
		if root then
			local offset = spawnCFrame.Position - root.CFrame.Position
			for _, descendant in ipairs(character:GetDescendants()) do
				if descendant.BaseClass == "BasePart" and descendant.CFrame then
					descendant.CFrame = descendant.CFrame:WithPosition(descendant.CFrame.Position + offset)
				end
			end
			humanoid.RootPart = root
			root.CFrame = spawnCFrame
			humanoid:RestoreRig()
		else
			humanoid:CreateDefaultRig({
				Character = character,
				SpawnCFrame = spawnCFrame,
				BodyColor = Color3.fromRGB(244, 205, 20),
				RootColor = Color3.new(0, 0, 0),
			})
		end

		local controller = humanoid:GetController()
		if type(self.ControllerFactory) == "function" then
			local replacement = self.ControllerFactory(character, player, controller, datamodel)
			if replacement and replacement ~= controller then
				if controller then
					controller:Destroy()
				end
				replacement.Parent = character
				controller = replacement
			end
		end
		character.PrimaryPart = humanoid.RootPart
		character.Parent = datamodel.Workspace
		assignCharacter(player, character)
		return character
	end

	function Character:UnloadPlayer(player)
		if not player then
			return false
		end
		local character = player.Character
		if not character then
			return false
		end
		if player.CharacterRemoving then
			player.CharacterRemoving:Fire(character)
		end
		player.Character = nil
		character:Destroy()
		return true
	end

	Character.LoadCharacter = Character.LoadPlayer
	Character.UnloadCharacter = Character.UnloadPlayer
	Character.GetStarterCharacter = function(_, datamodel)
		return StarterCharacterResolver.Resolve(datamodel or game)
	end
	return Character
end

return Character
