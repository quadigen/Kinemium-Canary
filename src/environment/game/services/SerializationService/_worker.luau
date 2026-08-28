local thread = zune.thread
local serde = zune.serde
local zstd = serde.zstd

local function decompress(str)
	return zstd.decompress(str)
end

local function compress(tbl)
	return zstd.compress(tbl, { level = 1 })
end

while true do
	local req = thread.receive()
	if not req then
		continue
	end

	if req.action == "decompress" then
		local ok, result = pcall(decompress, req.data)
		if ok then
			thread.send({ id = req.id, result = result })
		else
			thread.send({ id = req.id, error = tostring(result) })
		end
	elseif req.action == "compress" then
		local ok, result = pcall(compress, req.data)
		if ok then
			thread.send({ id = req.id, result = result })
		else
			thread.send({ id = req.id, error = tostring(result) })
		end
	end
end
