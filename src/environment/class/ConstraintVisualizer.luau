-- Filament-backed visualizers shared by every 3D physics constraint.
local Vector3 = require("@Vector3")
local CFrame = require("@CFrame")
local Color3 = require("@Color3")

local ConstraintVisualizer = {}
local meshCaches = setmetatable({}, { __mode = "k" })

local ENDPOINT0 = Color3.fromRGB(0, 220, 255)
local ENDPOINT1 = Color3.fromRGB(255, 70, 210)
local DISABLED = Color3.fromRGB(120, 120, 120)
local LIMIT = Color3.fromRGB(255, 65, 65)
local MAX_VISUALIZER_DISTANCE_SQUARED = 64 * 64

local function meshesFor(renderer, argon)
	local cache = meshCaches[renderer]
	if not cache then
		cache = {
			cube = argon:CreateMesh(renderer.Window, "cube"),
			sphere = argon:CreateMesh(renderer.Window, "sphere"),
		}
		meshCaches[renderer] = cache
	end
	return cache
end

local function drawMesh(argon, renderer, mesh, cframe, scale, color)
	if not mesh or not mesh._handle then
		return
	end
	argon:DrawMesh(
		renderer.Window,
		mesh,
		{ R = color.R, G = color.G, B = color.B, A = 1 },
		0.9,
		0,
		cframe:ToEngineMatrix(scale),
		false,
		false,
		false,
		nil,
		5,
		1
	)
end

local function drawPoint(argon, renderer, meshes, position, color, radius)
	local diameter = (radius or 0.13) * 2
	drawMesh(argon, renderer, meshes.sphere, CFrame.new(position), Vector3.new(diameter, diameter, diameter), color)
end

local function drawLine(argon, renderer, meshes, from, to, color, thickness)
	local delta = to - from
	local length = delta:Magnitude()
	if length < 0.0001 then
		return
	end
	local width = thickness or 0.045
	local transform = CFrame.lookAt((from + to) * 0.5, to)
	drawMesh(argon, renderer, meshes.cube, transform, Vector3.new(width, width, length), color)
end

local function endpoint(instance, index)
	local attachment = instance[`Attachment{index}`]
	if attachment and attachment.Parent and attachment.Parent.CFrame then
		local parent = attachment.Parent
		return parent.CFrame * attachment.Position,
			parent.CFrame:VectorToWorldSpace(attachment.Axis):Unit(),
			parent.CFrame:VectorToWorldSpace(attachment.SecondaryAxis):Unit()
	end
	local part = instance[`Part{index}`]
	if part and part.CFrame then
		return part.CFrame.Position,
			part.CFrame:VectorToWorldSpace(Vector3.new(1, 0, 0)):Unit(),
			part.CFrame:VectorToWorldSpace(Vector3.new(0, 1, 0)):Unit()
	end
	return nil, nil, nil
end

local function perpendicularBasis(axis)
	local reference = if math.abs(axis:Dot(Vector3.new(0, 1, 0))) < 0.9
		then Vector3.new(0, 1, 0)
		else Vector3.new(1, 0, 0)
	local side = axis:Cross(reference):Unit()
	return side, axis:Cross(side):Unit()
end

local function drawRing(argon, renderer, meshes, center, axis, radius, color, segments)
	local side, up = perpendicularBasis(axis:Unit())
	local previous = nil
	for segment = 0, segments or 20 do
		local angle = segment / (segments or 20) * math.pi * 2
		local point = center + side * math.cos(angle) * radius + up * math.sin(angle) * radius
		if previous then
			drawLine(argon, renderer, meshes, previous, point, color, 0.035)
		end
		previous = point
	end
end

local function drawSpring(argon, renderer, meshes, from, to, color)
	local delta = to - from
	local length = delta:Magnitude()
	if length < 0.0001 then
		return
	end
	local axis = delta / length
	local side, up = perpendicularBasis(axis)
	local previous = from
	local segments = 16
	for segment = 1, segments do
		local alpha = segment / segments
		local radius = if segment == segments then 0 else 0.22
		local angle = alpha * math.pi * 10
		local point = from + delta * alpha + side * math.cos(angle) * radius + up * math.sin(angle) * radius
		drawLine(argon, renderer, meshes, previous, point, color, 0.04)
		previous = point
	end
end

local function drawAttachmentAxes(argon, renderer, meshes, position, axis, secondary, color)
	drawPoint(argon, renderer, meshes, position, color, 0.16)
	drawLine(argon, renderer, meshes, position - axis * 0.35, position + axis * 0.35, color, 0.045)
	drawLine(argon, renderer, meshes, position, position + secondary * 0.3, color, 0.035)
end

local function render(instance, renderer, argon, meshes)
	if instance.Visible == false then
		return
	end

	local p0, axis0, secondary0 = endpoint(instance, 0)
	local p1, axis1, secondary1 = endpoint(instance, 1)
	local camera = renderer.GetActiveCamera and renderer:GetActiveCamera() or nil
	local cameraPosition = camera and camera.CFrame and camera.CFrame.Position
	if
		cameraPosition
		and (not p0 or cameraPosition:DistanceSquared(p0) > MAX_VISUALIZER_DISTANCE_SQUARED)
		and (not p1 or cameraPosition:DistanceSquared(p1) > MAX_VISUALIZER_DISTANCE_SQUARED)
	then
		return
	end
	if p0 then
		drawAttachmentAxes(argon, renderer, meshes, p0, axis0, secondary0, ENDPOINT0)
	end
	if p1 then
		drawAttachmentAxes(argon, renderer, meshes, p1, axis1, secondary1, ENDPOINT1)
	end
	if not p0 or not p1 then
		return
	end
	local color = if instance.Enabled == false then DISABLED else (instance.Color or Color3.fromRGB(255, 210, 40))
	local className = instance.ClassName
	if className == "SpringConstraint" then
		drawSpring(argon, renderer, meshes, p0, p1, color)
	elseif className == "RopeConstraint" then
		local previous = p0
		for segment = 1, 8 do
			local alpha = segment / 8
			local sag = math.sin(alpha * math.pi) * math.min(0.5, p0:Distance(p1) * 0.08)
			local point = p0:Lerp(p1, alpha) - Vector3.new(0, sag, 0)
			drawLine(argon, renderer, meshes, previous, point, color, 0.05)
			previous = point
		end
	elseif className == "HingeConstraint" or className == "TorsionSpringConstraint" then
		drawLine(argon, renderer, meshes, p0 - axis0 * 0.8, p0 + axis0 * 0.8, color, 0.07)
		drawRing(argon, renderer, meshes, p0, axis0, 0.48, color, 16)
		drawLine(argon, renderer, meshes, p0, p1, color, 0.035)
	elseif className == "BallSocketConstraint" then
		drawLine(argon, renderer, meshes, p0, p1, color, 0.04)
		drawRing(argon, renderer, meshes, p0, axis0, 0.36, color, 12)
		drawRing(argon, renderer, meshes, p0, secondary0, 0.36, color, 12)
		drawRing(argon, renderer, meshes, p0, axis0:Cross(secondary0):Unit(), 0.36, color, 12)
	elseif className == "PrismaticConstraint" or className == "CylindricalConstraint" then
		local lower = if instance.LimitsEnabled then (instance.LowerLimit or -2) else -2
		local upper = if instance.LimitsEnabled then (instance.UpperLimit or 2) else 2
		drawLine(argon, renderer, meshes, p0 + axis0 * lower, p0 + axis0 * upper, color, 0.07)
		drawPoint(argon, renderer, meshes, p0 + axis0 * lower, LIMIT, 0.1)
		drawPoint(argon, renderer, meshes, p0 + axis0 * upper, LIMIT, 0.1)
		drawLine(argon, renderer, meshes, p0, p1, color, 0.035)
		if className == "CylindricalConstraint" then
			drawRing(argon, renderer, meshes, p0, axis0, 0.35, color, 12)
		end
	elseif className == "UniversalConstraint" then
		drawLine(argon, renderer, meshes, p0 - axis0 * 0.6, p0 + axis0 * 0.6, color, 0.07)
		drawLine(argon, renderer, meshes, p0 - secondary0 * 0.6, p0 + secondary0 * 0.6, color, 0.07)
		drawRing(argon, renderer, meshes, p0, axis0:Cross(secondary0):Unit(), 0.38, color, 12)
		drawLine(argon, renderer, meshes, p0, p1, color, 0.035)
	elseif className == "PlaneConstraint" then
		for offset = -1, 1 do
			drawLine(
				argon,
				renderer,
				meshes,
				p0 + axis0 * -0.8 + secondary0 * offset * 0.4,
				p0 + axis0 * 0.8 + secondary0 * offset * 0.4,
				color,
				0.035
			)
			drawLine(
				argon,
				renderer,
				meshes,
				p0 + secondary0 * -0.8 + axis0 * offset * 0.4,
				p0 + secondary0 * 0.8 + axis0 * offset * 0.4,
				color,
				0.035
			)
		end
		drawLine(argon, renderer, meshes, p0, p1, color, 0.035)
	elseif className == "Weld" or className == "WeldConstraint" or className == "RigidConstraint" then
		-- A thick gold bar plus cyan/magenta endpoint frames makes the exact
		-- pair of connected parts/attachments unambiguous.
		drawLine(argon, renderer, meshes, p0, p1, color, 0.1)
	else
		drawLine(argon, renderer, meshes, p0, p1, color, 0.065)
	end
end

function ConstraintVisualizer.Attach(instance, renderer)
	if _G.IsHeadless or not renderer or not renderer.Window or not renderer.Pool then
		return nil
	end
	local argon = require("@Argon")
	local meshes = meshesFor(renderer, argon)
	local renderId = renderer.Pool.new("gizmo", function()
		render(instance, renderer, argon, meshes)
	end, 50)

	if instance.Destroying then
		instance.Destroying:Connect(function()
			if renderId then
				renderer.Pool.Destroy(renderId)
				renderId = nil
			end
		end)
	end
	return renderId
end

return ConstraintVisualizer
