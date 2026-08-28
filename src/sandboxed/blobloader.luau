local BlobLoader = game:GetService("BlobLoader")
local assetsaver = require("@assetsaver")

local flagValue = GetFlagValue("blob")

local path = "./exported/obj.kine"

local function loadBlob(read, source)
	if BlobLoader.MarkBlobLoadingPending then
		BlobLoader:MarkBlobLoadingPending()
	end

	local loadOk, loadErr = pcall(BlobLoader.LoadFileAsGame, read)
	if not loadOk then
		warn("Failed to load blob from " .. source .. ": " .. tostring(loadErr))
	end
	game:PrintTree()
end

local embeddedGame = if not flagValue and IsExecutable then EmbeddedGameData else nil

if embeddedGame then
	task.spawn(function()
		print("Loading embedded game")
		loadBlob(embeddedGame, "executable")
	end)
elseif not flagValue and not IsClient and not IsServer then
	task.spawn(function()
		print("Checking if path exists")
		local ok, read = pcall(Filesystem.readFile, path, true)
		if not ok or not read then
			return
		end
		loadBlob(read, path)
	end)
end

if flagValue then
	print("Loading blob from", flagValue)

	task.spawn(function()
		local ok, read = pcall(Filesystem.readFile, flagValue, true)
		if not ok or not read then
			warn("Failed to read blob file: " .. tostring(read or flagValue))
			return
		end
		loadBlob(read, flagValue)
	end)
end

task.wait(2)

if IsServer or IsClient then
	assetsaver:ResolveGame(game)
end
