local ffi = zune.ffi
local mem = zune.mem

local function getFieldType(structType, fieldName)
	local fieldInfo = structType:field(fieldName)
	return fieldInfo and fieldInfo.type
end

local typeSizes = {
	[ffi.types.i8] = 1,
	[ffi.types.u8] = 1,
	[ffi.types.i16] = 2,
	[ffi.types.u16] = 2,
	[ffi.types.i32] = 4,
	[ffi.types.u32] = 4,
	[ffi.types.i64] = 8,
	[ffi.types.u64] = 8,
	[ffi.types.float] = 4,
	[ffi.types.double] = 8,
	[ffi.types.pointer] = 8,
}

local function readWithType(object, offset, dataType)
	if dataType == ffi.types.i8 then
		return buffer.readi8(object, offset)
	elseif dataType == ffi.types.u8 then
		return buffer.readu8(object, offset)
	elseif dataType == ffi.types.i16 then
		return buffer.readi16(object, offset)
	elseif dataType == ffi.types.u16 then
		return buffer.readu16(object, offset)
	elseif dataType == ffi.types.i32 then
		return buffer.readi32(object, offset)
	elseif dataType == ffi.types.u32 then
		return buffer.readu32(object, offset)
	elseif dataType == ffi.types.i64 then
		return buffer.readi32(object, offset) + (buffer.readi32(object, offset + 4) * 4294967296)
	elseif dataType == ffi.types.u64 then
		return buffer.readu32(object, offset) + (buffer.readu32(object, offset + 4) * 4294967296)
	elseif dataType == ffi.types.float then
		return buffer.readf32(object, offset)
	elseif dataType == ffi.types.double then
		return buffer.readf64(object, offset)
	elseif dataType == ffi.types.pointer then
		local addrBuffer = buffer.create(8)
		local addr = buffer.readu64(object, offset)
		buffer.writeu64(addrBuffer, 0, addr)
		return ffi.ptrFromAddress(addrBuffer)
	else
		error("Unsupported or unknown type for auto-detection")
	end
end

return {
	read = function(object, structType, fieldName)
		local offset = structType:offset(fieldName)
		local fieldType = getFieldType(structType, fieldName)

		if not fieldType then
			error(string.format("Cannot determine type for field '%s'", fieldName))
		end

		return readWithType(object, offset, fieldType)
	end,

	getpointer = function(object, parentStructType, fieldName, fieldStructType)
		return mem.slice(object, parentStructType:offset(fieldName), fieldStructType:size())
	end,

	readi8 = function(object, structType, fieldName)
		local offset = structType:offset(fieldName)
		return buffer.readi8(object, offset)
	end,

	readu8 = function(object, structType, fieldName)
		local offset = structType:offset(fieldName)
		return buffer.readu8(object, offset)
	end,

	readi16 = function(object, structType, fieldName)
		local offset = structType:offset(fieldName)
		return buffer.readi16(object, offset)
	end,

	readu16 = function(object, structType, fieldName)
		local offset = structType:offset(fieldName)
		return buffer.readu16(object, offset)
	end,

	readi32 = function(object, structType, fieldName)
		local offset = structType:offset(fieldName)
		return buffer.readi32(object, offset)
	end,

	readu32 = function(object, structType, fieldName)
		local offset = structType:offset(fieldName)
		return buffer.readu32(object, offset)
	end,

	readi64 = function(object, structType, fieldName)
		local offset = structType:offset(fieldName)
		return buffer.readi32(object, offset) + (buffer.readi32(object, offset + 4) * 4294967296)
	end,

	readu64 = function(object, structType, fieldName)
		local offset = structType:offset(fieldName)
		return buffer.readu32(object, offset) + (buffer.readu32(object, offset + 4) * 4294967296)
	end,

	readf32 = function(object, structType, fieldName)
		local offset = structType:offset(fieldName)
		return buffer.readf32(object, offset)
	end,

	readf64 = function(object, structType, fieldName)
		local offset = structType:offset(fieldName)
		return buffer.readf64(object, offset)
	end,

	readstring = function(object, structType, fieldName, length)
		local offset = structType:offset(fieldName)
		if length then
			return buffer.readstring(object, offset, length)
		else
			return buffer.readstring(object, offset)
		end
	end,

	readbytes = function(object, structType, fieldName, size)
		local offset = structType:offset(fieldName)
		local result = buffer.create(size)
		buffer.copy(result, 0, object, offset, size)
		return result
	end,

	getoffset = function(structType, fieldName)
		return structType:offset(fieldName)
	end,

	getsize = function(structType)
		return structType:size()
	end,
}
