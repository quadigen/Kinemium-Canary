-- default renderer adapter, SDL3
local sdl = require("./sdl")
local typedefs = require("../../typedefs")
local ui = require("./skialib")
local filament = require("./filamentlib")
local sdl_image = require("./sdl_image")
local zembed = require("@zembed")
local SDLAdapter = {}

local translation_layers = {}
local active_translation = nil

export type SDL_Surface = typeof(sdl.structs.SDL_Surface:new())

local SDL_EVENT_QUIT = 0x100
local SDL_EVENT_WINDOW_RESIZED = 0x202
local SDL_EVENT_WINDOW_CLOSE_REQUESTED = 0x203
local SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED = 0x207
local SDL_EVENT_MOUSE_BUTTON_DOWN = 0x401
local SDL_EVENT_MOUSE_BUTTON_UP = 0x402
local SDL_SYSTEM_THEME_UNKNOWN = 0
local SDL_FLIP_NONE = 0
local SDL_FLIP_HORIZONTAL = 1
local SDL_FLIP_VERTICAL = 2
local SDL_SYSTEM_THEME_LIGHT = 1
local SDL_EVENT_MOUSE_MOTION = 0x400
local SDL_EVENT_MOUSE_WHEEL = 0x405
local SDL_SYSTEM_THEME_DARK = 2
local SDL_WINDOW_RESIZABLE = 0x0000000000000020
local SDL_INIT_VIDEO = 0x00000020
local GL_CONTEXT_MAJOR_VERSION = 17
local GL_CONTEXT_MINOR_VERSION = 18
local GL_CONTEXT_PROFILE_MASK = 21
local GL_DEPTH_SIZE = 6
local GL_DOUBLEBUFFER = 5
local PROFILE_CORE = 0x0001
local SDL_EVENT_KEY_DOWN = 0x300
local SDL_EVENT_TEXT_INPUT = 0x303

local eventPtr = zune.ffi.alloc(128)
local mouseDown = {}
local mousePressed = {}
local mouseReleased = {}
local keyDown = {}
local mouseDeltaX = 0
local mouseDeltaY = 0
local mouseWheel = 0
local cursorLocked = false

SDLAdapter.Key = {
	A = 4,
	B = 5,
	C = 6,
	D = 7,
	E = 8,
	F = 9,
	G = 10,
	H = 11,
	I = 12,
	J = 13,
	K = 14,
	L = 15,
	M = 16,
	N = 17,
	O = 18,
	P = 19,
	Q = 20,
	R = 21,
	S = 22,
	T = 23,
	U = 24,
	V = 25,
	W = 26,
	X = 27,
	Y = 28,
	Z = 29,

	Space = 44,
	Enter = 40,
	Escape = 41,
	Backspace = 42,
	Tab = 43,

	Left = 80,
	Right = 79,
	Up = 82,
	Down = 81,

	LeftShift = 225,
	RightShift = 229,
	LeftCtrl = 224,
	RightCtrl = 228,
	LeftAlt = 226,
	RightAlt = 230,

	CapsLock = 57,
	Delete = 76,
	Insert = 73,
	Home = 74,
	End = 77,
	PageUp = 75,
	PageDown = 78,
}

SDLAdapter.MouseButton = {
	Left = 1,
	Middle = 2,
	Right = 3,
	X1 = 4,
	X2 = 5,
}

local function window_real(w)
	if type(w) ~= "table" then
		return false
	end
	return w._handle ~= nil or w._uihandle ~= nil
end

function SDLAdapter:Init()
	sdl.lib.SDL_Init(SDL_INIT_VIDEO) -- SDL_INIT_VIDEO

	sdl.lib.SDL_GL_SetAttribute(GL_CONTEXT_PROFILE_MASK, PROFILE_CORE)
	sdl.lib.SDL_GL_SetAttribute(GL_CONTEXT_MAJOR_VERSION, 4)
	sdl.lib.SDL_GL_SetAttribute(GL_CONTEXT_MINOR_VERSION, 1) -- 4.1 core = safe ceiling incl. macOS
	sdl.lib.SDL_GL_SetAttribute(GL_DEPTH_SIZE, 24)
	sdl.lib.SDL_GL_SetAttribute(GL_DOUBLEBUFFER, 1)
end

function SDLAdapter:StartTextInput(window: typedefs.Window)
	if not window_real(window) then
		return
	end
	sdl.lib.SDL_StartTextInput(window._handle)
end

function SDLAdapter:StopTextInput(window: typedefs.Window)
	if not window_real(window) then
		return
	end
	sdl.lib.SDL_StopTextInput(window._handle)
end

local function readCString(strPtr, maxLen: number?)
	local bytes = {}
	local limit = maxLen or 256
	for i = 0, limit - 1 do
		local b = strPtr:readu8(i)
		if b == 0 then
			break
		end
		bytes[#bytes + 1] = string.char(b)
	end
	return table.concat(bytes)
end

function SDLAdapter:ClipRoundRect(window: typedefs.Window, rect: typedefs.Rectangle, radiusX, radiusY)
	if not window_real(window) then
		return
	end
	ui:ClipRoundRect(window._uihandle, rect, radiusX, radiusY)
end

function SDLAdapter:InitWindow(params: typedefs.WindowParams): typedefs.Window
	local graphics = {
		opengl = 0x0000000000000002,
		vulkan = 0x0000000010000000,
	}

	local flags = bit32.bor(graphics[params.WGI], SDL_WINDOW_RESIZABLE)

	local sdl_window = sdl.lib.SDL_CreateWindow(params.Title, params.Width, params.Height, flags)
	if sdl_window then
		local object = {
			Width = params.Width,
			Height = params.Height,
			WGI = params.WGI,
			_handle = sdl_window,
			_uihandle = ui:Init(params.Width, params.Height),
		}
		return object
	end
	return false
end

function SDLAdapter:Init3D(window: typedefs.Window)
	if not window_real(window) then
		return
	end
	filament:Init(window)
end

function SDLAdapter:GetSystemTheme(): "unknown" | "light" | "dark"
	local theme = sdl.lib.SDL_GetSystemTheme()
	if theme == 0 then
		return "unknown"
	elseif theme == 1 then
		return "light"
	elseif theme == 2 then
		return "dark"
	end
	return "unknown"
end

function SDLAdapter:CreateRenderingContext(window: typedefs.Window): typedefs.RenderingContext | boolean
	if not window_real(window) then
		return
	end
	if window.WGI == "opengl" then
		local context = sdl.lib.SDL_GL_CreateContext(window._handle)
		if context then
			local struct = {
				_handle = context,
				Window = window,
			}
			window._context = struct

			return struct
		else
			return false
		end
	elseif window.WGI == "vulkan" then
		print("Vulkan Rendering Context is in development, Check back later!")
		return false
	end
	return false
end

function SDLAdapter:GetDetailsImage(image: typedefs.Image)
	local sdl_image_surface = image._handle :: FFIPointer
	if sdl_image_surface == zune.ffi.null then
		return
	end
	if sdl_image_surface then
		local width_offset = sdl.structs.SDL_Surface:offset("w")
		local height_offset = sdl.structs.SDL_Surface:offset("h")
		local pixels_offset = sdl.structs.SDL_Surface:offset("pixels")
		local pitch_offset = sdl.structs.SDL_Surface:offset("pitch")

		local width = sdl_image_surface:readi32(width_offset)
		local height = sdl_image_surface:readi32(height_offset)
		local pixels = sdl_image_surface:readptr(pixels_offset)
		local pitch = sdl_image_surface:readi32(pitch_offset)
		local format_offset = sdl.structs.SDL_Surface:offset("format")
		local format = sdl_image_surface:readu32(format_offset)

		return { width = width, height = height, pixels = pixels, pitch = pitch, format = format }
	end
	return
end

local function loadRgbaImage(imagePath: string)
	local ok, surface = pcall(sdl_image.lib.IMG_Load, imagePath)
	if not ok or not surface or surface == zune.ffi.null then
		return nil, nil
	end

	local rgbaSurface = sdl.lib.SDL_ConvertSurface(
		surface :: SDL_Surface,
		0x16762004 -- SDL_PIXELFORMAT_RGBA32
	)

	sdl.lib.SDL_DestroySurface(surface :: SDL_Surface)
	if not rgbaSurface or rgbaSurface == zune.ffi.null then
		return nil, nil
	end

	local image = {
		_handle = rgbaSurface,
	}
	local details = SDLAdapter:GetDetailsImage(image)
	if details then
		image.width = details.width
		image.height = details.height
		image.pixels = details.pixels
		image.pitch = details.pitch
	end

	return image, rgbaSurface
end

function SDLAdapter:CreateImageFromPath(path: string)
	path = zembed.AssetPath(path)
	local surface = sdl_image.lib.IMG_Load(path) :: SDL_Surface
	local skia_image = ui:CreateImage(path)

	local new = {
		_handle = skia_image,
		_surface = surface,
	}
	local details = SDLAdapter:GetDetailsImage(new)
	if details then
		new.width = details.width
		new.height = details.height
		new.pixels = details.pixels
		new.pitch = details.pitch
	end

	return new
end

function SDLAdapter:CreateMesh(window: typedefs.Window, meshType: string)
	return filament:CreateMesh(window, meshType)
end

function SDLAdapter:CreateDecalTexture(window: typedefs.Window, path: string)
	path = zembed.AssetPath(path)
	local image, surface = loadRgbaImage(path)
	if not image then
		return nil
	end

	local texture = filament:CreateTextureFromImage(window, image)
	sdl.lib.SDL_DestroySurface(surface)
	return texture
end

function SDLAdapter:CreateMeshTexture(window: typedefs.Window, path: string)
	local albedo, albedoSurface = loadRgbaImage(path)
	if not albedo then
		return nil
	end

	local basePath = path:gsub("/albedo%.png$", "")
	local normal, normalSurface = loadRgbaImage(basePath .. "/normal.png")
	local orm, ormSurface = loadRgbaImage(basePath .. "/orm.png")

	local texture = nil
	if normal or orm then
		texture = filament:CreateMaterialTextureFromImages(window, albedo, normal, orm)
	else
		texture = filament:CreateTextureFromImage(window, albedo)
	end

	sdl.lib.SDL_DestroySurface(albedoSurface)
	if normalSurface then
		sdl.lib.SDL_DestroySurface(normalSurface)
	end
	if ormSurface then
		sdl.lib.SDL_DestroySurface(ormSurface)
	end

	return texture
end

function SDLAdapter:MeasureText(window: typedefs.Window, text: string, textSize: number, font: typedefs.Font)
	return ui:MeasureText(text, textSize, font)
end

function SDLAdapter:GetFontLineHeight(fontSize: number, font: typedefs.Font)
	return ui:GetFontLineHeight(fontSize, font)
end

function SDLAdapter:DrawImageSized(window: typedefs.Window, image: typedefs.Image, rect: typedefs.Rectangle)
	if not window_real(window) then
		return
	end
	ui:DrawImageSized(window._uihandle, image, rect)
end

function SDLAdapter:ShowWindow(window: typedefs.Window)
	if not window_real(window) then
		return
	end
	sdl.lib.SDL_ShowWindow(window._handle)
end

function SDLAdapter:BeginFrame(context: typedefs.RenderingContext)
	sdl.lib.SDL_GL_MakeCurrent(context.Window._handle, context._handle)
end

function SDLAdapter:ReleaseGLContext(context: typedefs.RenderingContext)
	sdl.lib.SDL_GL_MakeCurrent(context.Window._handle, nil)
end

function SDLAdapter:EndFrame(context: typedefs.RenderingContext)
	sdl.lib.SDL_GL_SwapWindow(context.Window._handle)
end

function SDLAdapter:RenderClear(renderer: typedefs.Renderer)
	sdl.lib.SDL_SetRenderDrawColor(renderer._handle, 0, 0, 0, 0)
	sdl.lib.SDL_RenderClear(renderer._handle)
end

function SDLAdapter:GetWindowPixelSize(window: typedefs.Window): (number?, number?)
	if not window_real(window) then
		return nil, nil
	end

	local widthPtr = zune.ffi.alloc(4)
	local heightPtr = zune.ffi.alloc(4)
	sdl.lib.SDL_GetWindowSizeInPixels(window._handle, widthPtr, heightPtr)
	return widthPtr:readi32(0), heightPtr:readi32(0)
end

function SDLAdapter:GetDPIScale(window: typedefs.Window)
	if not window_real(window) then
		return
	end
	return sdl.lib.SDL_GetWindowDisplayScale(window._handle)
end

function SDLAdapter:CreateRenderer(window: typedefs.Window): typedefs.Renderer
	if not window_real(window) then
		return
	end

	local renderer = {
		_handle = sdl.lib.SDL_CreateRenderer(window._handle, 0),
	}
	window._rendererhandle = renderer._handle
	return renderer
end

function SDLAdapter:CreateTexture(params: typedefs.TextureParams): typedefs.Texture
	local PixelFormat = {
		UNKNOWN = 0,

		RGB332 = 0x14110801,
		RGB444 = 0x15120E02,
		RGB555 = 0x15130F02,
		BGR555 = 0x15530F02,
		ARGB4444 = 0x15321002,
		RGBA4444 = 0x15421002,
		ABGR4444 = 0x15721002,
		BGRA4444 = 0x15821002,

		RGB565 = 0x15151002,
		BGR565 = 0x15551002,

		RGB24 = 0x17101803,
		BGR24 = 0x17401803,

		RGB888 = 0x16161804,
		RGBX8888 = 0x16261804,
		BGR888 = 0x16561804,
		BGRX8888 = 0x16661804,

		ARGB8888 = 0x16362004,
		RGBA8888 = 0x16462004,
		ABGR8888 = 0x16762004,
		BGRA8888 = 0x16862004,

		ARGB2101010 = 0x16372004,
		ABGR2101010 = 0x16772004,

		RGB10A2 = 0x16472004,
		BGR10A2 = 0x16872004,

		RGBA32 = 0xA1676204,
		ARGB32 = 0xA1632004,
		BGRA32 = 0xA1686204,
		ABGR32 = 0xA1676204,
	}

	local TextureAccess = {
		STATIC = 0,
		STREAMING = 1,
		TARGET = 2,
	}

	local texture = sdl.lib.SDL_CreateTexture(
		params.renderer._handle,
		PixelFormat[params.pixelFormat],
		TextureAccess[params.access],
		params.width,
		params.height
	)
	sdl.lib.SDL_SetTextureBlendMode(texture, 0x00000010)

	return {
		_handle = texture,
		width = params.width,
		height = params.height,
	}
end

function SDLAdapter:DrawTexture(renderer: typedefs.Renderer, texture: typedefs.Texture, dstRect: any?)
	if dstRect then
		local rectPtr = zune.ffi.alloc(16)
		rectPtr:writef32(0, dstRect.X)
		rectPtr:writef32(4, dstRect.Y)
		rectPtr:writef32(8, dstRect.Width)
		rectPtr:writef32(12, dstRect.Height)
		sdl.lib.SDL_RenderTexture(renderer._handle, texture._handle, nil, rectPtr)
		zune.ffi.free(rectPtr)
	else
		sdl.lib.SDL_RenderTexture(renderer._handle, texture._handle, nil, nil)
	end
end

function SDLAdapter:IsMouseButtonPressed(button: number)
	return mousePressed[button] == true
end

function SDLAdapter:IsMouseButtonReleased(button: number)
	return mouseReleased[button] == true
end

function SDLAdapter:IsMouseButtonDown(button: number)
	return mouseDown[button] == true
end

function SDLAdapter:DisableCursor(window: typedefs.Window)
	if not window_real(window) then
		return
	end

	cursorLocked = true
	sdl.lib.SDL_SetWindowRelativeMouseMode(window._handle, true)
end

function SDLAdapter:EnableCursor(window: typedefs.Window)
	if not window_real(window) then
		return
	end

	cursorLocked = false
	sdl.lib.SDL_SetWindowRelativeMouseMode(window._handle, false)
end

function SDLAdapter:SetMousePosition(window: typedefs.Window, x: number, y: number)
	if not window_real(window) then
		return
	end

	sdl.lib.SDL_WarpMouseInWindow(window._handle, x, y)
end

function SDLAdapter:GetMouseDelta()
	return {
		x = mouseDeltaX,
		y = mouseDeltaY,
	}
end

function SDLAdapter:GetMouseWheelMove()
	local value = mouseWheel
	mouseWheel = 0
	return value
end

function SDLAdapter:IsKeyDown(key: number)
	return keyDown[key] == true
end

function SDLAdapter:GetRenderWidth(window: typedefs.Window)
	local width, _ = SDLAdapter:GetWindowPixelSize(window)
	return width or window.Width
end

function SDLAdapter:GetRenderHeight(window: typedefs.Window)
	local _, height = SDLAdapter:GetWindowPixelSize(window)
	return height or window.Height
end

function SDLAdapter:DestroyTexture(texture: typedefs.Texture)
	if texture and texture._handle then
		sdl.lib.SDL_DestroyTexture(texture._handle)
	end
end

function SDLAdapter:ShowMessageBox(
	window: typedefs.Window,
	type: "warning" | "error" | "info",
	title: string,
	description: string
)
	local types = {
		info = 0x40,
		warning = 0x20,
		error = 0x10,
	}

	local messageType = types[type]
	assert(messageType, `Invalid message box type: {type}`)

	sdl.lib.SDL_ShowSimpleMessageBox(types[type], title, description, window._handle)
end

function SDLAdapter:PollEvents(window: typedefs.Window, callback)
	if not window_real(window) then
		return
	end

	table.clear(mousePressed)
	table.clear(mouseReleased)

	mouseDeltaX = 0
	mouseDeltaY = 0
	mouseWheel = 0

	local resized, newWidth, newHeight = false, nil, nil
	local shouldClose = false
	local clicks = {}
	local mousex, mousey = 0, 0
	local textInputs = {}
	local keyDowns = {}

	while true do
		local pollResult = sdl.lib.SDL_PollEvent(eventPtr)
		if not pollResult or pollResult == 0 then
			break
		end

		local eventType = eventPtr:readu32(0)

		if callback then
			callback(eventPtr)
		end

		if eventType == SDL_EVENT_WINDOW_RESIZED or eventType == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED then
			resized = true
			newWidth = eventPtr:readi32(20)
			newHeight = eventPtr:readi32(24)
		elseif eventType == SDL_EVENT_QUIT or eventType == SDL_EVENT_WINDOW_CLOSE_REQUESTED then
			shouldClose = true
		elseif eventType == SDL_EVENT_MOUSE_WHEEL then
			mouseWheel += eventPtr:readf32(24)
		elseif eventType == SDL_EVENT_MOUSE_BUTTON_DOWN or eventType == SDL_EVENT_MOUSE_BUTTON_UP then
			local button = eventPtr:readu8(24)
			local down = eventType == SDL_EVENT_MOUSE_BUTTON_DOWN

			mouseDown[button] = down

			if down then
				mousePressed[button] = true
			else
				mouseReleased[button] = true
			end

			table.insert(clicks, {
				Button = button,
				Down = down,
				Clicks = eventPtr:readu8(26),
				X = eventPtr:readf32(28),
				Y = eventPtr:readf32(32),
			})
		elseif eventType == SDL_EVENT_MOUSE_MOTION then
			mousex = eventPtr:readf32(28)
			mousey = eventPtr:readf32(32)

			mouseDeltaX += eventPtr:readf32(36)
			mouseDeltaY += eventPtr:readf32(40)
		elseif eventType == SDL_EVENT_TEXT_INPUT then
			local strPtr = eventPtr:readptr(24)
			if strPtr then
				local str = readCString(strPtr)
				if str ~= "" then
					table.insert(textInputs, str)
				end
			end
		elseif eventType == SDL_EVENT_KEY_DOWN then
			table.insert(keyDowns, eventPtr:readu32(28))
		end
	end

	local keyboardState = sdl.lib.SDL_GetKeyboardState(zune.ffi.null)
	if keyboardState then
		for _, key in pairs(SDLAdapter.Key) do
			keyDown[key] = keyboardState:readu8(key) ~= 0
		end
	end

	return resized, newWidth, newHeight, shouldClose, clicks, mousex, mousey, textInputs, keyDowns
end

-- ui lib
function SDLAdapter:UpdateSkiaTexture(texture: typedefs.Texture, window: typedefs.Window)
	local pixels, pitch = ui:GetPixelsAndPitch(window._uihandle)
	if not pixels or not pitch then
		return
	end
	sdl.lib.SDL_UpdateTexture(texture._handle, nil, pixels, pitch)
end

function SDLAdapter:CreateTranslationLayer(name: string, phrasemap: { string: string })
	translation_layers[name] = phrasemap
	active_translation = name
end

function SDLAdapter:SetActiveTranslationLayer(name: string)
	active_translation = name
end

function SDLAdapter:GetMousePosition(): typedefs.Vector
	local x = zune.ffi.alloc(4)
	local y = zune.ffi.alloc(4)

	sdl.lib.SDL_GetMouseState(x, y)

	local mouseX = x:readf32(0)
	local mouseY = y:readf32(0)

	zune.ffi.free(x)
	zune.ffi.free(y)

	return {
		X = mouseX,
		Y = mouseY,
	}
end

function SDLAdapter:DrawRectangle(window: typedefs.Window, rectangle: typedefs.Rectangle)
	if not window_real(window) then
		return
	end
	ui:DrawRect(window._uihandle, rectangle)
end

function SDLAdapter:CreateSkiaSurface(width, height): typedefs.Surface2D
	return { _uihandle = ui:InitSkiaSurface(width, height), width = width, height = height }
end

function SDLAdapter:GetFontAscent(fontSize, font: typedefs.Font)
	return ui:GetFontAscent(fontSize, font)
end

function SDLAdapter:Clear2D(window: typedefs.Window, color: typedefs.RGBA)
	if not window_real(window) then
		return
	end
	ui:Clear(window._uihandle, color)
end

function SDLAdapter:CreateFont(path)
	return ui:CreateFont(path) :: typedefs.Font
end

function SDLAdapter:DrawText(window: typedefs.Window, text: string, args: typedefs.TextArgs)
	if not window_real(window) then
		return
	end
	local mapped = text
	local active = translation_layers[active_translation]
	if active then
		if active[text] then
			mapped = active[text]
		end
	end
	ui:DrawText(window._uihandle, mapped, args)
end

function SDLAdapter:UpdateTexture(texture: typedefs.Texture, pixels, pitch)
	sdl.lib.SDL_UpdateTexture(texture._handle, nil, pixels, pitch)
end

function SDLAdapter:SetCameraPosition(window: typedefs.Window, position: typedefs.Vector3)
	if not window_real(window) then
		return
	end
	filament:SetCameraPosition(window, position)
end

function SDLAdapter:ResizePixelBuffer(window, width, height)
	filament:ResizePixelBuffer(window, width, height)
end

function SDLAdapter:InitSkiaSurface(width, height)
	return ui:InitSkiaSurface(width, height)
end

function SDLAdapter:Shutdown(window: typedefs.Window, renderer: typedefs.Renderer, context)
	if not window_real(window) then
		return
	end
	if renderer then
		sdl.lib.SDL_DestroyRenderer(renderer._handle)
	end
	if context then
		sdl.lib.SDL_GL_DestroyContext(context._handle)
	end
	if window then
		sdl.lib.SDL_DestroyWindow(window._handle)
	end
	sdl.lib.SDL_Quit()
end

function SDLAdapter:DestroySkiaSurface(surface)
	ui:DestroySurface(surface)
end

function SDLAdapter:Render3D(window: typedefs.Window, dt: number)
	if not window_real(window) then
		return
	end
	filament:Render3D(window, dt)
end

function SDLAdapter:Resize3D(window: typedefs.Window, width: number, height: number)
	if not window_real(window) then
		return
	end
	filament:Resize3D(window, width, height)
end

function SDLAdapter:RGBA(r, g, b, a: number?): typedefs.RGBA
	return {
		R = r / 255,
		G = g / 255,
		B = b / 255,
		A = a or 1,
	}
end

function SDLAdapter:DrawTextureFlipped(renderer: typedefs.Renderer, texture: typedefs.Texture, dstRect: any?)
	local dstPtr = nil
	if dstRect then
		dstPtr = zune.ffi.alloc(16)
		dstPtr:writef32(0, dstRect.X)
		dstPtr:writef32(4, dstRect.Y)
		dstPtr:writef32(8, dstRect.Width)
		dstPtr:writef32(12, dstRect.Height)
	end

	sdl.lib.SDL_RenderTextureRotated(
		renderer._handle,
		texture._handle,
		nil, -- srcrect
		dstPtr, -- dstrect
		0.0, -- angle
		nil, -- center
		SDL_FLIP_VERTICAL
	)

	if dstPtr then
		zune.ffi.free(dstPtr)
	end
end

function SDLAdapter:Vector3(x: number, y: number, z: number): typedefs.Vector3
	return {
		X = x,
		Y = y,
		Z = z,
	}
end

function SDLAdapter:BlitToScreen3D(
	window: typedefs.Window,
	dstX: number,
	dstY: number,
	dstWidth: number,
	dstHeight: number
)
	filament:BlitToScreen(window, dstX, dstY, dstWidth, dstHeight)
end

function SDLAdapter:Save(window: typedefs.Window | typedefs.Surface2D)
	if not window_real(window) then
		return
	end
	ui:Save(window._uihandle)
end

function SDLAdapter:Restore(window: typedefs.Window)
	if not window_real(window) then
		return
	end
	ui:Restore(window._uihandle)
end

function SDLAdapter:GetPixels(window: typedefs.Window)
	if not window_real(window) then
		return
	end
	return filament:GetPixels(window)
end

function SDLAdapter:SetClipboard(text: string)
	sdl.lib.SDL_SetClipboardText(text)
end

function SDLAdapter:GetClipboard()
	return sdl.lib.SDL_GetClipboardText()
end

-- frame
function SDLAdapter:RenderPresent(renderer: typedefs.Renderer)
	sdl.lib.SDL_SetRenderDrawColor(renderer._handle, 0, 0, 0, 255)
	sdl.lib.SDL_RenderPresent(renderer._handle)
end

-- i genuinely dont want to write this but
SDLAdapter.DrawMesh = filament.DrawMesh
SDLAdapter.SetSkyAtmosphere = filament.SetSkyAtmosphere
SDLAdapter.SetCameraLookAt = filament.SetCameraLookAt
SDLAdapter.CreateDecal = filament.CreateDecal
SDLAdapter.RemoveDecal = filament.RemoveDecal
SDLAdapter.SetDecalTransform = filament.SetDecalTransform
SDLAdapter.SetDecalTiling = filament.SetDecalTiling
SDLAdapter.Destroy3DTexture = filament.Destroy3DTexture

return SDLAdapter
