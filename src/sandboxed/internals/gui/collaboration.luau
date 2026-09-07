local StudioThemeService = game:GetService("StudioThemeService")
local NetworkService = game:GetService("NetworkService")
local Immco = require("@Immco")
local Argon = require("@Argon")

if IsServer or IsClient then
	return
end

repeat
	task.wait()
until game.CoreGui:FindFirstChild("Studio") and ishared.StudioSystem

local theme = StudioThemeService.SelectedTheme
local retained = {}
local visible = false
local status = "Offline"

ishared.StudioSystem:Connect(function(route)
	if route == "toggle_collaboration" then
		visible = not visible
	end
end)

local function button(rect, label, callback, dt)
	local hovered = renderer:isMouseInRect(rect)
	Immco.TextButton({
		x = rect.x,
		y = rect.y,
		width = rect.width,
		height = rect.height,
		text = label,
		Color = hovered and theme.ThirdColor or theme.SecondaryColor,
		TextColor = theme.TextColor,
		BgVisible = true,
		theme = theme,
		engine_window = renderer.Window,
	}, dt)
	if renderer:HasClicked(rect) then
		callback()
	end
end

renderer.Pool.new("2da", function(lib)
	if not visible then
		return
	end

	local dt = lib.dt
	local windowWidth, windowHeight = Argon:GetWindowPixelSize(renderer.Window)
	if not windowWidth or not windowHeight then
		return
	end
	local width, height = 520, 280
	local x = math.floor((windowWidth - width) / 2)
	local y = math.floor((windowHeight - height) / 2)

	Immco.Widget({
		x = x,
		y = y,
		width = width,
		height = height,
		title = "Collaboration",
		theme = theme,
		engine_window = renderer.Window,
		renderer = renderer,
		Draggable = true,
		RetainedStorage = retained,
		id = "collaboration-widget",
		OnMoved = function(nextX, nextY)
			x, y = nextX, nextY
		end,
		callback = function() end,
	}, dt)

	Immco.Text({
		x = x + 18,
		y = y + 62,
		text = "Session: " .. tostring(NetworkService.CollaborationMode or status),
		Color = theme.TextColor,
		TextSize = 16,
		theme = theme,
		engine_window = renderer.Window,
	}, dt)

	local invite = NetworkService.CurrentInvite
	local inviteText = invite and invite.Code or "Invite codes always use kinemiumcollab.quadigen.com"
	Immco.TextInput({
		x = x + 18,
		y = y + 82,
		width = width - 36,
		height = 38,
		text = inviteText,
		ReadOnly = true,
		RetainedStorage = retained,
		id = "collaboration-invite",
		renderer = renderer,
		engine_window = renderer.Window,
		theme = theme,
		Color = theme.SecondaryColor,
		TextColor = theme.TextColor,
	}, dt)
	if retained["collaboration-invite"] then
		retained["collaboration-invite"].text = inviteText
	end

	button({ x = x + 18, y = y + 136, width = 150, height = 38 }, "Host", function()
		local created, reason = NetworkService:HostCollaboration({
			BindAddress = GetFlagValue("address") or "0.0.0.0",
			Port = tonumber(GetFlagValue("port")) or 1234,
		})
		if created then
			Argon:SetClipboard(created.Code)
			status = "Hosting; invite copied"
		else
			status = "Host failed: " .. tostring(reason)
		end
	end, dt)

	button({ x = x + 177, y = y + 136, width = 150, height = 38 }, "Join Clipboard", function()
		local joined, reason =
			NetworkService:JoinCollaboration(Argon:GetClipboard(), GetFlagValue("username") or "Collaborator")
		status = joined and "Connected" or ("Join failed: " .. tostring(reason))
	end, dt)

	button({ x = x + 336, y = y + 136, width = 166, height = 38 }, "Stop", function()
		NetworkService:StopCollaboration()
		status = "Offline"
	end, dt)

	button({ x = x + 18, y = y + 184, width = 230, height = 38 }, "Copy Invite", function()
		local current = NetworkService.CurrentInvite
		if current then
			Argon:SetClipboard(current.Code)
			status = "Invite copied"
		else
			status = "Host a session first"
		end
	end, dt)

	button({ x = x + 272, y = y + 184, width = 230, height = 38 }, "Close", function()
		visible = false
	end, dt)

	Immco.Text({
		x = x + 18,
		y = y + 250,
		text = status,
		Color = theme.SecondaryTextColor,
		TextSize = 14,
		theme = theme,
		engine_window = renderer.Window,
	}, dt)
end)
