-- Filament adapter
local ffi = zune.ffi
local filament = require("./filament")
local filamentAdapter = {}
local typedefs = require("../../typedefs")

local filamentPixelsPtr = nil
local DrawItem = filament.structs.KineFilamentDrawItem
local DRAW_ITEM_SIZE = DrawItem:size()
local DRAW_CAST_SHADOWS = 1
local DRAW_RECEIVE_SHADOWS = 2
local DRAW_CULLING = 4

local function readCString(pointer, maxLength: number?): string
	if not pointer or pointer == zune.ffi.null then
		return ""
	end
	local bytes = {}
	for index = 0, (maxLength or 4096) - 1 do
		local byte = pointer:readu8(index)
		if byte == 0 then
			break
		end
		bytes[#bytes + 1] = string.char(byte)
	end
	return table.concat(bytes)
end
local drawListBuffers: { [any]: any } = setmetatable({}, { __mode = "k" })
local indexBuffers: { [any]: any } = setmetatable({}, { __mode = "k" })
local transformBuffers: { [any]: any } = setmetatable({}, { __mode = "k" })
local skinBuffers: { [any]: any } = setmetatable({}, { __mode = "k" })
local drawListVersions: { [any]: { [number]: number } } = setmetatable({}, { __mode = "k" })

assert(DRAW_ITEM_SIZE == 128, "KineFilamentDrawItem ABI mismatch")

local drawItemOffsets = {
	mesh = DrawItem:offset("mesh"),
	tex = DrawItem:offset("tex"),
	transform = DrawItem:offset("transform"),
	r = DrawItem:offset("r"),
	g = DrawItem:offset("g"),
	b = DrawItem:offset("b"),
	param1 = DrawItem:offset("param1"),
	param2 = DrawItem:offset("param2"),
	param3 = DrawItem:offset("param3"),
	transmission = DrawItem:offset("transmission"),
	materialKind = DrawItem:offset("materialKind"),
	flags = DrawItem:offset("flags"),
	reserved = DrawItem:offset("reserved"),
	shader = DrawItem:offset("shader"),
}

local function getDrawListBuffer(window: typedefs.Window, itemCount: number)
	local state = drawListBuffers[window]
	if state and state.capacity >= itemCount then
		return state.pointer
	end

	local capacity = if state then state.capacity else 0
	capacity = math.max(capacity, 64)
	while capacity < itemCount do
		capacity *= 2
	end

	if state then
		zune.ffi.free(state.pointer)
	end

	local pointer = zune.ffi.alloc(capacity * DRAW_ITEM_SIZE)
	drawListBuffers[window] = {
		pointer = pointer,
		capacity = capacity,
	}
	return pointer
end

local function getRawBuffer(cache, window: typedefs.Window, byteCount: number)
	local state = cache[window]
	if state and state.capacity >= byteCount then
		return state.pointer
	end

	local capacity = if state then state.capacity else 0
	capacity = math.max(capacity, 1024)
	while capacity < byteCount do
		capacity *= 2
	end

	if state then
		zune.ffi.free(state.pointer)
	end

	local pointer = zune.ffi.alloc(capacity)
	cache[window] = {
		pointer = pointer,
		capacity = capacity,
	}
	return pointer
end

local function writeTransform(items, transformOffset: number, rawMatrix, cframe, scale)
	if rawMatrix then
		items:write(transformOffset, rawMatrix, 0, 16 * 4)
		return true
	end

	if not cframe or not scale then
		return false
	end

	local position = cframe.Position
	local rotation = cframe.Rotation
	-- The FFI array is written as four affine rows. The native shim explicitly
	-- gathers indices 0/4/8/12, etc. into Filament's column vectors. Keep this
	-- layout paired with kine_draw_item_transform; writing this as a flat
	-- column-major array here would transpose the transform a second time.
	items:writef32(transformOffset, rotation[1][1] * scale.X)
	items:writef32(transformOffset + 4, rotation[1][2] * scale.Y)
	items:writef32(transformOffset + 8, rotation[1][3] * scale.Z)
	items:writef32(transformOffset + 12, position.X)
	items:writef32(transformOffset + 16, rotation[2][1] * scale.X)
	items:writef32(transformOffset + 20, rotation[2][2] * scale.Y)
	items:writef32(transformOffset + 24, rotation[2][3] * scale.Z)
	items:writef32(transformOffset + 28, position.Y)
	items:writef32(transformOffset + 32, rotation[3][1] * scale.X)
	items:writef32(transformOffset + 36, rotation[3][2] * scale.Y)
	items:writef32(transformOffset + 40, rotation[3][3] * scale.Z)
	items:writef32(transformOffset + 44, position.Z)
	items:writef32(transformOffset + 48, 0)
	items:writef32(transformOffset + 52, 0)
	items:writef32(transformOffset + 56, 0)
	items:writef32(transformOffset + 60, 1)
	return true
end

local function writeDrawItem(items, packedCount: number, drawCall)
	local mesh = drawCall and drawCall.mesh
	local rawMatrix = drawCall and drawCall.matrix
	local cframe = drawCall and drawCall.cframe
	local scale = drawCall and drawCall.scale
	if type(rawMatrix) == "table" and rawMatrix.getraw then
		rawMatrix = rawMatrix:getraw()
	end

	if not mesh or not mesh._handle then
		return false
	end

	local base = packedCount * DRAW_ITEM_SIZE
	if not writeTransform(items, base + drawItemOffsets.transform, rawMatrix, cframe, scale) then
		return false
	end

	local flags = 0
	if drawCall.CastShadow ~= false then
		flags += DRAW_CAST_SHADOWS
	end
	if drawCall.RecieveShadow ~= false then
		flags += DRAW_RECEIVE_SHADOWS
	end
	if drawCall.Culling == true then
		flags += DRAW_CULLING
	end

	local color = drawCall.color
	items:writeptr(base + drawItemOffsets.mesh, mesh._handle)
	items:writeptr(base + drawItemOffsets.tex, drawCall.texture or zune.ffi.null)
	items:writef32(base + drawItemOffsets.r, color.R)
	items:writef32(base + drawItemOffsets.g, color.G)
	items:writef32(base + drawItemOffsets.b, color.B)
	items:writef32(base + drawItemOffsets.param1, math.clamp(drawCall.roughness or 0.5, 0, 1))
	items:writef32(base + drawItemOffsets.param2, math.clamp(drawCall.metallic or 0, 0, 1))
	items:writef32(base + drawItemOffsets.param3, drawCall.MaterialTileScale or 1)
	items:writef32(base + drawItemOffsets.transmission, drawCall.transmission or 0)
	items:writei32(base + drawItemOffsets.materialKind, drawCall.MaterialKind or 0)
	items:writeu32(base + drawItemOffsets.flags, flags)
	items:writeu32(base + drawItemOffsets.reserved, 0)
	items:writeptr(base + drawItemOffsets.shader, drawCall.shader or zune.ffi.null)
	return true
end

function filamentAdapter:Init(window: typedefs.Window)
	filamentPixelsPtr = zune.ffi.alloc(window.Width * window.Height * 4)

	if window.WGI == "vulkan" then
		-- Filament owns the compositor only on the 3D path. A 2D-only renderer
		-- creates the standalone compositor directly and never calls Init3D.
		window._3dhandle =
			filament.lib.Kine_Filament_CreateForVulkanCompositorWindow(window._handle, window.Width, window.Height)
	else
		window._3dhandle = filament.lib.Kine_Filament_Create(window.Width, window.Height)
	end
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		print("Filament context creation failed.")
		return
	end
	filament.lib.Kine_Filament_CreateSky(window._3dhandle, 102 / 255, 191 / 255, 255 / 255, 1)
end

function filamentAdapter:CreateViewport(width: number, height: number)
	width = math.max(1, math.floor(width))
	height = math.max(1, math.floor(height))
	local handle = filament.lib.Kine_Filament_Create(width, height)
	if not handle or handle == zune.ffi.null then
		return nil, "Could not create the offscreen Filament context"
	end

	local viewportWindow = {
		_3dhandle = handle,
		Width = width,
		Height = height,
		WGI = "offscreen",
	}
	filament.lib.Kine_Filament_CreateSky(handle, 30 / 255, 34 / 255, 43 / 255, 1)
	return {
		Window = viewportWindow,
		Width = width,
		Height = height,
		Pixels = zune.ffi.alloc(width * height * 4),
	}
end

function filamentAdapter:ResizeViewport(viewport, width: number, height: number)
	if not viewport or not viewport.Window or not viewport.Window._3dhandle then
		return false
	end
	width = math.max(1, math.floor(width))
	height = math.max(1, math.floor(height))
	if viewport.Width == width and viewport.Height == height then
		return true
	end
	filament.lib.Kine_Filament_Resize(viewport.Window._3dhandle, width, height)
	if viewport.Pixels then
		zune.ffi.free(viewport.Pixels)
	end
	viewport.Pixels = zune.ffi.alloc(width * height * 4)
	viewport.Width = width
	viewport.Height = height
	viewport.Window.Width = width
	viewport.Window.Height = height
	return true
end

function filamentAdapter:SetViewportCamera(viewport, position, target, fieldOfView: number?)
	local window = viewport and viewport.Window
	local handle = window and window._3dhandle
	if not handle or handle == zune.ffi.null then
		return false
	end
	local aspect = viewport.Width / math.max(1, viewport.Height)
	filament.lib.Kine_Filament_SetCameraPerspective(handle, fieldOfView or 60, aspect, 0.1, 500)
	filament.lib.Kine_Filament_SetCameraLookAt(
		handle,
		position.X,
		position.Y,
		position.Z,
		target.X,
		target.Y,
		target.Z,
		0,
		1,
		0
	)
	return true
end

function filamentAdapter:RenderViewport(viewport, dt: number)
	local window = viewport and viewport.Window
	local handle = window and window._3dhandle
	if not handle or handle == zune.ffi.null or not viewport.Pixels then
		return nil
	end
	filament.lib.Kine_Filament_RenderFrame(handle, dt)
	filament.lib.Kine_Filament_ReadPixels(handle, viewport.Pixels)
	return viewport.Pixels, viewport.Width * 4
end

function filamentAdapter:DestroyViewport(viewport)
	if not viewport then
		return
	end
	if viewport.Pixels then
		zune.ffi.free(viewport.Pixels)
		viewport.Pixels = nil
	end
	local window = viewport.Window
	if window then
		local drawListBuffer = drawListBuffers[window]
		if drawListBuffer then
			zune.ffi.free(drawListBuffer.pointer)
			drawListBuffers[window] = nil
		end
		drawListVersions[window] = nil
		if window._3dhandle and window._3dhandle ~= zune.ffi.null then
			filament.lib.Kine_Filament_Destroy(window._3dhandle)
		end
		window._3dhandle = nil
	end
	viewport.Window = nil
end

function filamentAdapter:CreateMaterialShader(window: typedefs.Window, source: string)
	if not window or not window._3dhandle or window._3dhandle == zune.ffi.null then
		return nil, "Filament is not initialized for this window"
	end
	local handle = filament.lib.Kine_Filament_Shader_Create(window._3dhandle, source)
	if not handle or handle == zune.ffi.null then
		return nil, readCString(filament.lib.Kine_Filament_Shader_GetLastError())
	end
	return handle
end

function filamentAdapter:DestroyMaterialShader(shader)
	if shader and shader ~= zune.ffi.null then
		filament.lib.Kine_Filament_Shader_Destroy(shader)
	end
end

function filamentAdapter:SetMaterialShaderUniform(shader, name: string, values: { number })
	if not shader or shader == zune.ffi.null or #values == 0 then
		return false
	end
	local data = zune.ffi.alloc(#values * 4)
	for index, value in ipairs(values) do
		data:writef32((index - 1) * 4, value)
	end
	local result = filament.lib.Kine_Filament_Shader_SetUniform(shader, name, data, #values) ~= 0
	zune.ffi.free(data)
	return result
end

function filamentAdapter:SetGlobalMaterialShader(window: typedefs.Window, shader)
	if not window or not window._3dhandle or window._3dhandle == zune.ffi.null then
		return false
	end
	return filament.lib.Kine_Filament_SetGlobalShader(window._3dhandle, shader or zune.ffi.null) ~= 0
end

function filamentAdapter:SetPostProcessShader(window: typedefs.Window, shader)
	if not window or not window._3dhandle or window._3dhandle == zune.ffi.null then
		return false, "Filament is not initialized for this window"
	end
	local applied = filament.lib.Kine_Filament_SetPostProcessShader(window._3dhandle, shader or zune.ffi.null) ~= 0
	if not applied then
		return false, readCString(filament.lib.Kine_Filament_Shader_GetLastError())
	end
	return true
end

function filamentAdapter:GetVulkanCompositor(window: typedefs.Window)
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return nil
	end
	local compositor = filament.lib.Kine_Filament_GetVulkanCompositor(window._3dhandle)
	if not compositor or compositor == zune.ffi.null then
		return nil
	end
	return compositor
end

function filamentAdapter:GetVulkanBackend(window: typedefs.Window, outBackend)
	if not window._3dhandle then
		return false
	end
	return filament.lib.Kine_Filament_GetVulkanBackend(window._3dhandle, outBackend) ~= 0
end

function filamentAdapter:Shutdown(window: typedefs.Window)
	local drawListBuffer = drawListBuffers[window]
	if drawListBuffer then
		zune.ffi.free(drawListBuffer.pointer)
		drawListBuffers[window] = nil
	end
	drawListVersions[window] = nil
	if window._3dhandle then
		filament.lib.Kine_Filament_Destroy(window._3dhandle)
		window._3dhandle = nil
	end
end

function filamentAdapter:SetCameraPosition(window: typedefs.Window, position: typedefs.Vector3)
	local handle = window._3dhandle
	if not handle or handle == zune.ffi.null then
		return
	end
	filament.lib.Kine_Filament_SetCameraPosition(handle, position.X, position.Y, position.Z)
end

function filamentAdapter:SetCameraLookAt(window: typedefs.Window, position: typedefs.Vector3, target: typedefs.Vector3)
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return
	end
	filament.lib.Kine_Filament_SetCameraLookAt(
		window._3dhandle,
		position.X,
		position.Y,
		position.Z,
		target.X,
		target.Y,
		target.Z,
		0,
		1,
		0
	)
end

function filamentAdapter:SetCameraPerspective(
	window: typedefs.Window,
	fieldOfView: number,
	aspect: number,
	nearPlane: number?,
	farPlane: number?
)
	local handle = window._3dhandle
	if not handle or handle == zune.ffi.null then
		return
	end
	filament.lib.Kine_Filament_SetCameraPerspective(
		handle,
		fieldOfView,
		aspect,
		nearPlane or 1,
		farPlane or 500
	)
end

local filamentLightTypes = {
	Point = 0,
	Spot = 1,
	Surface = 2,
}

function filamentAdapter:CreateLight(window: typedefs.Window, lightType: string, options): typedefs.Light?
	if not window or not window._3dhandle then
		return nil
	end
	options = options or {}
	local position = options.Position or { X = 0, Y = 0, Z = 0 }
	local direction = options.Direction or { X = 0, Y = -1, Z = 0 }
	local color = options.Color or { R = 1, G = 1, B = 1 }
	local outer = math.rad(math.clamp(options.Angle or 90, 1, 180) * 0.5)
	local inner = outer * math.clamp(options.InnerConeRatio or 0.8, 0.05, 1)
	local handle = filament.lib.Kine_Filament_CreateLightEx(
		window._3dhandle,
		filamentLightTypes[lightType] or filamentLightTypes.Point,
		position.X, position.Y, position.Z,
		direction.X, direction.Y, direction.Z,
		color.R, color.G, color.B,
		math.max(0, options.Brightness or 1) * 100000,
		math.max(0.001, options.Range or 12),
		inner, outer,
		if options.CastShadow == true then 1 else 0,
		if options.Enabled ~= false then 1 else 0
	)
	if handle < 0 then
		return nil
	end
	return { _handle = handle }
end

function filamentAdapter:UpdateLight(window: typedefs.Window, light: typedefs.Light, options)
	if not window or not light then
		return
	end
	local ctx, handle = window._3dhandle, light._handle
	if options.Position then
		local value = options.Position
		filament.lib.Kine_Filament_SetPositionLight(ctx, handle, value.X, value.Y, value.Z)
	end
	if options.Direction then
		local value = options.Direction
		filament.lib.Kine_Filament_SetDirectionLight(ctx, handle, value.X, value.Y, value.Z)
	end
	if options.Color then
		local value = options.Color
		filament.lib.Kine_Filament_SetColorLight(ctx, handle, value.R, value.G, value.B)
	end
	if options.Brightness ~= nil then
		filament.lib.Kine_Filament_SetIntensityLight(ctx, handle, math.max(0, options.Brightness) * 100000)
	end
	if options.Range ~= nil then
		filament.lib.Kine_Filament_SetFalloffLight(ctx, handle, math.max(0.001, options.Range))
	end
	if options.Angle ~= nil then
		local outer = math.rad(math.clamp(options.Angle, 1, 180) * 0.5)
		filament.lib.Kine_Filament_SetConeLight(ctx, handle, outer * 0.8, outer)
	end
	if options.CastShadow ~= nil then
		filament.lib.Kine_Filament_SetShadowLight(ctx, handle, if options.CastShadow == true then 1 else 0)
	end
	if options.Enabled ~= nil then
		filament.lib.Kine_Filament_SetEnabledLight(ctx, handle, if options.Enabled == true then 1 else 0)
	end
end

function filamentAdapter:RemoveLight(window: typedefs.Window, light: typedefs.Light?)
	if window and light then
		filament.lib.Kine_Filament_RemoveLight(window._3dhandle, light._handle)
	end
end

function filamentAdapter:CreateDecal(
	window: typedefs.Window,
	width,
	height,
	texture: FFIPointerType,
	offsetStudsU,
	offsetStudsV,
	studsPerTileU,
	studsPerTileV
): typedefs.Decal
	local handle = window._3dhandle
	local decal = filament.lib.Kine_Filament_CreateDecal(
		handle,
		width,
		height,
		texture,
		offsetStudsU,
		offsetStudsV,
		studsPerTileU,
		studsPerTileV,
		false,
		false,
		true
	)
	return { _handle = decal }
end

function filamentAdapter:RemoveDecal(window: typedefs.Window, decal: typedefs.Decal)
	if not decal then
		return
	end
	filament.lib.Kine_Filament_RemoveDecal(window._3dhandle, decal._handle)
end

function filamentAdapter:SetDecalTransform(window: typedefs.Window, decal: typedefs.Decal, mat4: any)
	local handle = window._3dhandle

	filament.lib.Kine_Filament_SetDecalTransform(handle, decal._handle, mat4)
end

function filamentAdapter:SetDecalTiling(
	window: typedefs.Window,
	decal: typedefs.Decal,
	width: number,
	height: number,
	offsetStudsU: number?,
	offsetStudsV: number?,
	studsPerTileU: number?,
	studsPerTileV: number?
)
	filament.lib.Kine_Filament_SetDecalTiling(
		window._3dhandle,
		decal._handle,
		width,
		height,
		offsetStudsU or 0,
		offsetStudsV or 0,
		studsPerTileU or 0,
		studsPerTileV or 0
	)
end

function filamentAdapter:Resize3D(window: typedefs.Window, width, height)
	local handle = window._3dhandle
	if not handle or handle == zune.ffi.null then
		return
	end
	filament.lib.Kine_Filament_Resize(handle, width, height)
	if window.WGI == "vulkan" then
		local compositor = self:GetVulkanCompositor(window)
		if compositor and not window._vulkanCompositor then
			window._vulkanCompositor = compositor
			window._vulkanCompositorOwnedByFilament = true
		end
	end
end

function filamentAdapter:SetViewport(window: typedefs.Window, x: number?, y: number?, width: number?, height: number?)
	local handle = window._3dhandle
	if not handle then
		return
	end

	filament.lib.Kine_Filament_SetViewport(handle, x or 0, y or 0, width or 0, height or 0)
end

function filamentAdapter:Render3D(window: typedefs.Window, dt: number)
	local handle = window._3dhandle
	if not handle or handle == zune.ffi.null then
		return
	end
	filament.lib.Kine_Filament_RenderFrame(handle, dt)
end

function filamentAdapter:ResizePixelBuffer(window, width, height)
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return
	end
	if filamentPixelsPtr then
		zune.ffi.free(filamentPixelsPtr)
	end
	filamentPixelsPtr = zune.ffi.alloc(width * height * 4)
	filamentAdapter:Resize3D(window, width, height)
end

function filamentAdapter:BlitToScreen(
	window: typedefs.Window,
	dstX: number,
	dstY: number,
	dstWidth: number,
	dstHeight: number
)
	filament.lib.Kine_Filament_BlitToScreen(window._3dhandle, dstX, dstY, dstWidth, dstHeight)
end

function filamentAdapter:CreateTextureFromImage(window: typedefs.Window, image: typedefs.Image)
	return filament.lib.Kine_Filament_CreateTexFromPixels(
		window._3dhandle,
		image.width,
		image.height,
		image.pitch,
		image.pixels
	)
end

function filamentAdapter:UpdateTextureFromImage(window: typedefs.Window, texture, image: typedefs.Image)
	if not texture or not image then
		return false
	end
	return filament.lib.Kine_Filament_UpdateTexFromPixels(
		window._3dhandle,
		texture,
		image.width,
		image.height,
		image.pitch,
		image.pixels
	) ~= 0
end

function filamentAdapter:Destroy3DTexture(window: typedefs.Window, texture: FFIPointerType?)
	if not texture then
		return
	end
	filament.lib.Kine_Filament_DestroyTex(window._3dhandle, texture)
end

function filamentAdapter:CreateParticleTexture(window: typedefs.Window, image: typedefs.Image)
	return filamentAdapter:CreateTextureFromImage(window, image)
end

function filamentAdapter:CreateMaterialTextureFromImages(
	window: typedefs.Window,
	albedo: typedefs.Image,
	normal: typedefs.Image?,
	orm: typedefs.Image?,
	height: typedefs.Image?,
	heightScale: number?
)
	return filament.lib.Kine_Filament_CreatePbrTexFromPixels(
		window._3dhandle,
		albedo.width,
		albedo.height,
		albedo.pitch,
		albedo.pixels,
		normal and normal.width or 0,
		normal and normal.height or 0,
		normal and normal.pitch or 0,
		normal and normal.pixels or nil,
		orm and orm.width or 0,
		orm and orm.height or 0,
		orm and orm.pitch or 0,
		orm and orm.pixels or nil,
		height and height.width or 0,
		height and height.height or 0,
		height and height.pitch or 0,
		height and height.pixels or nil,
		heightScale or 0.0
	)
end

function filamentAdapter:CreateTerrainTextureSet(window: typedefs.Window, layers: { FFIPointerType? })
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return nil
	end
	local textureSet = filament.lib.Kine_Filament_CreateTerrainTextureSet(
		window._3dhandle,
		layers[1],
		layers[2],
		layers[3],
		layers[4],
		layers[5],
		layers[6]
	)
	if not textureSet or textureSet == zune.ffi.null then
		return nil
	end
	return textureSet
end

function filamentAdapter:CreateMesh(
	window: typedefs.Window,
	meshType: "cube" | "displacedCube" | "sphere" | "cylinder" | "pyramid" | "quad" | "moveGizmo" | "rotateGizmo" | "scaleGizmo"
): typedefs.Mesh
	local map = {
		["cube"] = 1,
		["displacedCube"] = 5,
		["sphere"] = 2,
		["cylinder"] = 6,
		["pyramid"] = 3,
		["quad"] = 4,
		["moveGizmo"] = 10,
		["rotateGizmo"] = 11,
		["scaleGizmo"] = 12,
	}

	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return { _handle = nil }
	end
	return { _handle = filament.lib.Kine_Filament_CreateMesh(window._3dhandle, map[meshType]) }
end

function filamentAdapter:CreateMeshFromPath(window: typedefs.Window, path: string): typedefs.Mesh?
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return nil
	end
	local mesh = filament.lib.Kine_Filament_CreateMeshFromPath(window._3dhandle, path)
	if not mesh or mesh == zune.ffi.null then
		return nil
	end
	return { _handle = mesh }
end

function filamentAdapter:LoadMeshDataFromPath(path: string): any?
	local nativeData = filament.lib.Kine_Filament_LoadMeshDataFromPath(path)
	if not nativeData or nativeData == zune.ffi.null then
		return nil
	end

	local vertexCount = filament.lib.Kine_Filament_GetMeshDataVertexCount(nativeData)
	local indexCount = filament.lib.Kine_Filament_GetMeshDataIndexCount(nativeData)
	if vertexCount < 3 or indexCount < 3 then
		filament.lib.Kine_Filament_DestroyMeshData(nativeData)
		return nil
	end

	local positions = ffi.create(ffi.types.float:array(vertexCount * 3))
	local indices = ffi.create(ffi.types.u32:array(indexCount))
	local positionsOk = filament.lib.Kine_Filament_CopyMeshDataPositions(nativeData, positions, vertexCount * 3) ~= 0
	local indicesOk = filament.lib.Kine_Filament_CopyMeshDataIndices(nativeData, indices, indexCount) ~= 0
	filament.lib.Kine_Filament_DestroyMeshData(nativeData)
	if not positionsOk or not indicesOk then
		return nil
	end

	local vertices = table.create(vertexCount)
	for index = 0, vertexCount - 1 do
		vertices[index + 1] = {
			position = {
				positions:readf32(index * 12),
				positions:readf32(index * 12 + 4),
				positions:readf32(index * 12 + 8),
			},
		}
	end
	local resultIndices = table.create(indexCount)
	for index = 0, indexCount - 1 do
		resultIndices[index + 1] = indices:readu32(index * 4)
	end
	return { vertices = vertices, indices = resultIndices }
end

function filamentAdapter:GetMeshSkeleton(mesh: typedefs.Mesh): { any }
	if not mesh or not mesh._handle then
		return {}
	end
	local boneCount = filament.lib.Kine_Filament_GetMeshBoneCount(mesh._handle)
	if boneCount <= 0 then
		return {}
	end
	local matrix = ffi.alloc(16 * 4)
	local bones = table.create(boneCount)
	for boneIndex = 0, boneCount - 1 do
		local copied = filament.lib.Kine_Filament_CopyMeshBoneBindTransform(mesh._handle, boneIndex, matrix) ~= 0
		local values = table.create(16)
		if copied then
			for component = 0, 15 do
				values[component + 1] = matrix:readf32(component * 4)
			end
		end
		local parent = filament.lib.Kine_Filament_GetMeshBoneParent(mesh._handle, boneIndex)
		bones[boneIndex + 1] = {
			index = boneIndex,
			name = readCString(filament.lib.Kine_Filament_GetMeshBoneName(mesh._handle, boneIndex), 1024),
			parentIndex = if parent >= 0 then parent + 1 else 0,
			bindTransform = values,
		}
	end
	ffi.free(matrix)
	return bones
end

function filamentAdapter:GetMeshAnimations(mesh: typedefs.Mesh): { any }
	if not mesh or not mesh._handle then
		return {}
	end
	local animationCount = filament.lib.Kine_Filament_GetMeshAnimationCount(mesh._handle)
	local animations = table.create(math.max(animationCount, 0))
	for animationIndex = 0, animationCount - 1 do
		animations[animationIndex + 1] = {
			index = animationIndex,
			name = readCString(filament.lib.Kine_Filament_GetMeshAnimationName(mesh._handle, animationIndex), 1024),
			duration = filament.lib.Kine_Filament_GetMeshAnimationDuration(mesh._handle, animationIndex),
		}
	end
	return animations
end

local function writeCFrameMatrix(target, offset: number, cframe)
	local position = cframe.Position
	local rotation = cframe.Rotation
	target:writef32(offset, rotation[1][1])
	target:writef32(offset + 4, rotation[1][2])
	target:writef32(offset + 8, rotation[1][3])
	target:writef32(offset + 12, position.X)
	target:writef32(offset + 16, rotation[2][1])
	target:writef32(offset + 20, rotation[2][2])
	target:writef32(offset + 24, rotation[2][3])
	target:writef32(offset + 28, position.Y)
	target:writef32(offset + 32, rotation[3][1])
	target:writef32(offset + 36, rotation[3][2])
	target:writef32(offset + 40, rotation[3][3])
	target:writef32(offset + 44, position.Z)
	target:writef32(offset + 48, 0)
	target:writef32(offset + 52, 0)
	target:writef32(offset + 56, 0)
	target:writef32(offset + 60, 1)
end

function filamentAdapter:SetMeshBoneTransforms(window: typedefs.Window, mesh: typedefs.Mesh, transforms: { any }): boolean
	if not window._3dhandle or window._3dhandle == zune.ffi.null or not mesh or not mesh._handle then
		return false
	end
	local boneCount = #transforms
	if boneCount <= 0 then
		return false
	end
	local matrices = getRawBuffer(skinBuffers, mesh, boneCount * 16 * 4)
	for index = 1, boneCount do
		local transform = transforms[index]
		if not transform or not transform.Position or not transform.Rotation then
			return false
		end
		writeCFrameMatrix(matrices, (index - 1) * 16 * 4, transform)
	end
	return filament.lib.Kine_Filament_SetMeshBoneTransforms(
		window._3dhandle,
		mesh._handle,
		matrices,
		boneCount
	) ~= 0
end

function filamentAdapter:ApplyMeshAnimation(
	window: typedefs.Window,
	mesh: typedefs.Mesh,
	animation: string | number,
	timeSeconds: number,
	looped: boolean?
): boolean
	if not window._3dhandle or window._3dhandle == zune.ffi.null or not mesh or not mesh._handle then
		return false
	end
	local animationIndex = if type(animation) == "number" then math.floor(animation) - 1 else -1
	if type(animation) == "string" then
		local wanted = string.lower(animation:gsub("\\", "/"):match("([^/]+)$") or animation):gsub("%.[^%.]+$", "")
		for _, clip in ipairs(self:GetMeshAnimations(mesh)) do
			local candidate = string.lower(clip.name)
			if candidate == string.lower(animation) or candidate == wanted or candidate:gsub("%.[^%.]+$", "") == wanted then
				animationIndex = clip.index
				break
			end
		end
	end
	if animationIndex < 0 then
		return false
	end
	return filament.lib.Kine_Filament_ApplyMeshAnimation(
		window._3dhandle,
		mesh._handle,
		animationIndex,
		timeSeconds or 0,
		looped ~= false and 1 or 0
	) ~= 0
end

function filamentAdapter:CreateCustomMesh(
	window: typedefs.Window,
	vertexData: any,
	vertexCount: number,
	indices: any,
	indexCount: number
): typedefs.Mesh?
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return nil
	end
	local mesh =
		filament.lib.Kine_Filament_CreateCustomMesh(window._3dhandle, vertexData, vertexCount, indices, indexCount)
	if not mesh or mesh == zune.ffi.null then
		return nil
	end
	return { _handle = mesh, _window = window }
end

function filamentAdapter:CreateTerrainMesh(
	window: typedefs.Window,
	vertexData: any,
	materialWeights: any,
	vertexCount: number,
	indices: any,
	indexCount: number
): typedefs.Mesh?
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return nil
	end
	local mesh = filament.lib.Kine_Filament_CreateTerrainMesh(
		window._3dhandle,
		vertexData,
		materialWeights,
		vertexCount,
		indices,
		indexCount
	)
	if not mesh or mesh == zune.ffi.null then
		return nil
	end
	return { _handle = mesh, _window = window }
end

function filamentAdapter:DestroyMesh(window: typedefs.Window, mesh: typedefs.Mesh?)
	if not mesh or not mesh._handle or not window._3dhandle or window._3dhandle == zune.ffi.null then
		return
	end
	filament.lib.Kine_Filament_DestroyMesh(window._3dhandle, mesh._handle)
	mesh._handle = nil
end

function filamentAdapter:UpdateCustomMesh(
	window: typedefs.Window,
	mesh: typedefs.Mesh?,
	vertexData,
	vertexCount: number
)
	if not mesh or not mesh._handle or not window._3dhandle or window._3dhandle == zune.ffi.null then
		return false
	end
	return filament.lib.Kine_Filament_UpdateCustomMesh(window._3dhandle, mesh._handle, vertexData, vertexCount) ~= 0
end

function filamentAdapter:CreateGizmo(
	window: typedefs.Window,
	gizmoType: "move" | "rotate" | "scale" | "moveGizmo" | "rotateGizmo" | "scaleGizmo"
): typedefs.Gizmo?
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return nil
	end

	local map = {
		["move"] = filament.const.GizmoType.Move,
		["rotate"] = filament.const.GizmoType.Rotate,
		["scale"] = filament.const.GizmoType.Scale,
		["moveGizmo"] = filament.const.GizmoType.Move,
		["rotateGizmo"] = filament.const.GizmoType.Rotate,
		["scaleGizmo"] = filament.const.GizmoType.Scale,
	}

	local gizmo =
		filament.lib.Kine_Filament_CreateGizmo(window._3dhandle, map[gizmoType] or filament.const.GizmoType.Move)
	if not gizmo or gizmo == zune.ffi.null then
		return nil
	end
	return { _handle = gizmo }
end

function filamentAdapter:DestroyGizmo(window: typedefs.Window, gizmo: typedefs.Gizmo?)
	if not gizmo or not gizmo._handle or not window._3dhandle or window._3dhandle == zune.ffi.null then
		return
	end
	filament.lib.Kine_Filament_DestroyGizmo(window._3dhandle, gizmo._handle)
	gizmo._handle = nil
end

function filamentAdapter:DrawMesh(
	window: typedefs.Window,
	mesh: typedefs.Mesh,
	color: typedefs.RGBA,
	roughness: number,
	metallic: number,
	mat4: any,
	castshadow: boolean,
	receiveShadow: boolean,
	culling: boolean,
	texture: any,
	materialKind: number,
	materialTileScale: number?
)
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return
	end
	if not mesh or not mesh._handle then
		return
	end
	filament.lib.Kine_Filament_DrawMeshEx(
		window._3dhandle,
		mesh._handle,
		materialKind or 0,
		color.R,
		color.G,
		color.B,
		roughness,
		metallic,
		materialTileScale or 1,
		0,
		mat4,
		castshadow and 1 or 0,
		receiveShadow and 1 or 0,
		culling and 1 or 0,
		texture
	)
end

function filamentAdapter:DrawMeshList(
	window: typedefs.Window,
	drawCalls: { any },
	itemCount: number?,
	streamId: number?,
	version: number?
)
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return
	end

	local versioned = streamId ~= nil and version ~= nil
	local retainedStreamId = streamId or 0
	local retainedVersion = version or 0
	if versioned then
		local versions = drawListVersions[window]
		if versions and versions[retainedStreamId] == retainedVersion then
			filament.lib.Kine_Filament_DrawMeshListVersioned(
				window._3dhandle,
				zune.ffi.null,
				0,
				retainedStreamId,
				retainedVersion
			)
			return
		end
	end

	local requestedCount = math.min(itemCount or #drawCalls, #drawCalls)
	if requestedCount <= 0 then
		if versioned then
			filament.lib.Kine_Filament_DrawMeshListVersioned(
				window._3dhandle,
				zune.ffi.null,
				0,
				retainedStreamId,
				retainedVersion
			)
			local versions = drawListVersions[window] or {}
			versions[retainedStreamId] = retainedVersion
			drawListVersions[window] = versions
		end
		return
	end

	local items = getDrawListBuffer(window, requestedCount)
	local packedCount = 0
	for i = 1, requestedCount do
		local drawCall = drawCalls[i]
		local mesh = drawCall and drawCall.mesh
		local rawMatrix = drawCall and drawCall.matrix
		local cframe = drawCall and drawCall.cframe
		local scale = drawCall and drawCall.scale
		if type(rawMatrix) == "table" and rawMatrix.getraw then
			rawMatrix = rawMatrix:getraw()
		end

		if not mesh or not mesh._handle or (not rawMatrix and (not cframe or not scale)) then
			continue
		end

		local color = drawCall.color
		local base = packedCount * DRAW_ITEM_SIZE
		local flags = 0
		if drawCall.CastShadow ~= false then
			flags += DRAW_CAST_SHADOWS
		end
		if drawCall.RecieveShadow ~= false then
			flags += DRAW_RECEIVE_SHADOWS
		end
		if drawCall.Culling == true then
			flags += DRAW_CULLING
		end

		items:writeptr(base + drawItemOffsets.mesh, mesh._handle)
		items:writeptr(base + drawItemOffsets.tex, drawCall.texture or zune.ffi.null)
		local transformOffset = base + drawItemOffsets.transform
		if rawMatrix then
			items:write(transformOffset, rawMatrix, 0, 16 * 4)
		else
			local position = cframe.Position
			local rotation = cframe.Rotation
			items:writef32(transformOffset, rotation[1][1] * scale.X)
			items:writef32(transformOffset + 4, rotation[1][2] * scale.Y)
			items:writef32(transformOffset + 8, rotation[1][3] * scale.Z)
			items:writef32(transformOffset + 12, position.X)
			items:writef32(transformOffset + 16, rotation[2][1] * scale.X)
			items:writef32(transformOffset + 20, rotation[2][2] * scale.Y)
			items:writef32(transformOffset + 24, rotation[2][3] * scale.Z)
			items:writef32(transformOffset + 28, position.Y)
			items:writef32(transformOffset + 32, rotation[3][1] * scale.X)
			items:writef32(transformOffset + 36, rotation[3][2] * scale.Y)
			items:writef32(transformOffset + 40, rotation[3][3] * scale.Z)
			items:writef32(transformOffset + 44, position.Z)
			items:writef32(transformOffset + 48, 0)
			items:writef32(transformOffset + 52, 0)
			items:writef32(transformOffset + 56, 0)
			items:writef32(transformOffset + 60, 1)
		end
		items:writef32(base + drawItemOffsets.r, color.R)
		items:writef32(base + drawItemOffsets.g, color.G)
		items:writef32(base + drawItemOffsets.b, color.B)
		items:writef32(base + drawItemOffsets.param1, math.clamp(drawCall.roughness or 0.5, 0, 1))
		items:writef32(base + drawItemOffsets.param2, math.clamp(drawCall.metallic or 0, 0, 1))
		items:writef32(base + drawItemOffsets.param3, drawCall.MaterialTileScale or 1)
		items:writef32(base + drawItemOffsets.transmission, drawCall.transmission or 0)
		items:writei32(base + drawItemOffsets.materialKind, drawCall.MaterialKind or 0)
		items:writeu32(base + drawItemOffsets.flags, flags)
		items:writeu32(base + drawItemOffsets.reserved, 0)
		items:writeptr(base + drawItemOffsets.shader, drawCall.shader or zune.ffi.null)
		packedCount += 1
	end

	if versioned then
		filament.lib.Kine_Filament_DrawMeshListVersioned(
			window._3dhandle,
			if packedCount > 0 then items else zune.ffi.null,
			packedCount,
			retainedStreamId,
			retainedVersion
		)
		local versions = drawListVersions[window] or {}
		versions[retainedStreamId] = retainedVersion
		drawListVersions[window] = versions
	elseif packedCount > 0 then
		filament.lib.Kine_Filament_DrawMeshList(window._3dhandle, items, packedCount)
	end
end

function filamentAdapter:CreateInstanceBatch(window: typedefs.Window, drawCalls: { any }, itemCount: number?)
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return nil
	end

	local requestedCount = math.min(itemCount or #drawCalls, #drawCalls)
	if requestedCount <= 0 then
		return nil
	end

	local items = getDrawListBuffer(window, requestedCount)
	local packedCount = 0
	for i = 1, requestedCount do
		if writeDrawItem(items, packedCount, drawCalls[i]) then
			packedCount += 1
		end
	end
	if packedCount <= 0 then
		return nil
	end

	local batch = filament.lib.Kine_Filament_CreateInstanceBatch(window._3dhandle, items, packedCount)
	if not batch or batch == zune.ffi.null then
		return nil
	end
	return batch
end

function filamentAdapter:DestroyInstanceBatch(batch)
	if not batch or batch == zune.ffi.null then
		return
	end
	filament.lib.Kine_Filament_DestroyInstanceBatch(batch)
end

function filamentAdapter:UpdateInstanceTransforms(
	window: typedefs.Window,
	batch,
	updates: { any },
	updateCount: number?
)
	if not batch or batch == zune.ffi.null then
		return
	end

	local requestedCount = math.min(updateCount or #updates, #updates)
	if requestedCount <= 0 then
		return
	end

	local indices = getRawBuffer(indexBuffers, window, requestedCount * 4)
	local transforms = getRawBuffer(transformBuffers, window, requestedCount * 16 * 4)
	local dirtyCount = 0
	for i = 1, requestedCount do
		local update = updates[i]
		if update then
			local rawMatrix = update.matrix
			if type(rawMatrix) == "table" and rawMatrix.getraw then
				rawMatrix = rawMatrix:getraw()
			end

			local transformOffset = dirtyCount * 16 * 4
			if writeTransform(transforms, transformOffset, rawMatrix, update.cframe, update.scale) then
				indices:writeu32(dirtyCount * 4, update.index)
				dirtyCount += 1
			end
		end
	end

	if dirtyCount > 0 then
		filament.lib.Kine_Filament_UpdateInstanceTransforms(batch, indices, transforms, dirtyCount)
	end
end

function filamentAdapter:DrawParticles(
	window: typedefs.Window,
	texture,
	items,
	itemCount: number,
	uvScale: typedefs.Vector2?,
	uvOffset: typedefs.Vector2?,
	castShadows: boolean?,
	culling: boolean?
)
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return
	end
	if not items or itemCount <= 0 then
		return
	end

	filament.lib.Kine_Filament_DrawParticles(
		window._3dhandle,
		texture or zune.ffi.null,
		items,
		itemCount,
		uvScale and uvScale.X or 1,
		uvScale and uvScale.Y or 1,
		uvOffset and uvOffset.X or 0,
		uvOffset and uvOffset.Y or 0,
		castShadows and 1 or 0,
		culling and 1 or 0
	)
end

function filamentAdapter:DrawMeshOutline(
	window: typedefs.Window,
	mesh: typedefs.Mesh,
	color: typedefs.RGBA,
	thickness: number,
	mat4: any
)
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return
	end
	if not mesh or not mesh._handle then
		return
	end
	filament.lib.Kine_Filament_DrawMeshOutline(
		window._3dhandle,
		mesh._handle,
		color.R,
		color.G,
		color.B,
		thickness,
		mat4
	)
end

function filamentAdapter:DrawGizmo(
	window: typedefs.Window,
	gizmo: typedefs.Gizmo,
	mat4: any,
	hoveredAxis: number?,
	selectedAxis: number?
)
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		return
	end
	if not gizmo or not gizmo._handle then
		return
	end
	filament.lib.Kine_Filament_DrawGizmo(
		window._3dhandle,
		gizmo._handle,
		mat4,
		hoveredAxis or filament.const.GizmoAxis.None,
		selectedAxis or filament.const.GizmoAxis.None
	)
end

function filamentAdapter:PickGizmo(
	window: typedefs.Window,
	gizmo: typedefs.Gizmo,
	mat4,
	screenX: number,
	screenY: number
)
	if not window._3dhandle or window._3dhandle == zune.ffi.null or not gizmo or not gizmo._handle then
		return filament.const.GizmoAxis.None
	end
	return filament.lib.Kine_Filament_PickGizmo(window._3dhandle, gizmo._handle, mat4, screenX, screenY)
end

function filamentAdapter:GetGizmoDragDelta(
	window: typedefs.Window,
	gizmo: typedefs.Gizmo,
	mat4,
	axis: number,
	startX: number,
	startY: number,
	currentX: number,
	currentY: number
)
	if not window._3dhandle or window._3dhandle == zune.ffi.null or not gizmo or not gizmo._handle then
		return 0
	end
	return filament.lib.Kine_Filament_GetGizmoDragDelta(
		window._3dhandle,
		gizmo._handle,
		mat4,
		axis,
		startX,
		startY,
		currentX,
		currentY
	)
end

function filamentAdapter:SetSkyAtmosphere(
	window: typedefs.Window,
	direction: typedefs.Vector3,
	skyZenith: typedefs.RGBA,
	horizonColor: typedefs.RGBA,
	groundColor: typedefs.RGBA,
	sunlightIntensity: number
)
	filament.lib.Kine_Filament_SetSkyAtmosphere(
		window._3dhandle,
		direction.X,
		direction.Y,
		direction.Z, -- sunDirX, Y, Z

		skyZenith.R,
		skyZenith.G,
		skyZenith.B, -- sky zenith color

		horizonColor.R,
		horizonColor.G,
		horizonColor.B, -- horizon color

		groundColor.R,
		groundColor.G,
		groundColor.B, -- ground color

		sunlightIntensity -- sun light intensity (lux)
	)
end

local qualityLevels = {
	low = 0,
	medium = 1,
	high = 2,
	ultra = 3,
}

local shadowTypes = {
	pcf = 0,
	vsm = 1,
	dpcf = 2,
	pcss = 3,
}

local function getQuality(value, fallback: number): number
	if type(value) == "string" then
		return qualityLevels[string.lower(value)] or fallback
	end
	if type(value) == "number" then
		return value
	end
	return fallback
end

local function hasFilamentHandle(window: typedefs.Window): boolean
	return window._3dhandle ~= nil and window._3dhandle ~= zune.ffi.null
end

function filamentAdapter:SetPostProcessing(window: typedefs.Window, enabled: boolean)
	if not hasFilamentHandle(window) then
		return
	end
	filament.lib.Kine_Filament_SetPostProcessing(window._3dhandle, enabled)
end

function filamentAdapter:SetBloom(window: typedefs.Window, enabled: boolean, options: any?)
	if not hasFilamentHandle(window) then
		return
	end
	options = options or {}
	filament.lib.Kine_Filament_SetBloom(
		window._3dhandle,
		enabled,
		options.Strength or options.strength or 0.12,
		options.Resolution or options.resolution or 384,
		options.Levels or options.levels or 6,
		if options.Threshold ~= nil
			then options.Threshold
			else if options.threshold ~= nil then options.threshold else true,
		options.LensFlare or options.lensFlare or false
	)
end

function filamentAdapter:SetAmbientOcclusion(window: typedefs.Window, enabled: boolean, options: any?)
	if not hasFilamentHandle(window) then
		return
	end
	options = options or {}
	local aoType = if options.Type == "gtao" or options.type == "gtao" then 1 else 0
	filament.lib.Kine_Filament_SetAmbientOcclusion(
		window._3dhandle,
		enabled,
		options.Radius or options.radius or 0.35,
		options.Power or options.power or 1,
		options.Intensity or options.intensity or 1,
		getQuality(options.Quality or options.quality, 1),
		aoType
	)
end

function filamentAdapter:SetAntiAliasing(window: typedefs.Window, options: any?)
	if not hasFilamentHandle(window) then
		return
	end
	options = options or {}
	filament.lib.Kine_Filament_SetAntiAliasing(
		window._3dhandle,
		if options.FXAA ~= nil then options.FXAA else if options.fxaa ~= nil then options.fxaa else true,
		options.TAA or options.taa or false,
		options.MSAA or options.msaa or false,
		options.SampleCount or options.sampleCount or 4
	)
end

function filamentAdapter:SetDynamicResolution(window: typedefs.Window, enabled: boolean, options: any?)
	if not hasFilamentHandle(window) then
		return
	end
	options = options or {}
	filament.lib.Kine_Filament_SetDynamicResolution(
		window._3dhandle,
		enabled,
		options.MinScale or options.minScale or 0.75,
		options.MaxScale or options.maxScale or 1,
		getQuality(options.Quality or options.quality, 1),
		options.Sharpness or options.sharpness or 0.9
	)
end

function filamentAdapter:SetDepthOfField(window: typedefs.Window, enabled: boolean, options: any?)
	if not hasFilamentHandle(window) then
		return
	end
	options = options or {}
	if options.FocusDistance or options.focusDistance then
		filament.lib.Kine_Filament_SetFocusDistance(window._3dhandle, options.FocusDistance or options.focusDistance)
	end
	filament.lib.Kine_Filament_SetDepthOfField(
		window._3dhandle,
		enabled,
		options.CocScale or options.cocScale or 1,
		options.CocAspectRatio or options.cocAspectRatio or 1,
		options.MaxApertureDiameter or options.maxApertureDiameter or 0.01,
		options.MaxForegroundCOC or options.maxForegroundCOC or 0,
		options.MaxBackgroundCOC or options.maxBackgroundCOC or 0
	)
end

function filamentAdapter:SetVignette(window: typedefs.Window, enabled: boolean, options: any?)
	if not hasFilamentHandle(window) then
		return
	end
	options = options or {}
	local color = options.Color or options.color or { R = 0, G = 0, B = 0, A = 1 }
	filament.lib.Kine_Filament_SetVignette(
		window._3dhandle,
		enabled,
		options.MidPoint or options.midPoint or 0.5,
		options.Roundness or options.roundness or 0.5,
		options.Feather or options.feather or 0.5,
		color.R or color.r or 0,
		color.G or color.g or 0,
		color.B or color.b or 0,
		color.A or color.a or 1
	)
end

function filamentAdapter:SetScreenSpaceReflections(window: typedefs.Window, enabled: boolean, options: any?)
	if not hasFilamentHandle(window) then
		return
	end
	options = options or {}
	filament.lib.Kine_Filament_SetScreenSpaceReflections(
		window._3dhandle,
		enabled,
		options.Thickness or options.thickness or 0.1,
		options.Bias or options.bias or 0.01,
		options.MaxDistance or options.maxDistance or 3,
		options.Stride or options.stride or 2
	)
end

function filamentAdapter:SetColorGrading(window: typedefs.Window, options: any?)
	if not hasFilamentHandle(window) then
		return
	end
	options = options or {}
	if options.Enabled == false or options.enabled == false then
		filament.lib.Kine_Filament_ClearColorGrading(window._3dhandle)
		return
	end
	filament.lib.Kine_Filament_SetColorGrading(
		window._3dhandle,
		options.Exposure or options.exposure or 0,
		options.Contrast or options.contrast or 1,
		options.Saturation or options.saturation or 1,
		options.Vibrance or options.vibrance or 1,
		options.Temperature or options.temperature or 0,
		options.Tint or options.tint or 0
	)
end

function filamentAdapter:SetRenderQuality(window: typedefs.Window, quality: string | number)
	if not hasFilamentHandle(window) then
		return
	end
	filament.lib.Kine_Filament_SetRenderQuality(window._3dhandle, getQuality(quality, 2))
end

function filamentAdapter:SetDithering(window: typedefs.Window, enabled: boolean)
	if not hasFilamentHandle(window) then
		return
	end
	filament.lib.Kine_Filament_SetDithering(window._3dhandle, enabled)
end

function filamentAdapter:SetShadowOptions(window: typedefs.Window, enabled: boolean, shadowType: string | number?)
	if not hasFilamentHandle(window) then
		return
	end
	local resolvedType = 0
	if type(shadowType) == "string" then
		resolvedType = shadowTypes[string.lower(shadowType)] or 0
	elseif type(shadowType) == "number" then
		resolvedType = shadowType
	end
	filament.lib.Kine_Filament_SetShadowOptions(window._3dhandle, enabled, resolvedType)
end

function filamentAdapter:SetSunShadowOptions(window: typedefs.Window, options: any?)
	if not hasFilamentHandle(window) then
		return
	end
	options = options or {}
	filament.lib.Kine_Filament_SetSunShadowOptions(
		window._3dhandle,
		options.MapSize or options.mapSize or 4096,
		options.Cascades or options.cascades or 4,
		options.ShadowFar or options.shadowFar or 0,
		options.ShadowNearHint or options.shadowNearHint or 0.5,
		options.ShadowFarHint or options.shadowFarHint or 160,
		if options.Stable ~= nil then options.Stable else if options.stable ~= nil then options.stable else true,
		if options.ContactShadows ~= nil
			then options.ContactShadows
			else if options.contactShadows ~= nil then options.contactShadows else true
	)
end

function filamentAdapter:SetSunRays(window: typedefs.Window, enabled: boolean, options: any?)
	if not hasFilamentHandle(window) then
		return
	end
	options = options or {}
	local color = options.Color or options.color or { R = 0.78, G = 0.84, B = 0.93 }
	filament.lib.Kine_Filament_SetSunRays(
		window._3dhandle,
		enabled,
		options.Distance or options.distance or 4,
		options.CutOffDistance or options.cutOffDistance or 1000,
		options.MaximumOpacity or options.maximumOpacity or 0.6,
		options.Height or options.height or 0,
		options.HeightFalloff or options.heightFalloff or 0.018,
		options.Density or options.density or 0.014,
		options.InScatteringStart or options.inScatteringStart or 0,
		options.InScatteringSize or options.inScatteringSize or 32,
		color.R or color.r or 0.78,
		color.G or color.g or 0.84,
		color.B or color.b or 0.93,
		if options.FogColorFromIbl ~= nil
			then options.FogColorFromIbl
			else if options.fogColorFromIbl ~= nil then options.fogColorFromIbl else false
	)
end

function filamentAdapter:ConfigurePostProcessing(window: typedefs.Window, options: any?)
	if not hasFilamentHandle(window) then
		return
	end
	options = options or {}

	if options.Enabled ~= nil or options.enabled ~= nil then
		self:SetPostProcessing(window, if options.Enabled ~= nil then options.Enabled else options.enabled)
	end
	if options.Bloom ~= nil or options.bloom ~= nil then
		self:SetBloom(
			window,
			if options.Bloom ~= nil then options.Bloom else options.bloom,
			options.BloomOptions or options.bloomOptions
		)
	end
	if options.AmbientOcclusion ~= nil or options.ambientOcclusion ~= nil then
		self:SetAmbientOcclusion(
			window,
			if options.AmbientOcclusion ~= nil then options.AmbientOcclusion else options.ambientOcclusion,
			options.AmbientOcclusionOptions or options.ambientOcclusionOptions
		)
	end
	if options.AntiAliasing or options.antiAliasing then
		self:SetAntiAliasing(window, options.AntiAliasing or options.antiAliasing)
	end
	if options.DynamicResolution ~= nil or options.dynamicResolution ~= nil then
		self:SetDynamicResolution(
			window,
			if options.DynamicResolution ~= nil then options.DynamicResolution else options.dynamicResolution,
			options.DynamicResolutionOptions or options.dynamicResolutionOptions
		)
	end
	if options.DepthOfField ~= nil or options.depthOfField ~= nil then
		self:SetDepthOfField(
			window,
			if options.DepthOfField ~= nil then options.DepthOfField else options.depthOfField,
			options.DepthOfFieldOptions or options.depthOfFieldOptions
		)
	end
	if options.Vignette ~= nil or options.vignette ~= nil then
		self:SetVignette(
			window,
			if options.Vignette ~= nil then options.Vignette else options.vignette,
			options.VignetteOptions or options.vignetteOptions
		)
	end
	if options.ScreenSpaceReflections ~= nil or options.screenSpaceReflections ~= nil then
		self:SetScreenSpaceReflections(
			window,
			if options.ScreenSpaceReflections ~= nil
				then options.ScreenSpaceReflections
				else options.screenSpaceReflections,
			options.ScreenSpaceReflectionsOptions or options.screenSpaceReflectionsOptions
		)
	end
	if options.ColorGrading or options.colorGrading then
		self:SetColorGrading(window, options.ColorGrading or options.colorGrading)
	end
	if options.RenderQuality or options.renderQuality then
		self:SetRenderQuality(window, options.RenderQuality or options.renderQuality)
	end
	if options.Dithering ~= nil or options.dithering ~= nil then
		self:SetDithering(window, if options.Dithering ~= nil then options.Dithering else options.dithering)
	end
	if options.Shadows ~= nil or options.shadows ~= nil then
		self:SetShadowOptions(
			window,
			if options.Shadows ~= nil then options.Shadows else options.shadows,
			options.ShadowType or options.shadowType
		)
	end
	if options.SunShadows or options.sunShadows then
		self:SetSunShadowOptions(window, options.SunShadows or options.sunShadows)
	end
	if options.SunRays ~= nil or options.sunRays ~= nil then
		self:SetSunRays(
			window,
			if options.SunRays ~= nil then options.SunRays else options.sunRays,
			options.SunRaysOptions or options.sunRaysOptions
		)
	end
end

function filamentAdapter:SetPostProcessingPreset(window: typedefs.Window, preset: string)
	local key = string.lower(preset)

	if key == "off" then
		self:ConfigurePostProcessing(window, {
			Enabled = false,

			Bloom = false,
			AmbientOcclusion = false,
			DepthOfField = false,
			Vignette = false,
			ScreenSpaceReflections = false,
			SunRays = false,
			Shadows = false,

			ColorGrading = {
				Enabled = false,
			},
		})
	elseif key == "low" then
		self:ConfigurePostProcessing(window, {
			Enabled = true,

			Bloom = false,

			AmbientOcclusion = true,
			AmbientOcclusionOptions = {
				Quality = "low",
				Radius = 0.3,
				Intensity = 0.7,
			},

			AntiAliasing = {
				FXAA = true,
				TAA = false,
				MSAA = false,
			},

			RenderQuality = "medium",
			Dithering = true,

			SunRays = false,

			Shadows = true,
			ShadowType = "pcf",

			SunShadows = {
				MapSize = 1024,
				Cascades = 2,
				ShadowFarHint = 100,
				Stable = true,
				ContactShadows = false,
			},
		})
	elseif key == "medium" then
		self:ConfigurePostProcessing(window, {
			Enabled = true,

			Bloom = true,
			BloomOptions = {
				Strength = 0.12,
				Resolution = 384,
				Levels = 6,
				Threshold = true,
			},

			AmbientOcclusion = true,
			AmbientOcclusionOptions = {
				Type = "gtao",
				Quality = "medium",
				Radius = 0.4,
				Power = 1.1,
				Intensity = 1,
			},

			AntiAliasing = {
				FXAA = true,
				TAA = true,
				MSAA = false,
			},

			Vignette = false,

			ColorGrading = {
				Enabled = true,
				Exposure = 0,
				Contrast = 1,
				Saturation = 1,
				Vibrance = 1,
			},

			RenderQuality = "high",
			Dithering = true,

			SunRays = true,
			SunRaysOptions = {
				Density = 0.014,
				MaximumOpacity = 0.58,
				InScatteringSize = 34,
			},

			Shadows = true,
			ShadowType = "pcf",

			SunShadows = {
				MapSize = 2048,
				Cascades = 3,
				ShadowFarHint = 140,
				Stable = true,
				ContactShadows = true,
			},
		})
	elseif key == "high" then
		self:ConfigurePostProcessing(window, {
			Enabled = true,

			Bloom = true,
			BloomOptions = {
				Strength = 0.18,
				Resolution = 512,
				Levels = 7,
				Threshold = true,
				LensFlare = true,
			},

			AmbientOcclusion = true,
			AmbientOcclusionOptions = {
				Type = "gtao",
				Quality = "high",
				Radius = 0.55,
				Power = 1.35,
				Intensity = 1.15,
			},

			AntiAliasing = {
				FXAA = true,
				TAA = true,
				MSAA = true,
				SampleCount = 4,
			},

			Vignette = false,

			ColorGrading = {
				Enabled = true,
				Exposure = 0,
				Contrast = 1.08,
				Saturation = 1.05,
				Vibrance = 1.08,
			},

			RenderQuality = "high",
			Dithering = true,

			SunRays = true,
			SunRaysOptions = {
				Density = 0.018,
				MaximumOpacity = 0.68,
				InScatteringSize = 28,
			},

			Shadows = true,
			ShadowType = "pcss",

			SunShadows = {
				MapSize = 4096,
				Cascades = 4,
				ShadowFarHint = 180,
				Stable = true,
				ContactShadows = true,
			},
		})
	else
		warn(`Unknown post-processing preset "{preset}", defaulting to Medium`)
		self:SetPostProcessingPreset(window, "medium")
	end
end

function filamentAdapter:GetPixels(window: typedefs.Window)
	if window.WGI == "vulkan" then
		return nil
	end
	if not filamentPixelsPtr then
		filamentPixelsPtr = zune.ffi.alloc(window.Width * window.Height * 4)
	end
	filament.lib.Kine_Filament_ReadPixels(window._3dhandle, filamentPixelsPtr)
	return filamentPixelsPtr
end

return filamentAdapter
