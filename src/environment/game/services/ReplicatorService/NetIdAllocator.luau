local NetIdAllocator = {}
NetIdAllocator.__index = NetIdAllocator

local INDEX_BITS = 20
local INDEX_MODULUS = 2 ^ INDEX_BITS
local MAX_GENERATION = 2 ^ (32 - INDEX_BITS)

function NetIdAllocator.new()
	return setmetatable({ nextIndex = 1, free = {}, generations = {}, active = {} }, NetIdAllocator)
end

function NetIdAllocator:Allocate()
	local index = table.remove(self.free)
	if not index then
		index = self.nextIndex
		assert(index < INDEX_MODULUS, "network entity ID capacity exhausted")
		self.nextIndex += 1
	end
	local generation = self.generations[index] or 0
	local id = generation * INDEX_MODULUS + index
	self.active[id] = index
	return id
end

function NetIdAllocator:Release(id)
	id = math.floor(tonumber(id) or -1)
	local index = self.active[id]
	if not index then
		return false
	end
	self.active[id] = nil
	self.generations[index] = ((self.generations[index] or 0) + 1) % MAX_GENERATION
	table.insert(self.free, index)
	return true
end

function NetIdAllocator:IsActive(id)
	return self.active[math.floor(tonumber(id) or -1)] ~= nil
end

function NetIdAllocator.GetIndex(id)
	return math.floor(tonumber(id) or 0) % INDEX_MODULUS
end

function NetIdAllocator.GetGeneration(id)
	return math.floor((tonumber(id) or 0) / INDEX_MODULUS)
end

return NetIdAllocator
