-- Filament adapter
local filament = require("./filament")
local filamentAdapter = {}
local typedefs = require("../../typedefs")

local filamentPixelsPtr = nil

function filamentAdapter:Init(window: typedefs.Window)
	filamentPixelsPtr = zune.ffi.alloc(window.Width * window.Height * 4)

	window._3dhandle = filament.lib.Kine_Filament_Create(window.Width, window.Height)
	filament.lib.Kine_Filament_CreateSky(window._3dhandle, 102 / 255, 191 / 255, 255 / 255, 1)
end

function filamentAdapter:SetCameraPosition(window: typedefs.Window, position: typedefs.Vector3)
	local handle = window._3dhandle
	filament.lib.Kine_Filament_SetCameraPosition(handle, position.X, position.Y, position.Z)
end

function filamentAdapter:SetCameraLookAt(window: typedefs.Window, position: typedefs.Vector3, target: typedefs.Vector3)
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
	filament.lib.Kine_Filament_Resize(handle, width, height)
end

function filamentAdapter:Render3D(window: typedefs.Window, dt: number)
	local handle = window._3dhandle
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

function filamentAdapter:CreateMesh(window: typedefs.Window, meshType: "cube" | "sphere" | "pyramid"): typedefs.Mesh
	local map = {
		["cube"] = 1,
		["sphere"] = 2,
		["pyramid"] = 3,
	}

	return { _handle = filament.lib.Kine_Filament_CreateMesh(window._3dhandle, map[meshType]) }
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
	if not filamentPixelsPtr then
		filamentPixelsPtr = zune.ffi.alloc(window.Width * window.Height * 4)
	end
	filament.lib.Kine_Filament_ReadPixels(window._3dhandle, filamentPixelsPtr)
	return filamentPixelsPtr
end

return filamentAdapter
