-- AnchorUtils.lua
local AnchorUtils = {}

local Vector2 = require("@Vector2")

function AnchorUtils.GetAbsolutePosition(position, size, anchor, parentSize)
	-- Convert position to pixels relative to parent
	local posX = position.X.Scale * parentSize.X + position.X.Offset
	local posY = position.Y.Scale * parentSize.Y + position.Y.Offset

	-- Convert size to pixels relative to parent
	local sizeX = size.X.Scale * parentSize.X + size.X.Offset
	local sizeY = size.Y.Scale * parentSize.Y + size.Y.Offset

	-- Apply anchor point: draw position is position minus anchor offset
	local drawX = posX - sizeX * anchor.X
	local drawY = posY - sizeY * anchor.Y

	return Vector2.new(drawX, drawY)
end

function AnchorUtils.PositionToUDim2(absPosition, size, anchorPoint, parentSize)
	local sizeX = size.X.Scale * parentSize.X + size.X.Offset
	local sizeY = size.Y.Scale * parentSize.Y + size.Y.Offset

	local posX = (absPosition.X + sizeX * anchorPoint.X) / parentSize.X
	local posY = (absPosition.Y + sizeY * anchorPoint.Y) / parentSize.Y

	return {
		X = { Scale = posX, Offset = 0 },
		Y = { Scale = posY, Offset = 0 },
	}
end

function AnchorUtils.UDim2(scaleX, offsetX, scaleY, offsetY)
	return {
		X = { Scale = scaleX or 0, Offset = offsetX or 0 },
		Y = { Scale = scaleY or 0, Offset = offsetY or 0 },
	}
end

function AnchorUtils.Vector2(x, y)
	return { X = x or 0, Y = y or 0 }
end

return AnchorUtils
