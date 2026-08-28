-- description: "Base class for 2D GUI elements: layout, absolute positioning, and mouse hit-testing only."
local Color3 = require("@Color3")
local Enum = require("@EnumMap")
local UDim2 = require("@UDim2")
local signal = require("@Kinemium.signal")
local Vector2 = require("@Vector2")
local argon = require("@Argon")

local ZERO_V = vector.create(0, 0, 0)
local MAX_AUTOMATIC_SIZE_DEPTH = 8

local function resolveUDim2(val, parentDim)
	if val then
		if val.ToPixels then
			return val:ToPixels(parentDim)
		elseif val.X and val.Y then
			local x = (type(val.X) == "table" and ((val.X.Scale or 0) * parentDim.X + (val.X.Offset or 0))) or 0
			local y = (type(val.Y) == "table" and ((val.Y.Scale or 0) * parentDim.Y + (val.Y.Offset or 0))) or 0
			return vector.create(x, y, 0)
		end
	end
	return ZERO_V
end

local function toArgonColor(color3, transparency)
	if color3.ToArgon then
		return color3:ToArgon(transparency)
	end
	return {
		R = color3.R,
		G = color3.G,
		B = color3.B,
		A = 1 - (transparency or 0),
	}
end

local function resolveAutomaticSizeAxes(mode)
	if mode == Enum.AutomaticSize.XY then
		return true, true
	elseif mode == Enum.AutomaticSize.X then
		return true, false
	elseif mode == Enum.AutomaticSize.Y then
		return false, true
	end

	local name = type(mode) == "table" and mode.Name or mode
	if name == "XY" then
		return true, true
	elseif name == "X" then
		return true, false
	elseif name == "Y" then
		return false, true
	end

	return false, false
end

local function resolvePaddingBounds(object, parentSize)
	local left, right, top, bottom = 0, 0, 0, 0

	for _, child in ipairs(object:GetChildren()) do
		if child.ClassName == "UIPadding" and child.GetResolvedPadding then
			local padding = child:GetResolvedPadding(parentSize)
			left += padding.Left or 0
			right += padding.Right or 0
			top += padding.Top or 0
			bottom += padding.Bottom or 0
		end
	end

	return left, right, top, bottom
end

local function getContentMetrics(object, size)
	if not object or object.BaseClass == "UIContainer" then
		return ZERO_V, size
	end

	local left, right, top, bottom = resolvePaddingBounds(object, size)
	return vector.create(left, top, 0),
		vector.create(math.max(0, size.X - left - right), math.max(0, size.Y - top - bottom), 0)
end

local function precomputeLayoutChildren(object, window, dt, renderer)
	for _, child in ipairs(object:GetChildren()) do
		local className = child.ClassName
		local isLayout = type(className) == "string" and string.sub(className, -6) == "Layout"
		if isLayout and child.render and child.Enabled ~= false then
			child.render(window, child, dt or 0, renderer)
		end
	end
end

local function calculateResolvedSize(object, parentSize, window, dt, renderer, depth)
	local size = resolveUDim2(object.Size, parentSize)
	local autoX, autoY = resolveAutomaticSizeAxes(object.AutomaticSize)

	if (not autoX and not autoY) or (depth or 0) >= MAX_AUTOMATIC_SIZE_DEPTH then
		return size
	end

	precomputeLayoutChildren(object, window, dt, renderer)

	local left, right, top, bottom = resolvePaddingBounds(object, size)
	local contentSize = vector.create(math.max(0, size.X - left - right), math.max(0, size.Y - top - bottom), 0)
	local maxX, maxY = left, top
	local hasGuiChild = false

	for _, child in ipairs(object:GetChildren()) do
		if child.BaseClass == "GuiObject" and child.Visible ~= false and child.Size then
			hasGuiChild = true

			local childSize = calculateResolvedSize(child, contentSize, window, dt, renderer, (depth or 0) + 1)
			local anchor = child.AnchorPoint or ZERO_V
			local relX, relY

			if child._LayoutControlled and child._LayoutRelativePosition then
				relX = child._LayoutRelativePosition.X - childSize.X * anchor.X
				relY = child._LayoutRelativePosition.Y - childSize.Y * anchor.Y
			elseif child.Position then
				local childPos = resolveUDim2(child.Position, contentSize)
				relX = left + childPos.X - childSize.X * anchor.X
				relY = top + childPos.Y - childSize.Y * anchor.Y
			end

			if relX and relY then
				maxX = math.max(maxX, relX + childSize.X)
				maxY = math.max(maxY, relY + childSize.Y)
			end
		end
	end

	if hasGuiChild then
		maxX += right
		maxY += bottom
	else
		maxX = left + right
		maxY = top + bottom
	end

	return vector.create(autoX and math.max(0, maxX) or size.X, autoY and math.max(0, maxY) or size.Y, 0)
end

local function GetAbsoluteSize(object, window, dt, renderer, depth)
	if object.BaseClass == "UIContainer" then
		return vector.create(object.Size.X.Offset, object.Size.Y.Offset, 0)
	end

	local parentSize = GetAbsoluteSize(object.Parent, window, dt, renderer, (depth or 0) + 1)
	local _, parentContentSize = getContentMetrics(object.Parent, parentSize)
	return calculateResolvedSize(object, parentContentSize, window, dt, renderer, depth)
end

local function getAbsoluteDrawPos(object, window, dt, renderer, depth)
	if object.BaseClass == "UIContainer" then
		return object.RenderOffset
	end
	local parent = object.Parent
	local parentAbsPos = getAbsoluteDrawPos(parent, window, dt, renderer, (depth or 0) + 1)
	local parentSize = GetAbsoluteSize(parent, window, dt, renderer, (depth or 0) + 1)
	local parentPaddingOffset, parentContentSize = getContentMetrics(parent, parentSize)
	local size = calculateResolvedSize(object, parentContentSize, window, dt, renderer, depth)
	local anchor = object.AnchorPoint or ZERO_V
	local drawPos

	if object._LayoutControlled and object._LayoutRelativePosition then
		drawPos = vector.create(
			parentAbsPos.X + object._LayoutRelativePosition.X - size.X * anchor.X,
			parentAbsPos.Y + object._LayoutRelativePosition.Y - size.Y * anchor.Y,
			0
		)
	else
		local pos = resolveUDim2(object.Position, parentContentSize)
		drawPos = vector.create(
			parentAbsPos.X + parentPaddingOffset.X + pos.X - size.X * anchor.X,
			parentAbsPos.Y + parentPaddingOffset.Y + pos.Y - size.Y * anchor.Y,
			0
		)
	end

	if parent and parent.ClassName == "ScrollingFrame" then
		drawPos = vector.create(drawPos.X, drawPos.Y - (parent.CanvasPosition or 0), 0)
	end
	return drawPos
end

local function isMouseInRect(mousePos, drawPos, size)
	return mousePos.X >= drawPos.X
		and mousePos.X <= drawPos.X + size.X
		and mousePos.Y >= drawPos.Y
		and mousePos.Y <= drawPos.Y + size.Y
end

local function calculateDrawParams(object, window, dt, renderer, depth)
	local parentSize = GetAbsoluteSize(object.Parent, window, dt, renderer, (depth or 0) + 1)
	local _, parentContentSize = getContentMetrics(object.Parent, parentSize)
	local size, drawPos, anchor

	if object._EditorOverride then
		size = object.AbsoluteSize or ZERO_V
		drawPos = object.AbsolutePosition or ZERO_V
	elseif object._LayoutControlled and object._LayoutRelativePosition then
		size = calculateResolvedSize(object, parentContentSize, window, dt, renderer, depth)
		anchor = object.AnchorPoint or ZERO_V
		local parentDrawPos = getAbsoluteDrawPos(object.Parent, window, dt, renderer, (depth or 0) + 1)
		drawPos = vector.create(
			parentDrawPos.X + object._LayoutRelativePosition.X - size.X * anchor.X,
			parentDrawPos.Y + object._LayoutRelativePosition.Y - size.Y * anchor.Y,
			0
		)
		if object.Parent and object.Parent.ClassName == "ScrollingFrame" then
			drawPos = vector.create(drawPos.X, drawPos.Y - (object.Parent.CanvasPosition or 0), 0)
		end
	else
		size = calculateResolvedSize(object, parentContentSize, window, dt, renderer, depth)
		drawPos = getAbsoluteDrawPos(object, window, dt, renderer, depth)
	end

	return drawPos, size
end

local function resolveGuiPoint(point)
	if type(point) ~= "table" then
		return nil
	end

	local x = point.X
	if x == nil then
		x = point.x
	end

	local y = point.Y
	if y == nil then
		y = point.y
	end

	if type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end

	return Vector2.new(x, y)
end

local function getGuiMetrics(object)
	if object.AbsolutePosition and object.AbsoluteSize then
		local pos = object.AbsolutePosition
		local size = object.AbsoluteSize
		return Vector2.new(pos.X, pos.Y), Vector2.new(size.X, size.Y)
	end

	if not object.Parent then
		return Vector2.Zero, Vector2.Zero
	end

	local drawPos, size = calculateDrawParams(object)
	return Vector2.new(drawPos.X, drawPos.Y), Vector2.new(size.X, size.Y)
end

local function getMousePos(window)
	if argon.GetMousePosition then
		local pos = argon:GetMousePosition()

		return vector.create(pos.X, pos.Y, 0)
	end
	return ZERO_V
end

local function makeRect(drawPos, size, color, isOutline)
	return {
		x = drawPos.X,
		y = drawPos.Y,
		width = size.X,
		height = size.Y,
		Color = color,
		isOutline = isOutline or false,
	}
end

local function resolveModifierRadius(modifier)
	if not modifier then
		return 0
	end
	local radius = modifier.CornerRadius
	if type(radius) == "table" then
		return radius.Offset or 0
	end
	return 0
end

local function getGuiShape(UICorner, UISquircle)
	local radius = resolveModifierRadius(UICorner)
	local exponent = 0
	local isSquircle = false

	if UISquircle then
		radius = resolveModifierRadius(UISquircle)
		exponent = if (UISquircle.Exponent or 0) > 0 then UISquircle.Exponent else 4
		isSquircle = true
	end

	return isSquircle, radius, exponent
end

local modifiers = {
	UIBackdrop = function(window, rect, modifier, isSquircle, radius, exponent)
		if not modifier or modifier.Enabled == false or (modifier.Blur or 0) <= 0 then
			return
		end

		rect.alpha = 1 - (modifier.Transparency or 0)
		local tint = toArgonColor(modifier.TintColor, modifier.TintTransparency or 1)
		if isSquircle then
			argon:DrawBackdropBlurSquircle(window, rect, modifier.Blur, radius, exponent, tint)
		else
			argon:DrawBackdropBlur(window, rect, modifier.Blur, radius, radius, tint)
		end
		rect.alpha = nil
	end,

	UIShadow = function(window, drawPos, size, modifier, isSquircle, radius, exponent)
		if not modifier or modifier.Enabled == false then
			return
		end

		argon:DrawUIShadow(
			window,
			makeRect(drawPos, size, toArgonColor(modifier.Color, modifier.Transparency)),
			radius,
			if isSquircle then exponent else 0,
			modifier.Offset or Vector2.new(0, 0),
			modifier.Blur or 8,
			modifier.Spread or 0
		)
	end,

	UISquircle = function(window, rect, radius, exponent, strokeWidth)
		argon:DrawSquircle(window, rect, radius, exponent, strokeWidth)
	end,

	UIStroke = function(window, rect, UICorner, UISquircle, stroke)
		if not stroke or stroke.Transparency == 1 or stroke.Thickness <= 0 then
			return
		end

		local isSquircle, radius, exponent = getGuiShape(UICorner, UISquircle)
		if isSquircle then
			argon:DrawSquircle(window, rect, radius, exponent, stroke.Thickness)
		elseif UICorner then
			argon:DrawRoundRectangle(window, rect, radius, radius, stroke.Thickness)
		else
			argon:DrawRectangle(window, rect)
		end
	end,
}

local propTable = {
	BaseClass = "GuiObject",
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(0, 100, 0, 100),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0,
	Visible = true,
	AbsolutePosition = nil,
	AbsoluteSize = nil,
	AutomaticSize = Enum.AutomaticSize.None,
	ClipsDescendants = false,
	ZIndex = 1,
	AnchorPoint = ZERO_V,
	MouseIsInObject = false,

	-- description: "Returns the absolute top-left position and size of the GUI object."
	-- args: "self: table"
	-- returns: "Vector2, Vector2"
	GetBounds = function(self)
		return getGuiMetrics(self)
	end,

	-- description: "Returns the absolute center point of the GUI object."
	-- args: "self: table"
	-- returns: "Vector2"
	GetCenter = function(self)
		local pos, size = getGuiMetrics(self)
		return Vector2.new(pos.X + size.X * 0.5, pos.Y + size.Y * 0.5)
	end,

	-- description: "Returns whether a screen-space point is inside the GUI object bounds."
	-- args: "self: table, point: Vector2"
	-- returns: "boolean"
	IsPointInside = function(self, point)
		local resolvedPoint = resolveGuiPoint(point)
		if not resolvedPoint then
			return false
		end

		local pos, size = getGuiMetrics(self)
		return resolvedPoint.X >= pos.X
			and resolvedPoint.X <= pos.X + size.X
			and resolvedPoint.Y >= pos.Y
			and resolvedPoint.Y <= pos.Y + size.Y
	end,

	-- description: "Converts a screen-space point into coordinates relative to the GUI object."
	-- args: "self: table, point: Vector2"
	-- returns: "Vector2?"
	GetRelativePoint = function(self, point)
		local resolvedPoint = resolveGuiPoint(point)
		if not resolvedPoint then
			return nil
		end

		local pos = getGuiMetrics(self)
		return Vector2.new(resolvedPoint.X - pos.X, resolvedPoint.Y - pos.Y)
	end,

	-- description: "Renders this GUI object's background, updates absolute bounds and hover state."
	-- args: "window: table, object: table, dt: number, renderer: table"
	-- returns: "vector?, vector?"
	render = function(window, object, dt, renderer)
		if not object.Visible then
			return
		end

		local drawPos, size = calculateDrawParams(object, window, dt, renderer)
		local mousePos = getMousePos(window)
		local mouseIsInObject = isMouseInRect(mousePos, drawPos, size)

		local UICorner = object:FindFirstChildOfClass("UICorner")
		local UIBackdrop = object:FindFirstChildOfClass("UIBackdrop")
		local UIShadow = object:FindFirstChildOfClass("UIShadow")
		local UISquircle = object:FindFirstChildOfClass("UISquircle")
		local UIStroke = object:FindFirstChildOfClass("UIStroke")
		local bgColor = toArgonColor(object.BackgroundColor3, object.BackgroundTransparency)
		local rect = makeRect(drawPos, size, bgColor)
		local isSquircle, radius, exponent = getGuiShape(UICorner, UISquircle)

		rawset(object, "MouseIsInObject", mouseIsInObject)
		rawset(object, "AbsolutePosition", drawPos)
		rawset(object, "AbsoluteSize", size)

		object.MouseEnter:FireOncePerPress("MouseEnter", mouseIsInObject)
		object.MouseLeave:FireOncePerPress("MouseLeave", not mouseIsInObject)

		if size.X > 0 and size.Y > 0 then
			modifiers.UIShadow(window, drawPos, size, UIShadow, isSquircle, radius, exponent)
			modifiers.UIBackdrop(window, rect, UIBackdrop, isSquircle, radius, exponent)

			if object.BackgroundTransparency ~= 1 then
				if isSquircle then
					modifiers.UISquircle(window, rect, radius, exponent)
				elseif UICorner then
					argon:DrawRoundRectangle(window, rect, radius, radius)
				else
					argon:DrawRectangle(window, rect)
				end
			end

			if UIStroke then
				local strokeRect = makeRect(drawPos, size, toArgonColor(UIStroke.Color, UIStroke.Transparency), true)
				modifiers.UIStroke(window, strokeRect, UICorner, UISquircle, UIStroke)
			end
		end

		return drawPos, size
	end,
}

local function createSignals()
	return {
		MouseEnter = signal.new(),
		MouseLeave = signal.new(),
		MouseMoved = signal.new(),
	}
end

return {
	class = "GuiObject",
	non_creatable = true,
	render = propTable.render,

	-- description: "Returns whether an object is parented directly under a GUI container."
	-- args: "object: table"
	-- returns: "boolean"
	IsParentGuiContainer = function(object)
		return object.Parent.BaseClass == "UIContainer"
	end,

	-- description: "Renders visible GUI children, applying ClipsDescendants as a plain rect clip."
	-- args: "window: table, object: table, dt: number, renderer: table"
	renderChildren = function(window, object, dt, renderer)
		local didClip = false

		if object.ClipsDescendants then
			local pos = object.AbsolutePosition or ZERO_V
			local size = object.AbsoluteSize or ZERO_V
			local UISquircle = object:FindFirstChildOfClass("UISquircle")
			local UICorner = object:FindFirstChildOfClass("UICorner")
			local rect = {
				x = pos.X,
				y = pos.Y,
				width = math.max(1, size.X),
				height = math.max(1, size.Y),
			}

			argon:Save(window)
			if UISquircle then
				local exponent = if (UISquircle.Exponent or 0) > 0 then UISquircle.Exponent else 4
				argon:ClipSquircle(window, rect, resolveModifierRadius(UISquircle), exponent)
			else
				local radius = resolveModifierRadius(UICorner)
				argon:ClipRoundRect(window, rect, radius, radius)
			end
			didClip = true
		end

		for _, child in pairs(object:GetChildren()) do
			if child.render then
				child.render(window, child, dt, renderer)
			end
		end

		if didClip then
			argon:Restore(window)
		end
	end,

	-- description: "Updates absolute position, absolute size, and hover state without drawing."
	-- args: "window: table, object: table, dt: number, renderer: table"
	-- returns: "vector, vector"
	calculatePositions = function(window, object, dt, renderer)
		local drawPos, size = calculateDrawParams(object, window, dt, renderer)
		local mousePos = getMousePos(window)
		local mouseIsInObject = isMouseInRect(mousePos, drawPos, size)

		rawset(object, "MouseIsInObject", mouseIsInObject)

		if object.MouseEnter then
			object.MouseEnter:FireOncePerPress("MouseEnter", mouseIsInObject)
		end
		if object.MouseLeave then
			object.MouseLeave:FireOncePerPress("MouseLeave", not mouseIsInObject)
		end

		rawset(object, "AbsolutePosition", drawPos)
		rawset(object, "AbsoluteSize", size)

		return drawPos, size
	end,

	callback = function(instance, renderer)
		local signals = createSignals()
		for k, v in pairs(signals) do
			propTable[k] = v
		end
		instance:SetProperties(propTable)
		return instance
	end,

	inherit = function(tble)
		local signals = createSignals()
		for k, v in pairs(signals) do
			tble[k] = v
		end
		for prop, val in pairs(propTable) do
			if not tble[prop] then
				tble[prop] = val
			end
		end
	end,
}
