local enet = require("@enet_ffi")
local task = zune.task

assert(enet.lib.Kine_ENet_Initialize() ~= 0, "ENet failed to initialize")

local State = {
	servers = {},
	clients = {},
	eventLoopStarted = false,
}

function State.RegisterServer(server)
	State.servers[server] = true
	State.InitEventLoop()
end

function State.UnregisterServer(server)
	State.servers[server] = nil
end

function State.RegisterClient(client)
	State.clients[client] = true
	State.InitEventLoop()
end

function State.UnregisterClient(client)
	State.clients[client] = nil
end

function State.InitEventLoop()
	if State.eventLoopStarted then
		return
	end
	State.eventLoopStarted = true

	task.spawn(function()
		while true do
			for server in pairs(State.servers) do
				server:Poll()
			end
			for client in pairs(State.clients) do
				client:Poll()
			end
			task.wait(0.01)
		end
	end)
end

return State
