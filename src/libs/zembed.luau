local fs = zune.fs
local lib = {}

local function normalizePath(path: string): string
	return (path:gsub([[\]], "/"))
end

local function stripCurrentPrefix(path: string): string
	return normalizePath(path):gsub("^%./", "")
end

local function isPathUnder(path: string, base: string): boolean
	local normalizedPath = stripCurrentPrefix(path)
	local normalizedBase = stripCurrentPrefix(base):gsub("/+$", "")

	return normalizedPath == normalizedBase or normalizedPath:sub(1, #normalizedBase + 1) == normalizedBase .. "/"
end

local function assetToSourcePath(path: string): string?
	if type(path) ~= "string" then
		return nil
	end

	local normalized = normalizePath(path)
	local assetPath = normalized:match("^kineasset://(.+)$")

	if not assetPath then
		assetPath = normalized:match("^%.?/src/assets/(.+)$")
	end

	if not assetPath then
		assetPath = normalized:match("^%.?/assets/(.+)$")
	end

	if assetPath then
		return "src/assets/" .. assetPath
	end

	return nil
end

local function getEmbeddedUnder(entries: { string }, base: string): { string }
	local results = {}

	for _, entry in entries do
		if isPathUnder(entry, base) then
			table.insert(results, entry)
		end
	end

	return results
end

local function isScriptPath(path: string): boolean
	local extension = fs.path.extension(path)
	return extension == ".luau" or extension == ".lua"
end

local function appendUnique(results: { string }, seen: { [string]: boolean }, entry: string)
	local normalized = normalizePath(entry)
	if seen[normalized] then
		return
	end

	seen[normalized] = true
	table.insert(results, entry)
end

local function embeddedScriptEntries(): { string }
	local results = {}
	local seen = {}

	for _, entry in fs.embeddedScripts() do
		appendUnique(results, seen, entry)
	end

	for _, entry in fs.embeddedFiles() do
		if isScriptPath(entry) then
			appendUnique(results, seen, entry)
		end
	end

	return results
end

local function isAbsolutePath(path: string): boolean
	return path:match("^%a:[/\\]") ~= nil or path:sub(1, 1) == "/" or path:sub(1, 2) == [[\\]]
end

function lib.IsEmbedded()
	local result = embeddedScriptEntries()
	if result[1] then
		return true
	else
		return false
	end
end

function lib.ExecutableDir(): string
	local dir = fs.path.dirname(fs.getExePath()) or "."
	return fs.path.resolve(dir)
end

function lib.RuntimePath(path: string): string
	if lib.IsEmbedded() and not isAbsolutePath(path) then
		return fs.path.resolve(lib.ExecutableDir(), path)
	end
	return path
end

function lib.AssetPath(path: string): string
	if type(path) ~= "string" then
		return path
	end

	local normalized = normalizePath(path)
	local assetPath = normalized:match("^kineasset://(.+)$")

	if not assetPath then
		assetPath = normalized:match("^%.?/src/assets/(.+)$")
	end

	if not assetPath then
		assetPath = normalized:match("^%.?/assets/(.+)$")
	end

	if assetPath then
		if lib.IsEmbedded() then
			return fs.path.resolve(lib.ExecutableDir(), "assets", assetPath)
		end
		return fs.path.resolve("src", "assets", assetPath)
	end

	return path
end

function lib.Path(path: string): string
	return lib.AssetPath(path)
end

function lib.GetEmbeddedScripts()
	return embeddedScriptEntries()
end

function lib.GetEmbeddedFiles()
	return fs.embeddedFiles()
end

function lib.GetScriptsUnder(path: string): { string }
	return getEmbeddedUnder(lib.GetEmbeddedScripts(), path)
end

function lib.GetFilesUnder(path: string): { string }
	return getEmbeddedUnder(lib.GetEmbeddedFiles(), path)
end

function lib.GetAssetFilesUnder(path: string): { string }
	local sourcePath = assetToSourcePath(path) or path
	return lib.GetFilesUnder(sourcePath)
end

function lib.GetScriptsThatHas(str)
	local scripts = lib.GetEmbeddedScripts()
	local results = {}
	local needle = normalizePath(str)

	for _, script in scripts do
		if string.find(normalizePath(script), needle, 1, true) then
			table.insert(results, script)
		end
	end

	return results
end

function lib.GetPathEmbedded()
	if lib.IsEmbedded() then
		return "../"
	else
		return "./"
	end
end

function lib.GetFilesThatHas(str)
	local scripts = fs.embeddedFiles()
	local results = {}
	local needle = normalizePath(str)

	for _, script in scripts do
		if string.find(normalizePath(script), needle, 1, true) then
			table.insert(results, script)
		end
	end

	return results
end

function lib.readFile(script)
	if lib.IsEmbedded() then
		local normalized = normalizePath(script)
		local variants = {
			script,
			normalized,
			normalized:gsub("/", [[\]]),
			"./" .. normalized,
			[[.\]] .. normalized:gsub("/", [[\]]),
			"../" .. normalized,
			[[..\]] .. normalized:gsub("/", [[\]]),
		}

		for _, variant in variants do
			local success, result = pcall(fs.embedFile, variant)
			if success and result then
				if type(result) == "buffer" then
					return buffer.tostring(result)
				end
				return result
			end
		end

	end

	return fs.readFile(script)
end

function lib.readAsset(path: string, binary: boolean?)
	local sourcePath = assetToSourcePath(path)

	if sourcePath and lib.IsEmbedded() then
		local normalized = normalizePath(sourcePath)
		local variants = {
			normalized,
			"./" .. normalized,
			normalized:gsub("/", [[\]]),
			[[.\]] .. normalized:gsub("/", [[\]]),
		}

		for _, variant in variants do
			local success, result = pcall(fs.embedFile, variant)
			if success and result then
				if binary then
					if type(result) == "buffer" then
						return result
					end

					return buffer.fromstring(result)
				end

				if type(result) == "buffer" then
					return buffer.tostring(result)
				end

				return result
			end
		end
	end

	return fs.readFile(lib.AssetPath(path), binary)
end

return lib
