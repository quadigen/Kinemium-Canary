local StarterCharacterResolver = {}

local function getStarterPlayer(datamodel)
	if not datamodel then
		return nil
	end
	local starterPlayer = datamodel.StarterPlayer
	if starterPlayer then
		return starterPlayer
	end
	if type(datamodel.GetService) == "function" then
		local ok, service = pcall(datamodel.GetService, datamodel, "StarterPlayer")
		if ok then
			return service
		end
	end
	return nil
end

function StarterCharacterResolver.Resolve(datamodel)
	local starterPlayer = getStarterPlayer(datamodel)
	if not starterPlayer then
		return nil
	end
	local candidate = if type(starterPlayer.FindFirstChild) == "function"
		then starterPlayer:FindFirstChild("StarterCharacter")
		else starterPlayer.StarterCharacter
	if candidate and candidate.ClassName == "Model" then
		return candidate
	end
	return nil
end

return StarterCharacterResolver
