local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")

repeat
	task.wait()
until ScriptContext.RunClientScripts and ScriptContext.RunServerScripts

if RunService:IsClient() then
	-- `cli run` uses one offline process as both the local server and client.
	-- Start authoritative scripts first so the world exists before client scripts run.
	if FlagExists("offline") then
		ScriptContext.RunServerScripts()
	end
	ScriptContext.RunClientScripts()
elseif RunService:IsServer() then
	ScriptContext.RunServerScripts()
end
