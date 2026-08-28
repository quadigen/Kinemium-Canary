local Selection = game:GetService("Selection")
local Argon = require("@Argon")
local GuiObject = require("@GuiObject")
local UDim2 = require("@UDim2")

local HANDLE_SIZE = 8
local MIN_SIZE = 8
local activeDrag = nil

local handles = {
	{ name = "TL", x = 0, y = 0, left = true, top = true },
	{ name = "T", x = 0.5, y = 0, top = true },
	{ name = "TR", x = 1, y = 0, right = true, top = true },
	{ name = "L", x = 0, y = 0.5, left = true },
	{ name = "R", x = 1, y = 0.5, right = true },
	{ name = "BL", x = 0, y = 1, left = true, bottom = true },
	{ name = "B", x = 0.5, y = 1, bottom = true },
	{ name = "BR", x = 1, y = 1, right = true, bottom = true },
}

local function inRect(mouse, x, y, width, height)
	return mouse.X >= x and mouse.X <= x + width and mouse.Y >= y and mouse.Y <= y + height
end

local function isScreenGuiObject(object)
	if not object or object.BaseClass ~= "GuiObject" then
		return false
	end
	local ancestor = object.Parent
	while ancestor do
		if ancestor.ClassName == "ScreenGui" then
			return ancestor.Enabled ~= false
		end
		if ancestor.BaseClass == "UIContainer" then
			return false
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function getParentMetrics(object)
	local parent = object.Parent
	local pos = parent and (parent.AbsolutePosition or parent.RenderOffset)
	local size = parent and parent.AbsoluteSize
	if not size and parent and parent.Size then
		size = { X = parent.Size.X.Offset, Y = parent.Size.Y.Offset }
	end
	return pos or { X = 0, Y = 0 }, size or { X = 0, Y = 0 }
end

local function beginDrag(object, mode, handle, mouse, drawPos, size)
	activeDrag = {
		object = object,
		mode = mode,
		handle = handle,
		mouseX = mouse.X,
		mouseY = mouse.Y,
		left = drawPos.X,
		top = drawPos.Y,
		width = size.X,
		height = size.Y,
	}
	object._LayoutControlled = false
end

local function applyDrag(mouse)
	local drag = activeDrag
	local object = drag.object
	local dx, dy = mouse.X - drag.mouseX, mouse.Y - drag.mouseY
	local left, top = drag.left, drag.top
	local right, bottom = left + drag.width, top + drag.height

	if drag.mode == "move" then
		left, right = left + dx, right + dx
		top, bottom = top + dy, bottom + dy
	else
		local h = drag.handle
		if h.left then
			left = math.min(left + dx, right - MIN_SIZE)
		end
		if h.right then
			right = math.max(right + dx, left + MIN_SIZE)
		end
		if h.top then
			top = math.min(top + dy, bottom - MIN_SIZE)
		end
		if h.bottom then
			bottom = math.max(bottom + dy, top + MIN_SIZE)
		end
	end

	local width, height = right - left, bottom - top
	local parentPos, parentSize = getParentMetrics(object)
	local anchor = object.AnchorPoint or { X = 0, Y = 0 }
	local position, size = object.Position, object.Size
	object.Position = UDim2.new(
		position.X.Scale,
		left - parentPos.X + width * anchor.X - parentSize.X * position.X.Scale,
		position.Y.Scale,
		top - parentPos.Y + height * anchor.Y - parentSize.Y * position.Y.Scale
	)
	if drag.mode == "resize" then
		object.Size = UDim2.new(
			size.X.Scale,
			width - parentSize.X * size.X.Scale,
			size.Y.Scale,
			height - parentSize.Y * size.Y.Scale
		)
	end
end

renderer.Pool.new("2da", function()
	local selected = Selection.Get()
	local selection = selected and selected[1]
	if not isScreenGuiObject(selection) then
		activeDrag = nil
		return
	end

	local drawPos, size = GuiObject.calculatePositions(renderer.Window, selection, renderer.RuntimeLibrary.dt, renderer)
	if not drawPos or not size then
		return
	end
	local mouse = Argon:GetMousePosition()

	if activeDrag and activeDrag.object ~= selection then
		activeDrag = nil
	end
	if activeDrag then
		if Argon:IsMouseButtonDown(Argon.MouseButton.Left) then
			applyDrag(mouse)
		else
			activeDrag = nil
		end
	elseif Argon:IsMouseButtonPressed(Argon.MouseButton.Left) then
		local hitHandle
		for _, handle in ipairs(handles) do
			local cx, cy = drawPos.X + size.X * handle.x, drawPos.Y + size.Y * handle.y
			if inRect(mouse, cx - HANDLE_SIZE, cy - HANDLE_SIZE, HANDLE_SIZE * 2, HANDLE_SIZE * 2) then
				hitHandle = handle
				break
			end
		end
		if hitHandle then
			beginDrag(selection, "resize", hitHandle, mouse, drawPos, size)
		elseif inRect(mouse, drawPos.X, drawPos.Y, size.X, size.Y) then
			beginDrag(selection, "move", nil, mouse, drawPos, size)
		end
	end

	Argon:DrawRectangle(renderer.Window, {
		x = drawPos.X,
		y = drawPos.Y,
		width = size.X,
		height = size.Y,
		Color = Argon:RGBA(255, 48, 48),
		isOutline = true,
	})
	for _, handle in ipairs(handles) do
		local cx, cy = drawPos.X + size.X * handle.x, drawPos.Y + size.Y * handle.y
		Argon:DrawRectangle(renderer.Window, {
			x = cx - HANDLE_SIZE * 0.5,
			y = cy - HANDLE_SIZE * 0.5,
			width = HANDLE_SIZE,
			height = HANDLE_SIZE,
			Color = Argon:RGBA(255, 48, 48),
		})
	end
end, 1000000)
