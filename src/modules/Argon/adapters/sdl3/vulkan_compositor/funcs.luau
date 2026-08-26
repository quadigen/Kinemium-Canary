local ffi = zune.ffi

type int = number
type uint = number
type FFIPointer = typeof(ffi.types.pointer)

export type Fns = {
	Kine_VulkanCompositor_CreateForSDLWindow: (sdlWindow: FFIPointer, width: int, height: int) -> FFIPointer,
	Kine_VulkanCompositor_Destroy: (compositor: FFIPointer) -> (),
	Kine_VulkanCompositor_IsReady: (compositor: FFIPointer) -> int,
	Kine_VulkanCompositor_GetLastError: (compositor: FFIPointer) -> FFIPointer,
	Kine_VulkanCompositor_GetInfo: (compositor: FFIPointer, outInfo: FFIPointer) -> int,
	Kine_VulkanCompositor_GetSkiaContext: (compositor: FFIPointer) -> FFIPointer,
	Kine_VulkanCompositor_GetCurrentSkiaSurface: (compositor: FFIPointer) -> FFIPointer,
	Kine_VulkanCompositor_BeginFrame: (compositor: FFIPointer) -> FFIPointer,
	Kine_VulkanCompositor_EndFrame: (compositor: FFIPointer) -> int,
}

local funcs = {
	Kine_VulkanCompositor_CreateForSDLWindow = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer, ffi.types.i32, ffi.types.i32 },
	},
	Kine_VulkanCompositor_Destroy = {
		returns = ffi.types.void,
		args = { ffi.types.pointer },
	},
	Kine_VulkanCompositor_IsReady = {
		returns = ffi.types.i32,
		args = { ffi.types.pointer },
	},
	Kine_VulkanCompositor_GetLastError = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer },
	},
	Kine_VulkanCompositor_GetInfo = {
		returns = ffi.types.i32,
		args = { ffi.types.pointer, ffi.types.pointer },
	},
	Kine_VulkanCompositor_GetSkiaContext = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer },
	},
	Kine_VulkanCompositor_GetCurrentSkiaSurface = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer },
	},
	Kine_VulkanCompositor_BeginFrame = {
		returns = ffi.types.pointer,
		args = { ffi.types.pointer },
	},
	Kine_VulkanCompositor_EndFrame = {
		returns = ffi.types.i32,
		args = { ffi.types.pointer },
	},
}

return funcs :: Fns
