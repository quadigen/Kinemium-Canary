-- description: "A client-visible world prompt whose validated activation is signalled on the server."
local Enum = require("@EnumMap")
local Vector2 = require("@Vector2")
local Vector3 = require("@Vector3")
local UDim2 = require("@UDim2")
local Color3 = require("@Color3")
local signal = require("@Kinemium.signal")

local EVENT_CHANNEL = "__kinemium_proximity_prompt"
local managers = setmetatable({}, { __mode = "k" })

local propTable = {
	ActionText = "Interact",
	AutoLocalize = true,
	ClickablePrompt = true,
	Enabled = true,
	Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton,
	GamepadKeyCode = Enum.KeyCode.ButtonX,
	HoldDuration = 0,
	KeyboardKeyCode = Enum.KeyCode.E,
	MaxActivationDistance = 10,
	MaxIndicatorDistance = 10,
	ObjectText = "",
	RequiresLineOfSight = true,
	RootLocalizationTable = nil,
	Style = Enum.ProximityPromptStyle.Default,
	UIOffset = Vector2.new(0, 0),
}

local function getAdornee(prompt)
	local parent = prompt.Parent
	if parent and (parent.CFrame or parent.WorldPosition or parent.Position) then
		return parent
	end
	return parent and parent.Parent or nil
end

local function getPosition(object)
	if not object then return nil end
	if object.CFrame then return object.CFrame.Position end
	return object.WorldPosition or object.Position
end

local function getPlayerRoot(player)
	local character = player and player.Character
	return character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart) or nil
end

local function sameKey(left, right)
	if left == right then return true end
	return type(left) == "table" and type(right) == "table" and left.Value == right.Value
end

local function managerFor(datamodel)
	local manager = managers[datamodel]
	if manager then return manager end
	manager = { prompts = setmetatable({}, { __mode = "k" }), holdToken = 0, held = nil }
	managers[datamodel] = manager

	local replicator = datamodel and datamodel:GetService("ReplicatorService")
	if IsServer == true and replicator then
		replicator:OnEvent(EVENT_CHANNEL, function(player, payload)
			if type(payload) ~= "table" or type(payload.promptId) ~= "number" then return end
			local active = replicator:GetActiveReplicator()
			local prompt = active and active.world and active.world:GetInstance(payload.promptId) or nil
			if not prompt or prompt.ClassName ~= "ProximityPrompt" or not prompt.Enabled then return end

			local rootPosition = getPosition(getPlayerRoot(player))
			local promptPosition = getPosition(getAdornee(prompt))
			local maxDistance = math.max(0, tonumber(prompt.MaxActivationDistance) or 0)
			if not rootPosition or not promptPosition or (rootPosition - promptPosition):Magnitude() > maxDistance + 0.5 then
				return
			end
			prompt.Triggered:Fire(player)
		end)
	end

	if IsServer ~= true and datamodel then
		local input = datamodel:GetService("UserInputService")
		if input and input.InputBegan then
			manager.inputBegan = input.InputBegan:Connect(function(inputObject, processed)
				if processed then return end
				local closestPrompt, closestDistance
				for prompt, record in pairs(manager.prompts) do
					if record.visible and sameKey(inputObject.KeyCode, prompt.KeyboardKeyCode)
						and (not closestDistance or record.distance < closestDistance)
					then
						closestPrompt, closestDistance = prompt, record.distance
					end
				end
				if closestPrompt then closestPrompt:InputHoldBegin() end
			end)
			manager.inputEnded = input.InputEnded:Connect(function(inputObject)
				if manager.held and sameKey(inputObject.KeyCode, manager.held.KeyboardKeyCode) then
					manager.held:InputHoldEnd()
				end
			end)
		end
	end
	return manager
end

return {
	class = "ProximityPrompt",
	callback = function(instance, renderer, datamodel)
		instance:SetProperties(propTable)
		instance.Triggered = signal.new()
		instance.TriggerEnded = signal.new()
		instance.PromptButtonHoldBegan = signal.new()
		instance.PromptButtonHoldEnded = signal.new()
		instance.PromptHidden = signal.new()
		instance.PromptShown = signal.new()

		local manager = managerFor(datamodel)
		local record = { visible = false, distance = math.huge, billboard = nil }
		manager.prompts[instance] = record
		local connections = {}

		local function createPromptGui()
			if _G.IsHeadless or not renderer or not renderer.Window or record.billboard then return end
			local Registry = require("@InstanceRegistry")
			local billboard = Registry.new("BillboardGui", renderer, datamodel)
			billboard.Name = "ProximityPromptBillboard"
			billboard.Size = UDim2.new(0, 230, 0, 74)
			billboard.PixelsPerStud = 70
			billboard.AlwaysOnTop = true
			billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.25, 0)
			billboard.MaxDistance = instance.MaxIndicatorDistance
			billboard.Adornee = getAdornee(instance)
			billboard.Enabled = false
			billboard.Parent = instance

			local background = Registry.new("Frame", renderer, datamodel)
			background.Name = "Background"
			background.Size = UDim2.new(1, 0, 1, 0)
			background.BackgroundColor3 = Color3.fromRGB(22, 24, 29)
			background.BackgroundTransparency = 0.12
			background.Parent = billboard

			local corner = Registry.new("UICorner", renderer, datamodel)
			corner.CornerRadius = require("@UDim").new(0, 14)
			corner.Parent = background

			local keyLabel = Registry.new("TextLabel", renderer, datamodel)
			keyLabel.Name = "Key"
			keyLabel.Position = UDim2.new(0, 10, 0, 10)
			keyLabel.Size = UDim2.new(0, 48, 0, 48)
			keyLabel.BackgroundColor3 = Color3.fromRGB(244, 205, 20)
			keyLabel.BackgroundTransparency = 0
			keyLabel.TextColor3 = Color3.fromRGB(30, 28, 18)
			keyLabel.TextSize = 22
			keyLabel.Text = instance.KeyboardKeyCode and instance.KeyboardKeyCode.Name or "E"
			keyLabel.Parent = background

			local keyCorner = Registry.new("UICorner", renderer, datamodel)
			keyCorner.CornerRadius = require("@UDim").new(0, 10)
			keyCorner.Parent = keyLabel

			local actionLabel = Registry.new("TextLabel", renderer, datamodel)
			actionLabel.Name = "Action"
			actionLabel.Position = UDim2.new(0, 70, 0, 7)
			actionLabel.Size = UDim2.new(1, -80, 0, 34)
			actionLabel.BackgroundTransparency = 1
			actionLabel.TextColor3 = Color3.new(1, 1, 1)
			actionLabel.TextSize = 20
			actionLabel.TextXAlignment = Enum.TextXAlignment.Left
			actionLabel.Text = instance.ActionText
			actionLabel.Parent = background

			local objectLabel = Registry.new("TextLabel", renderer, datamodel)
			objectLabel.Name = "Object"
			objectLabel.Position = UDim2.new(0, 70, 0, 38)
			objectLabel.Size = UDim2.new(1, -80, 0, 24)
			objectLabel.BackgroundTransparency = 1
			objectLabel.TextColor3 = Color3.fromRGB(180, 184, 194)
			objectLabel.TextSize = 14
			objectLabel.TextXAlignment = Enum.TextXAlignment.Left
			objectLabel.Text = instance.ObjectText
			objectLabel.Parent = background

			record.billboard, record.keyLabel, record.actionLabel, record.objectLabel = billboard, keyLabel, actionLabel, objectLabel
		end

		local function refreshGui()
			createPromptGui()
			if not record.billboard then return end
			record.billboard.Adornee = getAdornee(instance)
			record.billboard.MaxDistance = instance.MaxIndicatorDistance
			record.billboard.Enabled = record.visible
			record.keyLabel.Text = instance.KeyboardKeyCode and instance.KeyboardKeyCode.Name or "E"
			record.actionLabel.Text = instance.ActionText
			record.objectLabel.Text = instance.ObjectText
		end

		local function updateVisibility()
			if IsServer == true then return end
			local players = datamodel and datamodel:GetService("Players")
			local rootPosition = getPosition(getPlayerRoot(players and players.LocalPlayer))
			local promptPosition = getPosition(getAdornee(instance))
			record.distance = if rootPosition and promptPosition then (rootPosition - promptPosition):Magnitude() else math.huge
			local maxDistance = math.max(0, tonumber(instance.MaxIndicatorDistance) or tonumber(instance.MaxActivationDistance) or 0)
			local visible = instance.Enabled and record.distance <= maxDistance
			if visible ~= record.visible then
				record.visible = visible
				if visible then instance.PromptShown:Fire() else instance.PromptHidden:Fire() end
			end
			refreshGui()
		end

		function instance:Trigger()
			if not self.Enabled then return false end
			if IsServer == true then
				self.Triggered:Fire(nil)
				return true
			end
			updateVisibility()
			if record.distance > math.max(0, tonumber(self.MaxActivationDistance) or 0) then return false end
			local players = datamodel and datamodel:GetService("Players")
			self.Triggered:Fire(players and players.LocalPlayer or nil)
			local replicator = datamodel and datamodel:GetService("ReplicatorService")
			if replicator and type(self.NetworkId) == "number" then
				replicator:SendEvent(EVENT_CHANNEL, { promptId = self.NetworkId }, true)
			end
			self.TriggerEnded:Fire(players and players.LocalPlayer or nil)
			return true
		end

		function instance:InputHoldBegin()
			if not self.Enabled then return false end
			manager.holdToken += 1
			local token = manager.holdToken
			manager.held = self
			self.PromptButtonHoldBegan:Fire()
			local duration = math.max(0, tonumber(self.HoldDuration) or 0)
			if duration == 0 then return self:Trigger() end
			task.delay(duration, function()
				if manager.held == self and manager.holdToken == token then self:Trigger() end
			end)
			return true
		end

		function instance:InputHoldEnd()
			if manager.held ~= self then return false end
			manager.holdToken += 1
			manager.held = nil
			self.PromptButtonHoldEnded:Fire()
			return true
		end

		if datamodel and IsServer ~= true then
			local runService = datamodel:GetService("RunService")
			if runService and runService.RenderStepped then
				table.insert(connections, runService.RenderStepped:Connect(updateVisibility))
			end
		end
		table.insert(connections, instance.Changed:Connect(function(property)
			if property == "Parent" or property == "ActionText" or property == "ObjectText"
				or property == "KeyboardKeyCode" or property == "Enabled" or property == "MaxIndicatorDistance"
			then
				updateVisibility()
			end
		end))

		instance.Destroying:Connect(function()
			manager.prompts[instance] = nil
			if manager.held == instance then manager.held = nil manager.holdToken += 1 end
			for _, connection in ipairs(connections) do connection:Disconnect() end
			for _, event in ipairs({ instance.Triggered, instance.TriggerEnded, instance.PromptButtonHoldBegan, instance.PromptButtonHoldEnded, instance.PromptHidden, instance.PromptShown }) do event:Destroy() end
		end)
		return instance
	end,
	inherit = function(tble)
		for property, value in pairs(propTable) do tble[property] = value end
	end,
}
