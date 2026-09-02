-- Opt-in diagnostics for a manual one-server/two-client character test.
if not FlagExists("character_probe") then
	return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatorService = game:GetService("ReplicatorService")

task.spawn(function()
	while true do
		task.wait(2)
		local role = if RunService:IsServer() then "Server" else "Client"
		local playerList = Players:GetPlayers()
		print(`[CharacterProbe][{role}] players={#playerList}`)
		for _, player in ipairs(playerList) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = humanoid and humanoid.RootPart
			local partCount = 0
			local nameCounts = {}
			for _, child in ipairs(character and character:GetChildren() or {}) do
				if child.BaseClass == "BasePart" then
					partCount += 1
					nameCounts[child.Name] = (nameCounts[child.Name] or 0) + 1
				end
			end
			local duplicates = {}
			for name, count in pairs(nameCounts) do
				if count > 1 then
					duplicates[#duplicates + 1] = `{name}x{count}`
				end
			end
			print(
				`[CharacterProbe][{role}] {player.Name} userId={player.UserId} character={character and character.Name or "nil"} root={root and root.Name or "nil"} parts={partCount} duplicates={#duplicates > 0 and table.concat(duplicates, ",") or "none"}`
			)
		end
		local stats = ReplicatorService:GetStats()
		print(
			`[CharacterProbe][{role}] entities={stats.replicatedEntities or 0} inputsSent={stats.inputsSent or 0} inputsReceived={stats.inputsReceived or 0} reconciliations={stats.reconciliations or 0}`
		)
	end
end)
