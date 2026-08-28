-- description: "An interactive Filament transform gizmo attached to an Adornee."
local Color3 = require("@Color3")
local signal = require("@Kinemium.signal")
local Enum = require("@EnumMap")
local argon = require("@Argon")

local propTable = {
	Color = Color3.new(0.5, 0.5, 0.5),
	Adornee = nil,
	CastShadows = false,
	Name = "Handles",
	Style = Enum.HandlesStyle.Rotation,
	RotationSnap = 0,
}

local signalNames = { "MouseButton1Down", "MouseButton1Up", "MouseDrag", "MouseEnter", "MouseLeave" }

local function styleName(style)
	return style and style.Name or "Movement"
end

local function gizmoType(style)
	local name = styleName(style)
	if name == "Resize" then
		return "scale"
	elseif name == "Rotation" then
		return "rotate"
	end
	return "move"
end

local function axisNormalId(axis)
	if axis == 1 then
		return Enum.NormalId.Right
	elseif axis == 2 then
		return Enum.NormalId.Top
	elseif axis == 3 then
		return Enum.NormalId.Back
	end
	return nil
end

return {
	class = "Handles",

	callback = function(instance, renderer)
		for _, property in ipairs(signalNames) do
			instance:SetProperty(property, signal.new())
		end
		instance:SetProperties(propTable)

		local hoveredAxis = 0
		local selectedAxis = 0
		local dragStartX = 0
		local dragStartY = 0
		local lastDragDelta = nil
		local currentType = nil
		local renderId = nil

		local function replaceGizmo()
			local nextType = gizmoType(instance.Style)
			if currentType == nextType and instance._gizmo and instance._gizmo._handle then
				return
			end
			if instance._gizmo then
				argon:DestroyGizmo(renderer.Window, instance._gizmo)
			end
			instance._gizmo = argon:CreateGizmo(renderer.Window, nextType)
			currentType = nextType
			hoveredAxis = 0
			selectedAxis = 0
		end

		replaceGizmo()

		renderId = renderer.Pool.new("gizmo", function()
			local adornee = instance.Adornee
			if not adornee or not adornee.CFrame then
				if hoveredAxis ~= 0 then
					instance.MouseLeave:Fire(axisNormalId(hoveredAxis))
					hoveredAxis = 0
				end
				return
			end

			replaceGizmo()
			local gizmo = instance._gizmo
			if not gizmo or not gizmo._handle then
				return
			end
			local mat4 = adornee.CFrame:ToEngineMatrix()
			local mouse = argon:GetMousePosition()
			local pickedAxis = argon:PickGizmo(renderer.Window, gizmo, mat4, mouse.X, mouse.Y)

			if selectedAxis == 0 and pickedAxis ~= hoveredAxis then
				if hoveredAxis ~= 0 then
					instance.MouseLeave:Fire(axisNormalId(hoveredAxis))
				end
				hoveredAxis = pickedAxis
				if hoveredAxis ~= 0 then
					instance.MouseEnter:Fire(axisNormalId(hoveredAxis))
				end
			end

			if selectedAxis == 0 and hoveredAxis ~= 0 and argon:IsMouseButtonPressed(argon.MouseButton.Left) then
				selectedAxis = hoveredAxis
				dragStartX = mouse.X
				dragStartY = mouse.Y
				lastDragDelta = nil
				instance.MouseButton1Down:Fire(axisNormalId(selectedAxis))
			end

			if selectedAxis ~= 0 and argon:IsMouseButtonDown(argon.MouseButton.Left) then
				local delta = argon:GetGizmoDragDelta(
					renderer.Window,
					gizmo,
					mat4,
					selectedAxis,
					dragStartX,
					dragStartY,
					mouse.X,
					mouse.Y
				)
				if currentType == "rotate" then
					local snapDegrees = math.max(0, instance.RotationSnap or 0)
					if snapDegrees > 0 then
						local snapRadians = math.rad(snapDegrees)
						delta = math.round(delta / snapRadians) * snapRadians
					end
				end
				if delta ~= lastDragDelta then
					lastDragDelta = delta
					instance.MouseDrag:Fire(axisNormalId(selectedAxis), delta)
				end
			end

			if selectedAxis ~= 0 and argon:IsMouseButtonReleased(argon.MouseButton.Left) then
				local releasedAxis = selectedAxis
				selectedAxis = 0
				lastDragDelta = nil
				instance.MouseButton1Up:Fire(axisNormalId(releasedAxis))
			end

			argon:DrawGizmo(renderer.Window, gizmo, mat4, hoveredAxis, selectedAxis)
		end)

		instance.Changed:Connect(function(property)
			if property == "Style" then
				replaceGizmo()
			end
		end)

		instance.Destroying:Connect(function()
			if renderId then
				renderer.Pool.Destroy(renderId)
				renderId = nil
			end
			if instance._gizmo then
				argon:DestroyGizmo(renderer.Window, instance._gizmo)
				instance._gizmo = nil
			end
			for _, property in ipairs(signalNames) do
				local event = instance[property]
				if event and event.Destroy then
					event:Destroy()
				end
			end
		end)

		return instance
	end,

	inherit = function(tble)
		for property, value in pairs(propTable) do
			if tble[property] == nil then
				tble[property] = value
			end
		end
	end,
}
