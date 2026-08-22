--!strict
local fs = zune.fs
local net = zune.net
local serde = zune.serde
local zip = require("./Packager/lib/zip")
local tar = require("./Packager/lib/tar")

local Downloader = {}

local function request(link: string, options: any, bytes: boolean?): any
	local res = net.http.request(link, options, bytes)
	if res.status_code == 301 or res.status_code == 302 then
		local location = res.headers["location"]
		if location then
			return request(location, options, bytes)
		else
			error("Redirection without location")
		end
	end
	return res
end

function Downloader.download(url: string, parentFolder: string, filename: string?)
	fs.makeDir(parentFolder)

	local res = request(url, { method = "GET" }, true)
	if not res.ok then
		error(`Failed to download {url}`)
	end
	local data = res.body

	if zip.is(data) then
		local files = zip.read(data)
		for name, content in files do
			print("Making file " .. name)
			local path = fs.path.join(parentFolder, filename or name)
			fs.writeFile(path, content)
		end
	elseif serde.gzip.is(data) then
		local decompressed = serde.gzip.decompress(data)
		local files = tar.read(decompressed)
		for name, content in files do
			local path = fs.path.join(parentFolder, filename or name)
			fs.writeFile(path, content)
		end
	else
		-- Regular file
		local path = fs.path.join(parentFolder, filename or fs.path.basename(url))
		fs.writeFile(path, data)
	end
end

return Downloader
