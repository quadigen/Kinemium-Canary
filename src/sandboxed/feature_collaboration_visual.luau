if not FlagExists("feature_collaboration_visual") then
	return
end

local NetworkService = game:GetService("NetworkService")
local role = GetFlagValue("visual-role") or "host"
local camera = workspace.CurrentCamera or workspace:FindFirstChildOfClass("Camera")
assert(camera, "The collaboration visual test requires a workspace Camera")

if role == "host" then
	camera.CFrame = CFrame.lookAt(Vector3.new(11, 8, 13), Vector3.new(0, 1.5, 0))
	local floor = Instance.new("Part")
	floor.Name = "CollaborationFloor"
	floor.Size = Vector3.new(18, 0.5, 18)
	floor.CFrame = CFrame.new(0, -0.25, 0)
	floor.Color = Color3.fromRGB(38, 48, 66)
	floor.Anchored = true
	floor.Parent = workspace
	local marker = Instance.new("Part")
	marker.Name = "SharedPart"
	marker.Size = Vector3.new(2.5, 2.5, 2.5)
	marker.CFrame = CFrame.new(0, 1.25, -3)
	marker.Color = Color3.fromRGB(70, 205, 255)
	marker.Anchored = true
	marker.Parent = workspace
	repeat
		task.wait()
	until NetworkService.HostCollaboration
	local invite, reason = NetworkService:HostCollaboration({
		BindAddress = "127.0.0.1",
		InviteAddress = "127.0.0.1",
		Port = tonumber(GetFlagValue("port")) or 12473,
		Name = "VisualHost",
	})
	assert(invite, reason)
	print("VISUAL_INVITE " .. invite.Code)
	print("VISUAL_READY collaboration-host")
else
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 2.2, 2), Vector3.new(0, 1.5, -4))
	repeat
		task.wait()
	until NetworkService.JoinCollaboration
	local connected, reason = NetworkService:JoinCollaboration(GetFlagValue("invite"), "VisualGuest")
	assert(connected, reason)
	print("VISUAL_READY collaboration-guest")
end
