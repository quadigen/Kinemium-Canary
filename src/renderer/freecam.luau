local Argon = require("@Argon")
local CFrame = require("@CFrame")
local Vector3 = require("@Vector3")

local MOUSE_SENSITIVITY = 0.003
local MOVE_VELOCITY = 10

local camPos = Vector3.new(0, 5, 10)
local yaw = 0
local pitch = 0

local function UpdateFreecam(delta: number, Kinemium_camera, window)
	if Argon:IsMouseButtonPressed(3) then
		Argon:DisableCursor(window)
	end
	if Argon:IsMouseButtonReleased(3) then
		Argon:EnableCursor(window)
	end

	if Argon:IsMouseButtonDown(3) then
		local md = Argon:GetMouseDelta()

		yaw += -md.x * MOUSE_SENSITIVITY
		pitch += md.y * MOUSE_SENSITIVITY

		local limit = math.rad(89)
		pitch = math.clamp(pitch, -limit, limit)
	end

	local rotation = CFrame.fromEulerAnglesYXZ(yaw, pitch, 0).Rotation
	local camCF = CFrame.new(camPos):WithRotation(rotation)

	local forward = camCF:GetLookVector()
	local right = camCF:GetRightVector()
	local up = Vector3.new(0, 1, 0)

	local sideway = (Argon:IsKeyDown(7) and 1 or 0)
		- (Argon:IsKeyDown(4) and 1 or 0)
		+ (Argon:IsKeyDown(79) and 1 or 0)
		- (Argon:IsKeyDown(80) and 1 or 0)

	local forwardInput = (Argon:IsKeyDown(26) and 1 or 0)
		- (Argon:IsKeyDown(22) and 1 or 0)
		+ (Argon:IsKeyDown(82) and 1 or 0)
		- (Argon:IsKeyDown(81) and 1 or 0)

	local vertical = (Argon:IsKeyDown(44) and 1 or 0) - (Argon:IsKeyDown(225) and 1 or 0)

	local wheelMove = Argon:GetMouseWheelMove()

	local move = (forward * forwardInput + right * sideway + up * vertical + forward * (wheelMove * 5.0))
		* MOVE_VELOCITY
		* delta

	camPos += move
	camCF = CFrame.new(camPos):WithRotation(rotation)

	local target = camPos + camCF:GetLookVector()

	Kinemium_camera.CFrame = camCF
	Kinemium_camera.Position = camPos

	return camPos, target
end

return {
	Update = UpdateFreecam,
	SetSpeed = function(v)
		MOVE_VELOCITY = v
	end,
	SetSensitivity = function(v)
		MOUSE_SENSITIVITY = v
	end,
	GetPos = function()
		return camPos
	end,
	ToVectorShader = function()
		return { camPos.X, camPos.Y, camPos.Z }
	end,
	SetCFrame = function(cf)
		camPos = cf.Position
		local y, p = cf:GetYawPitchRoll()
		yaw, pitch = y, p
	end,
	GetCFrame = function()
		return CFrame.new(camPos):WithRotation(CFrame.fromEulerAnglesYXZ(yaw, pitch, 0).Rotation)
	end,
}
