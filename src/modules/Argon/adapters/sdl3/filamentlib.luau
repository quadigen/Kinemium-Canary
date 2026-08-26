-- Filament adapter
local filament = require("./filament")
local filamentAdapter = {}
local typedefs = require("../../typedefs")

local filamentPixelsPtr = nil
local DrawItem = filament.structs.KineFilamentDrawItem
local DRAW_ITEM_SIZE = DrawItem:size()
local DRAW_CAST_SHADOWS = 1
local DRAW_RECEIVE_SHADOWS = 2
local DRAW_CULLING = 4
local drawListBuffers: { [any]: any } = setmetatable({}, { __mode = "k" })
local drawListVersions: { [any]: { [number]: number } } = setmetatable({}, { __mode = "k" })

assert(DRAW_ITEM_SIZE == 120, "KineFilamentDrawItem ABI mismatch")

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

function filamentAdapter:Init(window: typedefs.Window)
	filamentPixelsPtr = zune.ffi.alloc(window.Width * window.Height * 4)

	if window.WGI == "vulkan" then
		window._3dhandle = filament.lib.Kine_Filament_CreateForVulkanCompositorWindow(
			window._handle,
			window.Width,
			window.Height
		)
	else
		window._3dhandle = filament.lib.Kine_Filament_Create(window.Width, window.Height)
	end
	if not window._3dhandle or window._3dhandle == zune.ffi.null then
		print("Filament context creation failed.")
		return
	end
	filament.lib.Kine_Filament_CreateSky(window._3dhandle, 102 / 255, 191 / 255, 255 / 255, 1)
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
		false
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
		if compositor then
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

function filamentAdapter:Destroy3DTexture(window: typedefs.Window, texture: FFIPointerType?)
	if not texture then
		return
	end
	filament.lib.Kine_Filament_DestroyTex(window._3dhandle, texture)
end

function filamentAdapter:CreateMaterialTextureFromImages(
	window: typedefs.Window,
	albedo: typedefs.Image,
	normal: typedefs.Image?,
	orm: typedefs.Image?
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
		orm and orm.pixels or nil
	)
end

function filamentAdapter:CreateMesh(
	window: typedefs.Window,
	meshType: "cube" | "sphere" | "pyramid" | "moveGizmo" | "rotateGizmo" | "scaleGizmo"
): typedefs.Mesh
	local map = {
		["cube"] = 1,
		["sphere"] = 2,
		["pyramid"] = 3,
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
	local mesh = filament.lib.Kine_Filament_CreateCustomMesh(
		window._3dhandle,
		vertexData,
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

function filamentAdapter:UpdateCustomMesh(window: typedefs.Window, mesh: typedefs.Mesh?, vertexData, vertexCount: number)
	if
		not mesh
		or not mesh._handle
		or not window._3dhandle
		or window._3dhandle == zune.ffi.null
	then
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

	local gizmo = filament.lib.Kine_Filament_CreateGizmo(window._3dhandle, map[gizmoType] or filament.const.GizmoType.Move)
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
