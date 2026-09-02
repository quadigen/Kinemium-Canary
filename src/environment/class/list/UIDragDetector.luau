-- description: "A drag detection component for UI elements."
local Vector2 = require("@Vector2")
local Vector3 = require("@Vector3")
local UDim2 = require("@UDim2")
local Argon = require("@Argon")
local Enum = require("@EnumMap")
local MouseCursor = require("@Kinemium.MouseCursor")

local function makeRect(x, y, width, height)
	return { x = x, y = y, width = width, height = height }
end

local function mouseInRect(rect)
	local mouse = Argon:GetMousePosition()
	return mouse.X >= rect.x and mouse.X <= rect.x + rect.width
		and mouse.Y >= rect.y and mouse.Y <= rect.y + rect.height
end

local ZERO_V2 = Vector2.new(0, 0)

local function getParentMetrics(parent, window)
	local parentAbsPos = ZERO_V2
	local parentSize = ZERO_V2

	if not parent then
		return parentAbsPos, parentSize
	end

	if parent.AbsolutePosition then
		parentAbsPos = parent.AbsolutePosition
	elseif parent.RenderOffset then
		parentAbsPos = parent.RenderOffset
	end

	if parent.AbsoluteSize then
		parentSize = parent.AbsoluteSize
	elseif parent.Size and parent.Size.ToPixels then
		parentSize = parent.Size:ToPixels(Vector2.new(Argon:GetRenderWidth(window), Argon:GetRenderHeight(window)))
	end

	return parentAbsPos, parentSize
end

local propTable = {
	Name = "UIDragDetector",
	isDragging = false,
	RespectScreenBounds = true,
	dragOffset = Vector3.new(0, 0, 0), -- why is this a vector3? no idea
}

return {
	class = "UIDragDetector",

	callback = function(instance)
		propTable.render = function(lib, object, dt, structs, renderer)
			if object.Parent then
				local adornee = object.Parent
				if adornee.BaseClass == "GuiObject" then
					local absolutePosition, absoluteSize = adornee.AbsolutePosition, adornee.AbsoluteSize

					if not absolutePosition or not absoluteSize then
						return
					end

					if instance.isDragging == true then
						local mousePos = Argon:GetMousePosition()
						local newAbsX = mousePos.X - instance.dragOffset.X
						local newAbsY = mousePos.Y - instance.dragOffset.Y

						if instance.RespectScreenBounds then
							local screenW = Argon:GetRenderWidth(renderer.Window)
							local screenH = Argon:GetRenderHeight(renderer.Window)
							newAbsX = math.clamp(newAbsX, 0, screenW - absoluteSize.X)
							newAbsY = math.clamp(newAbsY, 0, screenH - absoluteSize.Y)
						end

						local parentAbsPos, parentSize = getParentMetrics(adornee.Parent, renderer.Window)
						local anchor = adornee.AnchorPoint or ZERO_V2
						local relativeX = newAbsX - parentAbsPos.X + absoluteSize.X * anchor.X
						local relativeY = newAbsY - parentAbsPos.Y + absoluteSize.Y * anchor.Y
						local scaleXOffset = parentSize.X * adornee.Position.X.Scale
						local scaleYOffset = parentSize.Y * adornee.Position.Y.Scale

						adornee.Position = UDim2.new(
							adornee.Position.X.Scale,
							relativeX - scaleXOffset,
							adornee.Position.Y.Scale,
							relativeY - scaleYOffset
						)

						MouseCursor.request(Enum.KinemiumMouseCursor.MOUSE_CURSOR_RESIZE_ALL.Value)
					end

					local new = makeRect(absolutePosition.X, absolutePosition.Y, absoluteSize.X, absoluteSize.Y)
					if mouseInRect(new) then
						if Argon:IsMouseButtonDown(Argon.MouseButton.Left) then
							if not instance.isDragging then
								local mousePos = Argon:GetMousePosition()
								instance.dragOffset =
									Vector3.new(mousePos.X - absolutePosition.X, mousePos.Y - absolutePosition.Y, 0)
							end
							instance.isDragging = true
						elseif Argon:IsMouseButtonReleased(Argon.MouseButton.Left) then
							instance.isDragging = false
							MouseCursor.request(Enum.KinemiumMouseCursor.MOUSE_CURSOR_DEFAULT.Value)
						end
					end
				end
			end
		end

		instance:SetProperties(propTable)

		return instance
	end,

	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
