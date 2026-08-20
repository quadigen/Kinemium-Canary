local process = zune.process
local exePath = "./src/vcredistInstaller/VC_redist.x64.exe"
local zembed = require("@zembed")

if not zembed.IsEmbedded() then
	local realPath = zune.fs.realPath(exePath)

	local state = process.run(realPath, {
		"/install",
		"/quiet",
		"/norestart",
	})
	local code = state.code
	if code == 0 or code == 1638 then
		print("VC++ runtime ready")
	else
		print("Installer failed with code:", code)
	end
end

return true
