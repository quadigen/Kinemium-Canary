--!strict
local ffi = zune.ffi

-- Type aliases for FFI
type int = number
type float = number
type double = number
type uint = number
type bool = number
type FFIPointer = typeof(ffi.types.pointer)

local KineMaterialKind = {
	Default = 0,
	Glass = 1,
	Neon = 2,
	Water = 3,
	Outline = 4,
	Gizmo = 5,
	Particle = 6,
	Terrain = 7,
}

export type Fns = {
	-- Context lifecycle
	Kine_Filament_Create: (width: int, height: int) -> FFIPointer,
	Kine_Filament_CreateForSDLWindow: (sdlWindow: FFIPointer, width: int, height: int) -> FFIPointer,
	Kine_Filament_CreateForVulkanCompositor: (vulkanCompositor: FFIPointer, width: int, height: int) -> FFIPointer,
	Kine_Filament_CreateForVulkanCompositorWindow: (sdlWindow: FFIPointer, width: int, height: int) -> FFIPointer,
	Kine_Filament_GetVulkanCompositor: (ctx: FFIPointer) -> FFIPointer,
	Kine_Filament_Destroy: (ctx: FFIPointer) -> (),
	Kine_Filament_RenderFrame: (ctx: FFIPointer, deltaTime: float) -> (),
	Kine_Filament_Resize: (ctx: FFIPointer, width: int, height: int) -> (),
	Kine_Filament_SetViewport: (ctx: FFIPointer, x: int, y: int, width: int, height: int) -> (),
	Kine_Filament_ReadPixels: (ctx: FFIPointer, outPixels: FFIPointer) -> (),
	Kine_Filament_GetWidth: (ctx: FFIPointer) -> int,
	Kine_Filament_GetHeight: (ctx: FFIPointer) -> int,
	Kine_Filament_GetColorTextureId: (ctx: FFIPointer) -> uint,
	Kine_Filament_GetVulkanBackend: (ctx: FFIPointer, outBackend: FFIPointer) -> bool,
	Kine_Filament_DebugPrintPixel: (ctx: FFIPointer) -> (),

	Kine_Filament_CreateSky: (ctx: FFIPointer, r: float, g: float, b: float, a: float) -> (),
	Kine_Filament_SetPostProcessing: (ctx: FFIPointer, enabled: bool) -> (),
	Kine_Filament_SetBloom: (
		ctx: FFIPointer,
		enabled: bool,
		strength: float,
		resolution: int,
		levels: int,
		threshold: bool,
		lensFlare: bool
	) -> (),
	Kine_Filament_SetAmbientOcclusion: (
		ctx: FFIPointer,
		enabled: bool,
		radius: float,
		power: float,
		intensity: float,
		quality: int,
		aoType: int
	) -> (),
	Kine_Filament_SetAntiAliasing: (
		ctx: FFIPointer,
		fxaa: bool,
		taa: bool,
		msaa: bool,
		sampleCount: int
	) -> (),
	Kine_Filament_SetDynamicResolution: (
		ctx: FFIPointer,
		enabled: bool,
		minScale: float,
		maxScale: float,
		quality: int,
		sharpness: float
	) -> (),
	Kine_Filament_SetDepthOfField: (
		ctx: FFIPointer,
		enabled: bool,
		cocScale: float,
		cocAspectRatio: float,
		maxApertureDiameter: float,
		maxForegroundCOC: int,
		maxBackgroundCOC: int
	) -> (),
	Kine_Filament_SetFocusDistance: (ctx: FFIPointer, distance: float) -> (),
	Kine_Filament_SetVignette: (
		ctx: FFIPointer,
		enabled: bool,
		midPoint: float,
		roundness: float,
		feather: float,
		r: float,
		g: float,
		b: float,
		a: float
	) -> (),
	Kine_Filament_SetScreenSpaceReflections: (
		ctx: FFIPointer,
		enabled: bool,
		thickness: float,
		bias: float,
		maxDistance: float,
		stride: float
	) -> (),
	Kine_Filament_SetColorGrading: (
		ctx: FFIPointer,
		exposure: float,
		contrast: float,
		saturation: float,
		vibrance: float,
		temperature: float,
		tint: float
	) -> (),
	Kine_Filament_ClearColorGrading: (ctx: FFIPointer) -> (),
	Kine_Filament_SetRenderQuality: (ctx: FFIPointer, hdrQuality: int) -> (),
	Kine_Filament_SetDithering: (ctx: FFIPointer, enabled: bool) -> (),
	Kine_Filament_SetShadowOptions: (ctx: FFIPointer, enabled: bool, shadowType: int) -> (),
	Kine_Filament_SetSunShadowOptions: (
		ctx: FFIPointer,
		mapSize: int,
		cascades: int,
		shadowFar: float,
		shadowNearHint: float,
		shadowFarHint: float,
		stable: bool,
		contactShadows: bool
	) -> (),
	Kine_Filament_SetSunRays: (
		ctx: FFIPointer,
		enabled: bool,
		distance: float,
		cutOffDistance: float,
		maximumOpacity: float,
		height: float,
		heightFalloff: float,
		density: float,
		inScatteringStart: float,
		inScatteringSize: float,
		r: float,
		g: float,
		b: float,
		fogColorFromIbl: bool
	) -> (),

	Kine_Filament_SetSkyAtmosphere: (
		ctx: FFIPointer,
		sunDirX: float,
		sunDirY: float,
		sunDirZ: float,
		skyR: float,
		skyG: float,
		skyB: float,
		horizonR: float,
		horizonG: float,
		horizonB: float,
		groundR: float,
		groundG: float,
		groundB: float,
		sunIntensity: float
	) -> (),

	Kine_Filament_CreateSkyboxCubemap: (
		ctx: FFIPointer,
		texPosX: FFIPointer,
		texNegX: FFIPointer,
		texPosY: FFIPointer,
		texNegY: FFIPointer,
		texPosZ: FFIPointer,
		texNegZ: FFIPointer
	) -> (),

	Kine_Filament_SetSun: (
		ctx: FFIPointer,
		sunDirX: float,
		sunDirY: float,
		sunDirZ: float,
		sunIntensity: float
	) -> (),

	-- Scene accessors
	Kine_Filament_GetEngine: (ctx: FFIPointer) -> FFIPointer,
	Kine_Filament_GetScene: (ctx: FFIPointer) -> FFIPointer,
	Kine_Filament_GetView: (ctx: FFIPointer) -> FFIPointer,
	Kine_Filament_GetCamera: (ctx: FFIPointer) -> FFIPointer,

	-- Camera controls
	Kine_Filament_SetCameraLookAt: (
		ctx: FFIPointer,
		eyeX: float,
		eyeY: float,
		eyeZ: float,
		targetX: float,
		targetY: float,
		targetZ: float,
		upX: float,
		upY: float,
		upZ: float
	) -> (),
	Kine_Filament_SetCameraPosition: (ctx: FFIPointer, x: float, y: float, z: float) -> (),
	Kine_Filament_SetCameraDirection: (ctx: FFIPointer, dx: float, dy: float, dz: float) -> (),
	Kine_Filament_SetCameraPerspective: (
		ctx: FFIPointer,
		fovYDegrees: double,
		aspect: double,
		nearPlane: double,
		farPlane: double
	) -> (),

	-- Mesh system
	-- shape: 1 = cube, 2 = sphere, 3 = pyramid, 10 = move gizmo, 11 = rotate gizmo, 12 = scale gizmo
	Kine_Filament_CreateMesh: (ctx: FFIPointer, shape: int) -> FFIPointer,
	Kine_Filament_CreateMeshFromPath: (ctx: FFIPointer, path: cstring) -> FFIPointer,
	Kine_Filament_DestroyMesh: (ctx: FFIPointer, mesh: FFIPointer) -> (),
	Kine_Filament_CreateGizmo: (ctx: FFIPointer, gizmoType: int) -> FFIPointer,
	Kine_Filament_DestroyGizmo: (ctx: FFIPointer, gizmo: FFIPointer) -> (),

	-- Custom mesh: interleaved vertexData is px,py,pz,nx,ny,nz,u,v (8 floats/vertex)
	Kine_Filament_CreateCustomMesh: (
		ctx: FFIPointer,
		vertexData: FFIPointer,
		vertexCount: int,
		indices: FFIPointer,
		indexCount: int
	) -> FFIPointer,
	Kine_Filament_CreateTerrainMesh: (
		ctx: FFIPointer,
		vertexData: FFIPointer,
		materialWeights: FFIPointer,
		vertexCount: int,
		indices: FFIPointer,
		indexCount: int
	) -> FFIPointer,
	Kine_Filament_UpdateCustomMesh: (
		ctx: FFIPointer,
		mesh: FFIPointer,
		vertexData: FFIPointer,
		vertexCount: int
	) -> bool,

	-- Texture system
	-- glTexture: pointer to KineGLTextureInfo { id, width, height, mipmaps, format }
	Kine_Filament_CreateTex: (ctx: FFIPointer, glTexture: FFIPointer) -> FFIPointer,
	Kine_Filament_UpdateTexFromPixels: (
		ctx: FFIPointer,
		tex: FFIPointer,
		width: int,
		height: int,
		rowBytes: int,
		pixelsRGBA8: FFIPointer
	) -> bool,
	Kine_Filament_CreateTerrainTextureSet: (
		ctx: FFIPointer,
		layer0: FFIPointer,
		layer1: FFIPointer,
		layer2: FFIPointer,
		layer3: FFIPointer,
		layer4: FFIPointer,
		layer5: FFIPointer
	) -> FFIPointer,
	Kine_Filament_DestroyTex: (ctx: FFIPointer, tex: FFIPointer) -> (),

	-- Draw call (queued this frame, batched+instanced internally)
	-- materialKind: 0=default, 1=glass, 2=neon, 3=water, 7=terrain
	-- param1/param2/param3: roughness/ior/thickness (glass/water), intensity/unused/unused (neon)
	-- transmission: glass/water only
	-- mat4: pointer to float[16] column-major world transform
	-- tex: optional KineFilamentTex* (nil for no texture)
	Kine_Filament_DrawMeshEx: (
		ctx: FFIPointer,
		mesh: FFIPointer,
		materialKind: int,
		r: float,
		g: float,
		b: float,
		param1: float,
		param2: float,
		param3: float,
		transmission: float,
		mat4: FFIPointer,
		castshadow: bool,
		receiveShadow: bool,
		culling: bool,
		tex: FFIPointer?
	) -> (),
	Kine_Filament_DrawMeshList: (ctx: FFIPointer, items: FFIPointer, itemCount: uint) -> (),
	Kine_Filament_DrawMeshListVersioned: (
		ctx: FFIPointer,
		items: FFIPointer,
		itemCount: uint,
		streamId: number,
		version: number
	) -> (),
	Kine_Filament_CreateInstanceBatch: (
		ctx: FFIPointer,
		items: FFIPointer,
		itemCount: uint
	) -> FFIPointer,
	Kine_Filament_DestroyInstanceBatch: (batch: FFIPointer) -> (),
	Kine_Filament_UpdateInstanceTransforms: (
		batch: FFIPointer,
		indices: FFIPointer,
		transforms: FFIPointer,
		dirtyCount: uint
	) -> (),
	Kine_Filament_DrawParticles: (
		ctx: FFIPointer,
		texture: FFIPointer?,
		items: FFIPointer,
		itemCount: uint,
		uvScaleX: float,
		uvScaleY: float,
		uvOffsetX: float,
		uvOffsetY: float,
		castShadows: bool,
		culling: bool
	) -> (),
	Kine_Filament_DrawMeshOutline: (
		ctx: FFIPointer,
		mesh: FFIPointer,
		r: float,
		g: float,
		b: float,
		thickness: float,
		mat4: FFIPointer
	) -> (),
	Kine_Filament_DrawGizmo: (
		ctx: FFIPointer,
		gizmo: FFIPointer,
		mat4: FFIPointer,
		hoveredAxis: int,
		selectedAxis: int
	) -> (),
	Kine_Filament_PickGizmo: (
		ctx: FFIPointer,
		gizmo: FFIPointer,
		mat4: FFIPointer,
		screenX: float,
		screenY: float
	) -> int,
	Kine_Filament_GetGizmoDragDelta: (
		ctx: FFIPointer,
		gizmo: FFIPointer,
		mat4: FFIPointer,
		axis: int,
		startX: float,
		startY: float,
		currentX: float,
		currentY: float
	) -> float,

	-- Point light management. Returns an opaque int light ID, or -1 on failure.
	-- position/color are passed as three separate floats (x, y, z).
	Kine_Filament_CreateLight: (
		ctx: FFIPointer,
		px: float,
		py: float,
		pz: float,
		cr: float,
		cg: float,
		cb: float,
		intensity: float,
		falloff: float
	) -> int,
	Kine_Filament_SetColorLight: (ctx: FFIPointer, light: int, r: float, g: float, b: float) -> (),
	Kine_Filament_SetIntensityLight: (ctx: FFIPointer, light: int, intensity: float) -> (),
	Kine_Filament_SetFalloffLight: (ctx: FFIPointer, light: int, falloff: float) -> (),
	Kine_Filament_SetPositionLight: (ctx: FFIPointer, light: int, x: float, y: float, z: float) -> (),

	-- Decal management. Returns an opaque int decal ID, or -1 on failure.
	Kine_Filament_CreateDecal: (
		ctx: FFIPointer,
		width: float,
		height: float,
		texture: FFIPointer,
		offsetStudsU: float,
		offsetStudsV: float,
		studsPerTileU: float,
		studsPerTileV: float,
		culling: bool,
		castShadows: bool,
		receiveShadows: bool
	) -> int,
	Kine_Filament_SetDecalTiling: (
		ctx: FFIPointer,
		decal: int,
		width: float,
		height: float,
		offsetStudsU: float,
		offsetStudsV: float,
		studsPerTileU: float,
		studsPerTileV: float
	) -> bool,
	Kine_Filament_SetDecalTransform: (ctx: FFIPointer, decal: int, mat4: FFIPointer) -> bool,
	Kine_Filament_RemoveDecal: (ctx: FFIPointer, decal: int) -> (),
	Kine_Filament_EditDecal: (
		ctx: FFIPointer,
		decal: int,
		width: float,
		height: float,
		culling: bool,
		castShadows: bool,
		receiveShadows: bool
	) -> bool,
}

local funcs = {
	-- Context lifecycle
	Kine_Filament_Create = {
		returns = ffi.types.pointer,
		args = { ffi.types.i32, ffi.types.i32 },
	},
	Kine_Filament_CreateForSDLWindow = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer, ffi.types.i32, ffi.types.i32 },
	},
	Kine_Filament_CreateForVulkanCompositor = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer, ffi.types.i32, ffi.types.i32 },
	},
	Kine_Filament_CreateForVulkanCompositorWindow = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer, ffi.types.i32, ffi.types.i32 },
	},
	Kine_Filament_GetVulkanCompositor = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer },
	},
	Kine_Filament_Destroy = {
		returns = ffi.types.void,
		args = { ffi.types.pointer },
	},
	Kine_Filament_RenderFrame = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.float },
	},
	Kine_Filament_Resize = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.i32, ffi.types.i32 },
	},
	Kine_Filament_SetViewport = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.i32, ffi.types.i32, ffi.types.i32, ffi.types.i32 },
	},
	Kine_Filament_ReadPixels = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.pointer },
	},
	Kine_Filament_GetWidth = {
		returns = ffi.types.i32,
		args = { ffi.types.pointer },
	},
	Kine_Filament_CreateTexFromPixels = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer, ffi.types.i32, ffi.types.i32, ffi.types.i32, ffi.types.pointer },
	},
	Kine_Filament_UpdateTexFromPixels = {
		returns = ffi.types.u8,
		args = {
			ffi.types.pointer,
			ffi.types.pointer,
			ffi.types.i32,
			ffi.types.i32,
			ffi.types.i32,
			ffi.types.pointer,
		},
	},
	Kine_Filament_CreatePbrTexFromPixels = {
		returns = ffi.types.pointer,
		args = {
			ffi.types.pointer,
			ffi.types.i32,
			ffi.types.i32,
			ffi.types.i32,
			ffi.types.pointer,
			ffi.types.i32,
			ffi.types.i32,
			ffi.types.i32,
			ffi.types.pointer,
			ffi.types.i32,
			ffi.types.i32,
			ffi.types.i32,
			ffi.types.pointer,
			-- height map
			ffi.types.i32,
			ffi.types.i32,
			ffi.types.i32,
			ffi.types.pointer,
			ffi.types.float,
		},
	},
	Kine_Filament_GetHeight = {
		returns = ffi.types.i32,
		args = { ffi.types.pointer },
	},
	Kine_Filament_GetColorTextureId = {
		returns = ffi.types.u32,
		args = { ffi.types.pointer },
	},
	Kine_Filament_GetVulkanBackend = {
		returns = ffi.types.u8,
		args = { ffi.types.pointer, ffi.types.pointer },
	},
	Kine_Filament_DebugPrintPixel = {
		returns = ffi.types.void,
		args = { ffi.types.pointer },
	},

	-- Sky / post-processing
	Kine_Filament_CreateSky = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.float, ffi.types.float, ffi.types.float, ffi.types.float },
	},
	Kine_Filament_SetPostProcessing = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.u8 },
	},
	Kine_Filament_SetBloom = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer,
			ffi.types.u8,
			ffi.types.float,
			ffi.types.i32,
			ffi.types.i32,
			ffi.types.u8,
			ffi.types.u8,
		},
	},
	Kine_Filament_SetAmbientOcclusion = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer,
			ffi.types.u8,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.i32,
			ffi.types.i32,
		},
	},
	Kine_Filament_SetAntiAliasing = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.u8, ffi.types.u8, ffi.types.u8, ffi.types.i32 },
	},
	Kine_Filament_SetDynamicResolution = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.u8, ffi.types.float, ffi.types.float, ffi.types.i32, ffi.types.float },
	},
	Kine_Filament_SetDepthOfField = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer,
			ffi.types.u8,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.i32,
			ffi.types.i32,
		},
	},
	Kine_Filament_SetFocusDistance = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.float },
	},
	Kine_Filament_SetVignette = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer,
			ffi.types.u8,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
		},
	},
	Kine_Filament_SetScreenSpaceReflections = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.u8, ffi.types.float, ffi.types.float, ffi.types.float, ffi.types.float },
	},
	Kine_Filament_SetColorGrading = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
		},
	},
	Kine_Filament_ClearColorGrading = {
		returns = ffi.types.void,
		args = { ffi.types.pointer },
	},
	Kine_Filament_SetRenderQuality = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.i32 },
	},
	Kine_Filament_SetDithering = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.u8 },
	},
	Kine_Filament_SetShadowOptions = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.u8, ffi.types.i32 },
	},
	Kine_Filament_SetSunShadowOptions = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer,
			ffi.types.i32,
			ffi.types.i32,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.u8,
			ffi.types.u8,
		},
	},
	Kine_Filament_SetSunRays = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer,
			ffi.types.u8,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.u8,
		},
	},

	Kine_Filament_SetSkyAtmosphere = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.float, -- sunDirX
			ffi.types.float, -- sunDirY
			ffi.types.float, -- sunDirZ
			ffi.types.float, -- skyR
			ffi.types.float, -- skyG
			ffi.types.float, -- skyB
			ffi.types.float, -- horizonR
			ffi.types.float, -- horizonG
			ffi.types.float, -- horizonB
			ffi.types.float, -- groundR
			ffi.types.float, -- groundG
			ffi.types.float, -- groundB
			ffi.types.float, -- sunIntensity
		},
	},

	-- Scene accessors
	Kine_Filament_GetEngine = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer },
	},
	Kine_Filament_GetScene = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer },
	},
	Kine_Filament_GetView = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer },
	},
	Kine_Filament_GetCamera = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer },
	},

	-- Camera controls
	Kine_Filament_SetCameraLookAt = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float, -- eye
			ffi.types.float,
			ffi.types.float,
			ffi.types.float, -- target
			ffi.types.float,
			ffi.types.float,
			ffi.types.float, -- up
		},
	},
	Kine_Filament_SetCameraPosition = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.float, ffi.types.float, ffi.types.float },
	},
	Kine_Filament_SetCameraDirection = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.float, ffi.types.float, ffi.types.float },
	},
	Kine_Filament_SetCameraPerspective = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer,
			ffi.types.double,
			ffi.types.double,
			ffi.types.double,
			ffi.types.double,
		},
	},

	-- Mesh system
	Kine_Filament_CreateMesh = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer, ffi.types.i32 },
	},
	Kine_Filament_CreateMeshFromPath = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer, ffi.types.i8 },
	},
	Kine_Filament_DestroyMesh = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.pointer },
	},
	Kine_Filament_CreateGizmo = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer, ffi.types.i32 },
	},
	Kine_Filament_DestroyGizmo = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.pointer },
	},

	Kine_Filament_CreateCustomMesh = {
		returns = ffi.types.pointer,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.pointer, -- vertexData (float*)
			ffi.types.i32, -- vertexCount
			ffi.types.pointer, -- indices (uint16_t*)
			ffi.types.i32, -- indexCount
		},
	},
	Kine_Filament_CreateTerrainMesh = {
		returns = ffi.types.pointer,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.pointer, -- vertexData (float*)
			ffi.types.pointer, -- materialWeights (float[8] per vertex)
			ffi.types.i32, -- vertexCount
			ffi.types.pointer, -- indices (uint16_t*)
			ffi.types.i32, -- indexCount
		},
	},
	Kine_Filament_UpdateCustomMesh = {
		returns = ffi.types.u8,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.pointer, -- mesh
			ffi.types.pointer, -- vertexData
			ffi.types.i32, -- vertexCount
		},
	},

	-- Texture system
	Kine_Filament_CreateTex = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer, ffi.types.pointer },
	},
	Kine_Filament_CreateTerrainTextureSet = {
		returns = ffi.types.pointer,
		args = {
			ffi.types.pointer,
			ffi.types.pointer,
			ffi.types.pointer,
			ffi.types.pointer,
			ffi.types.pointer,
			ffi.types.pointer,
			ffi.types.pointer,
		},
	},
	Kine_Filament_DestroyTex = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.pointer },
	},

	-- Draw call
	Kine_Filament_DrawMeshEx = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.pointer, -- mesh
			ffi.types.i32, -- materialKind
			ffi.types.float, -- r
			ffi.types.float, -- g
			ffi.types.float, -- b
			ffi.types.float, -- param1 (roughness / intensity)
			ffi.types.float, -- param2 (ior)
			ffi.types.float, -- param3 (thickness)
			ffi.types.float, -- transmission
			ffi.types.pointer, -- mat4 float[16]
			ffi.types.u8, -- castShadows
			ffi.types.u8, -- receiveShadows
			ffi.types.u8, -- culling
			ffi.types.pointer, -- tex (optional KineFilamentTex*)
		},
	},
	Kine_Filament_DrawMeshList = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.pointer, -- KineFilamentDrawItem[]
			ffi.types.u32, -- itemCount
		},
	},
	Kine_Filament_DrawMeshListVersioned = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.pointer, -- KineFilamentDrawItem[] or null when unchanged
			ffi.types.u32, -- itemCount
			ffi.types.u64, -- streamId
			ffi.types.u64, -- version
		},
	},
	Kine_Filament_CreateInstanceBatch = {
		returns = ffi.types.pointer,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.pointer, -- KineFilamentDrawItem[]
			ffi.types.u32, -- itemCount
		},
	},
	Kine_Filament_DestroyInstanceBatch = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer, -- KineFilamentInstanceBatch*
		},
	},
	Kine_Filament_UpdateInstanceTransforms = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer, -- KineFilamentInstanceBatch*
			ffi.types.pointer, -- uint32_t[]
			ffi.types.pointer, -- float[16][]
			ffi.types.u32, -- dirtyCount
		},
	},
	Kine_Filament_DrawParticles = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.pointer, -- KineFilamentTex*
			ffi.types.pointer, -- KineFilamentParticleItem[]
			ffi.types.u32, -- itemCount
			ffi.types.float, -- uvScaleX
			ffi.types.float, -- uvScaleY
			ffi.types.float, -- uvOffsetX
			ffi.types.float, -- uvOffsetY
			ffi.types.u8, -- castShadows
			ffi.types.u8, -- culling
		},
	},
	Kine_Filament_DrawMeshOutline = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.pointer, -- mesh
			ffi.types.float, -- r
			ffi.types.float, -- g
			ffi.types.float, -- b
			ffi.types.float, -- thickness
			ffi.types.pointer, -- mat4 float[16]
		},
	},
	Kine_Filament_DrawGizmo = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.pointer, -- gizmo
			ffi.types.pointer, -- mat4 float[16]
			ffi.types.i32, -- hoveredAxis
			ffi.types.i32, -- selectedAxis
		},
	},
	Kine_Filament_PickGizmo = {
		returns = ffi.types.i32,
		args = {
			ffi.types.pointer,
			ffi.types.pointer,
			ffi.types.pointer,
			ffi.types.float,
			ffi.types.float,
		},
	},
	Kine_Filament_GetGizmoDragDelta = {
		returns = ffi.types.float,
		args = {
			ffi.types.pointer,
			ffi.types.pointer,
			ffi.types.pointer,
			ffi.types.i32,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
			ffi.types.float,
		},
	},

	Kine_Filament_CreateLight = {
		returns = ffi.types.i32,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.float,
			ffi.types.float,
			ffi.types.float, -- position (x,y,z)
			ffi.types.float,
			ffi.types.float,
			ffi.types.float, -- color (r,g,b)
			ffi.types.float, -- intensity
			ffi.types.float, -- falloff
		},
	},
	Kine_Filament_SetColorLight = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.i32, -- light
			ffi.types.float,
			ffi.types.float,
			ffi.types.float, -- color (r,g,b)
		},
	},
	Kine_Filament_SetIntensityLight = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.i32, ffi.types.float },
	},
	Kine_Filament_SetFalloffLight = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.i32, ffi.types.float },
	},
	Kine_Filament_SetPositionLight = {
		returns = ffi.types.void,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.i32, -- light
			ffi.types.float,
			ffi.types.float,
			ffi.types.float, -- position (x,y,z)
		},
	},

	-- Decal management
	Kine_Filament_CreateDecal = {
		returns = ffi.types.i32,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.float, -- width
			ffi.types.float, -- height
			ffi.types.pointer, -- KineFilamentTex
			ffi.types.float, -- offsetStudsU
			ffi.types.float, -- offsetStudsV
			ffi.types.float, -- studsPerTileU
			ffi.types.float, -- studsPerTileV
			ffi.types.u8, -- culling
			ffi.types.u8, -- castShadows
			ffi.types.u8, -- receiveShadows
		},
	},

	Kine_Filament_SetDecalTiling = {
		returns = ffi.types.u8,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.i32, -- decal
			ffi.types.float, -- width
			ffi.types.float, -- height
			ffi.types.float, -- offsetStudsU
			ffi.types.float, -- offsetStudsV
			ffi.types.float, -- studsPerTileU
			ffi.types.float, -- studsPerTileV
		},
	},

	Kine_Filament_BlitToScreen = {
		returns = ffi.types.u8,
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.float, -- dstX
			ffi.types.float, -- dstY
			ffi.types.float, -- dstWidth
			ffi.types.float, -- dstHeight
		},
	},

	Kine_Filament_RemoveDecal = {
		returns = ffi.types.void,
		args = { ffi.types.pointer, ffi.types.i32 },
	},
	Kine_Filament_SetDecalTransform = {
		returns = ffi.types.u8,
		args = { ffi.types.pointer, ffi.types.i32, ffi.types.pointer },
	},
	Kine_Filament_EditDecal = {
		returns = ffi.types.u8, -- bool
		args = {
			ffi.types.pointer, -- ctx
			ffi.types.i32, -- decal
			ffi.types.float, -- width
			ffi.types.float, -- height
			ffi.types.u8, -- culling
			ffi.types.u8, -- castShadows
			ffi.types.u8, -- receiveShadows
		},
	},
}

return funcs
