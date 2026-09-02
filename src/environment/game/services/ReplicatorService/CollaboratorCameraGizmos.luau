local Argon = require("@Argon")
local CFrame = require("@CFrame")
local Color3 = require("@Color3")
local Vector3 = require("@Vector3")

local CollaboratorCameraGizmos = {}
CollaboratorCameraGizmos.__index = CollaboratorCameraGizmos

local function colorFor(key)
	local hash = 2166136261
	for index = 1, #key do
		hash = bit32.bxor(hash, string.byte(key, index))
		hash = (hash * 16777619) % 2147483647
	end
	local hue = (hash % 360) / 360
	return Color3.fromHSV(hue, 0.72, 1)
end

local function drawMesh(self, cframe, scale, color)
	if not self.mesh or not self.mesh._handle then
		return
	end
	Argon:DrawMesh(
		self.renderer.Window,
		self.mesh,
		{ R = color.R, G = color.G, B = color.B, A = 1 },
		0.35,
		0.15,
		cframe:ToEngineMatrix(scale),
		false,
		false,
		false,
		nil,
		2,
		1
	)
end

local function drawLine(self, from, to, color, thickness)
	local delta = to - from
	local length = delta:Magnitude()
	if length < 0.0001 then
		return
	end
	drawMesh(self, CFrame.lookAt((from + to) * 0.5, to), Vector3.new(thickness, thickness, length), color)
end

local function drawCamera(self, state)
	local cframe = state.cframe
	local color = state.color
	local position = cframe.Position
	local forward = cframe:GetLookVector()
	local right = cframe:GetRightVector()
	local up = cframe:GetUpVector()
	local lensCenter = position + forward * 0.7
	local halfWidth, halfHeight = 0.52, 0.32
	local corners = {
		lensCenter + right * halfWidth + up * halfHeight,
		lensCenter - right * halfWidth + up * halfHeight,
		lensCenter - right * halfWidth - up * halfHeight,
		lensCenter + right * halfWidth - up * halfHeight,
	}

	drawMesh(self, cframe, Vector3.new(0.5, 0.32, 0.36), color)
	for index = 1, 4 do
		drawLine(self, position, corners[index], color, 0.055)
		drawLine(self, corners[index], corners[index % 4 + 1], color, 0.055)
	end
	-- The raised chevron makes the camera's roll and facing direction readable.
	local top = lensCenter + up * 0.62
	drawLine(self, corners[1], top, color, 0.06)
	drawLine(self, top, corners[2], color, 0.06)
end

function CollaboratorCameraGizmos.new(renderer)
	local self = setmetatable({ renderer = renderer, states = {} }, CollaboratorCameraGizmos)
	if _G.IsHeadless or not renderer or not renderer.Window or not renderer.Pool then
		return self
	end
	self.mesh = Argon:CreateMesh(renderer.Window, "cube")
	self.renderId = renderer.Pool.new("gizmo", function()
		for _, state in pairs(self.states) do
			drawCamera(self, state)
		end
	end, 80)
	return self
end

function CollaboratorCameraGizmos:Update(id, name, cframe)
	if type(id) ~= "string" or type(name) ~= "string" or typeof(cframe) ~= "CFrame" then
		return false
	end
	self.states[id] = {
		name = name,
		cframe = cframe,
		color = colorFor(id .. name),
		updatedAt = os.clock(),
	}
	return true
end

function CollaboratorCameraGizmos:Remove(id)
	self.states[id] = nil
end

function CollaboratorCameraGizmos:Destroy()
	if self.renderId then
		self.renderer.Pool.Destroy(self.renderId)
		self.renderId = nil
	end
	if self.mesh and self.mesh._handle and Argon.DestroyMesh then
		Argon:DestroyMesh(self.renderer.Window, self.mesh)
	end
	table.clear(self.states)
end

return CollaboratorCameraGizmos
