local Instance = require("@Instance")

local NetworkService = Instance.new("NetworkService")

local function inviteCode(address, port, token)
	return `kinecollab://{address}:{port}/{token}`
end

local function parseInvite(invite)
	if type(invite) == "table" then
		return invite.Address or invite.address, tonumber(invite.Port or invite.port), invite.Token or invite.token
	end
	if type(invite) ~= "string" then
		return nil
	end
	local address, port, token = invite:match("^kinecollab://([^:]+):(%d+)/([%w%-]+)$")
	return address, tonumber(port), token
end

NetworkService.InitRenderer = function(renderer, renderer_signal, datamodel)
	if IsHeadless == true and not FlagExists("server") and not FlagExists("client") then
		return
	end

	task.spawn(function()
		repeat
			task.wait()
		until datamodel.Loaded == true

		local replicator = datamodel:GetService("ReplicatorService")
		local studioServer = require("@KinemiumStudioServer")
		local studioClient = require("@KinemiumStudioClient")
		local collaborationMode = "Offline"
		local currentInvite = nil

		local function stopCollaboration()
			studioServer:Shutdown()
			studioClient:Shutdown()
			replicator:Stop()
			collaborationMode = "Offline"
			currentInvite = nil
			NetworkService.CollaborationMode = collaborationMode
			NetworkService.CurrentInvite = nil
			return true
		end

		NetworkService:SetProperties({
			CollaborationMode = collaborationMode,
			CurrentInvite = nil,
			GetStats = function()
				return replicator:GetStats()
			end,
			SendEvent = function(_, name, data, reliable)
				return replicator:SendEvent(name, data, reliable)
			end,
			OnEvent = function(_, name, callback)
				return replicator:OnEvent(name, callback)
			end,
		})

		function NetworkService:HostCollaboration(options)
			options = options or {}
			stopCollaboration()
			local bindAddress = options.BindAddress or "0.0.0.0"
			local inviteAddress = options.InviteAddress or "127.0.0.1"
			local port = tonumber(options.Port) or 1234
			local token = zune.crypto.uuid.v4() .. zune.crypto.uuid.v4()
			local active = studioServer:Init(bindAddress, port, datamodel, renderer, {
				token = token,
				readOnly = options.ReadOnly == true,
				name = options.Name or GetFlagValue("username") or "Host",
			})
			if not active then
				return nil, "failed to start collaboration server"
			end
			collaborationMode = "Hosting"
			currentInvite = {
				Address = inviteAddress,
				Port = port,
				Token = token,
				Code = inviteCode(inviteAddress, port, token),
			}
			self.CollaborationMode = collaborationMode
			self.CurrentInvite = currentInvite
			return table.clone(currentInvite)
		end

		function NetworkService:JoinCollaboration(invite, collaboratorName)
			local address, port, token = parseInvite(invite)
			if not address or not port or type(token) ~= "string" or #token < 16 then
				return nil, "invalid collaboration invitation"
			end
			stopCollaboration()
			local active = studioClient:Init(address, port, datamodel, renderer, {
				token = token,
				name = collaboratorName or GetFlagValue("username") or "Collaborator",
			})
			if not active then
				return nil, "failed to connect to collaboration host"
			end
			collaborationMode = "Collaborator"
			self.CollaborationMode = collaborationMode
			return active
		end

		function NetworkService:StopCollaboration()
			return stopCollaboration()
		end

		function NetworkService:GetCollaborators()
			local active = replicator:GetActiveReplicator()
			if not active then
				return {}
			end
			if active.GetCollaborators then
				return active:GetCollaborators()
			end
			local collaborators = {}
			for _, peer in pairs(active.world and active.world.peers or {}) do
				if peer.isStudio then
					table.insert(collaborators, peer.player)
				end
			end
			return collaborators
		end

		function NetworkService:SetCollaborativeProperty(instance, property, value)
			local active = replicator:GetActiveReplicator()
			if collaborationMode == "Hosting" then
				instance[property] = value
				return true
			end
			if active and active.SetStudioProperty then
				return active:SetStudioProperty(instance, property, value)
			end
			return false, "not in a collaboration session"
		end

		function NetworkService:DeleteCollaborativeInstance(instance, callback)
			local active = replicator:GetActiveReplicator()
			if collaborationMode == "Hosting" then
				instance:Destroy()
				return true
			end
			if active and active.DeleteStudioInstance then
				return active:DeleteStudioInstance(instance, callback)
			end
			return false, "not in a collaboration session"
		end

		-- Backwards-compatible entry points now use authenticated sessions.
		function NetworkService:InitStudioServer(address, port)
			return self:HostCollaboration({ BindAddress = address, InviteAddress = address, Port = port })
		end

		function NetworkService:InitStudioClient(address, port, token, name)
			return self:JoinCollaboration({ Address = address, Port = port, Token = token }, name)
		end

		if FlagExists("offline") then
			return
		end

		local isServer = FlagExists("server")
		local isClient = FlagExists("client")
		local isEditor = FlagExists("editor")
		local address = GetFlagValue("address") or (isServer and "0.0.0.0" or "127.0.0.1")
		local port = tonumber(GetFlagValue("port")) or 1234
		if isServer and isEditor then
			self:HostCollaboration({
				BindAddress = address,
				InviteAddress = GetFlagValue("invite-address") or "127.0.0.1",
				Port = port,
			})
		elseif isServer then
			require("@KinemiumServer"):Init(address, port, datamodel, renderer)
		elseif isClient then
			require("@KinemiumClient"):Init(address, port, datamodel, renderer)
		end
	end)
	return NetworkService
end

return NetworkService
