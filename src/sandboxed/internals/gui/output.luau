local kilang = _G.kilang
if not kilang or type(kilang.threads) ~= "table" then
	local ok, mod = pcall(require, "@Kilang")
	if ok and mod and type(mod.threads) == "table" then
		kilang = mod
	else
		ok, mod = pcall(require, "@kilang")
		if ok and mod and type(mod.threads) == "table" then
			kilang = mod
		end
	end
end

local StudioThemeService = game:GetService("StudioThemeService")
local LogService = game:GetService("LogService")
local ProfilerService = game:GetService("ProfilerService")
local Immco = require("@Immco")
local Argon = require("@Argon")

local theme = StudioThemeService.SelectedTheme
local storage = {}

if IsServer or IsClient then
	return
end

repeat
	task.wait()
until game.CoreGui:FindFirstChild("Studio")

local Output = Instance.new("Frame")
Output.Name = "Output"
Output.Size = theme.OutputCoordinates.Size
Output.Position = theme.OutputCoordinates.Position
Output.Parent = game.CoreGui:FindFirstChild("Studio")
Output.BackgroundTransparency = 1

local tabs = {
	{ title = "Output" },
	{ title = "Threads" },
	{ title = "Stack Trace" },
	{ title = "Profiler" },
}
local activeTab = 1
local search = ""
local contentHeight = 0
local expandedThread = nil
local lastMousePressed = false

local THREAD_ROW_H = 28
local THREAD_TRACE_H = 18
local THREAD_HEADER_H = 28

local STATUS_COLORS = {
	running = { R = 0.35, G = 0.85, B = 0.45, A = 1 },
	suspended = { R = 0.95, G = 0.75, B = 0.25, A = 1 },
	["active (render loop)"] = { R = 0.35, G = 0.75, B = 0.95, A = 1 },
	normal = { R = 0.45, G = 0.65, B = 0.95, A = 1 },
	completed = { R = 0.55, G = 0.55, B = 0.55, A = 1 },
	dead = { R = 0.55, G = 0.55, B = 0.55, A = 1 },
	unavailable = { R = 0.55, G = 0.55, B = 0.55, A = 1 },
}

local function threadStatus(thread, id)
	if type(thread) ~= "thread" then
		return "unavailable"
	end
	local ok, status = pcall(coroutine.status, thread)
	if ok and status == "dead" then
		if id and (string.find(id, "gui/", 1, true) or string.find(id, "internals/", 1, true)) then
			return "active (render loop)"
		end
		return "completed"
	end
	return ok and status or "unavailable"
end

local function threads()
	local result = {}
	local seen = {}

	local targetKilang = kilang or _G.kilang
	if targetKilang then
		local activeMap = targetKilang.getThreads and targetKilang:getThreads()
		if activeMap then
			for id, entry in pairs(activeMap) do
				local idStr = tostring(id)
				seen[idStr] = true
				table.insert(result, { id = idStr, thread = entry.thread, status = threadStatus(entry.thread, idStr) })
			end
		elseif targetKilang.threads then
			for id, thread in pairs(targetKilang.threads) do
				local idStr = tostring(id)
				seen[idStr] = true
				table.insert(result, { id = idStr, thread = thread, status = threadStatus(thread, idStr) })
			end
		end
	end

	pcall(function()
		local ScriptContext = game:GetService("ScriptContext")
		if ScriptContext and ScriptContext.GetActiveThreads then
			local active = ScriptContext:GetActiveThreads()
			if type(active) == "table" then
				for lang, langThreads in pairs(active) do
					if type(langThreads) == "table" then
						for uniqueId, thread in pairs(langThreads) do
							local idStr = `Script [{lang}]: {tostring(uniqueId)}`
							if not seen[idStr] and not seen[uniqueId] then
								seen[idStr] = true
								table.insert(
									result,
									{ id = idStr, thread = thread, status = threadStatus(thread, idStr) }
								)
							end
						end
					end
				end
			end
		end
	end)

	local function statusPriority(status)
		if status == "running" then
			return 1
		elseif status == "suspended" then
			return 2
		elseif status == "active (render loop)" then
			return 3
		elseif status == "normal" then
			return 4
		else
			return 5
		end
	end

	table.sort(result, function(a, b)
		local pA = statusPriority(a.status)
		local pB = statusPriority(b.status)
		if pA ~= pB then
			return pA < pB
		end
		return a.id < b.id
	end)
	return result
end

local function stackTrace(thread)
	if type(thread) ~= "thread" then
		return "Stack trace unavailable: this entry has no coroutine handle."
	end
	local ok, trace = pcall(function()
		return debug.traceback(thread, "", 0)
	end)
	if ok and type(trace) == "string" and trace ~= "" then
		return trace
	end
	return "Stack trace unavailable for this coroutine (" .. tostring(trace) .. ")."
end

local function drawTable(params, dt, id, data, widths)
	Immco.Table({
		x = params.x + 8,
		y = params.y + 8,
		width = params.width - 16,
		engine_window = renderer.Window,
		theme = theme,
		RetainedStorage = storage,
		id = id,
		renderer = renderer,
		Data = data,
		HasHeader = true,
		ColumnWidths = widths,
		MaxVisibleRows = math.max(1, math.floor((params.height - 44) / 28)),
	}, dt)
end

local function drawOutput(params, dt)
	Immco.TextInput({
		x = params.x + 80,
		y = params.y - 28,
		width = params.width - 90,
		height = 20,
		id = "OutputSearch",
		RetainedStorage = storage,
		renderer = renderer,
		theme = theme,
		Color = { R = 0.15, G = 0.15, B = 0.15, A = 1 },
		FocusColor = theme.InputFocusColor,
		TextColor = theme.TextColor,
		PlaceholderColor = theme.InputPlaceholderColor,
		placeholder = "Search Output..",
		OnSubmit = function(text)
			search = string.lower(text)
		end,
		engine_window = renderer.Window,
	}, dt)

	local visibleLogs = {}
	for _, log in ipairs(LogService.GetLogHistory()) do
		local message = tostring(log.message)
		if search == "" or string.find(string.lower(message), search, 1, true) then
			table.insert(visibleLogs, { log = log, message = message })
		end
	end
	contentHeight = #visibleLogs * 18 + 23

	Immco.Scroller({
		id = "output-logs",
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
		ViewHeight = params.height,
		ContentHeight = contentHeight,
		ScrollSpeed = 50,
		ScrollLerpSpeed = 20,
		renderer = renderer,
		window = renderer.Window,
		theme = theme,
		RetainedStorage = storage,
		callback = function(scroll)
			local y = scroll.y + 23
			for _, entry in ipairs(visibleLogs) do
				local log = entry.log
				local timestamp = if log.timestamp
					then os.date("%H:%M:%S", log.timestamp)
					else string.format("%08.3f", log.time or 0)
				Immco.Text({
					x = scroll.x + 10,
					y = y,
					TextSize = 16,
					Font = Argon:CreateFont(theme.Font),
					text = timestamp,
					Color = theme.SecondaryTextColor,
					engine_window = renderer.Window,
					theme = theme,
				}, dt)
				Immco.Text({
					x = scroll.x + 90,
					y = y,
					TextSize = 16,
					Font = Argon:CreateFont(theme.Font),
					text = entry.message,
					Color = theme.TextColor,
					engine_window = renderer.Window,
					theme = theme,
				}, dt)
				y += 18
			end
		end,
	}, dt)
end

local function drawThreads(params, dt)
	local threadList = threads()
	local font = Argon:CreateFont(theme.Font)
	local mousePos = Argon:GetMousePosition()
	local mousePressed = Argon:IsMouseButtonPressed(1)
	local justPressed = mousePressed and not lastMousePressed
	lastMousePressed = mousePressed

	local innerX = params.x + 8
	local innerW = params.width - 16
	local col1w = math.max(100, innerW - 130)

	-- compute total scrollable height
	local totalH = THREAD_HEADER_H
	for _, entry in ipairs(threadList) do
		totalH += THREAD_ROW_H
		if expandedThread == entry.id then
			local traceLines = {}
			for line in string.gmatch(stackTrace(entry.thread), "[^\r\n]+") do
				table.insert(traceLines, line)
			end
			totalH += math.max(1, #traceLines) * THREAD_TRACE_H + 12
		end
	end
	if #threadList == 0 then
		totalH += THREAD_ROW_H
	end

	Immco.Scroller({
		id = "output-threads",
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
		ViewHeight = params.height,
		ContentHeight = totalH + 10,
		ScrollSpeed = 50,
		ScrollLerpSpeed = 20,
		renderer = renderer,
		window = renderer.Window,
		theme = theme,
		RetainedStorage = storage,
		callback = function(scroll)
			local y = scroll.y + 4
			local x = innerX

			-- ── header ──────────────────────────────────────────────────────────
			Immco.Rectangle({
				x = x,
				y = y,
				width = innerW,
				height = THREAD_HEADER_H,
				Color = theme.SecondaryColor,
				theme = theme,
				engine_window = renderer.Window,
			}, dt)
			Immco.Text({
				x = x + 28,
				y = y + 8,
				TextSize = 13,
				Font = font,
				text = "Kilang stack",
				Color = theme.SecondaryTextColor,
				engine_window = renderer.Window,
				theme = theme,
			}, dt)
			Immco.Text({
				x = x + 28 + col1w,
				y = y + 8,
				TextSize = 13,
				Font = font,
				text = "Status",
				Color = theme.SecondaryTextColor,
				engine_window = renderer.Window,
				theme = theme,
			}, dt)
			y += THREAD_HEADER_H

			-- ── empty state ──────────────────────────────────────────────────────
			if #threadList == 0 then
				Immco.Text({
					x = x + 28,
					y = y + 8,
					TextSize = 13,
					Font = font,
					text = "No Kilang threads are registered",
					Color = theme.SecondaryTextColor,
					engine_window = renderer.Window,
					theme = theme,
				}, dt)
				return
			end

			-- ── thread rows ──────────────────────────────────────────────────────
			for i, entry in ipairs(threadList) do
				if entry.status == "dead" then
					continue
				end
				local isExpanded = expandedThread == entry.id
				local rowY = y

				local isHovered = mousePos.X >= x
					and mousePos.X <= x + innerW
					and mousePos.Y >= rowY
					and mousePos.Y <= rowY + THREAD_ROW_H

				-- edge-triggered toggle on click
				if justPressed and isHovered then
					if isExpanded then
						expandedThread = nil
					else
						expandedThread = entry.id
					end
					isExpanded = not isExpanded
				end

				-- row background: hover > stripe > nothing
				local rowBg = isHovered and { R = 0.18, G = 0.18, B = 0.22, A = 1 }
					or (i % 2 == 0 and { R = 0.12, G = 0.12, B = 0.12, A = 1 } or nil)
				if rowBg then
					Immco.Rectangle({
						x = x,
						y = rowY,
						width = innerW,
						height = THREAD_ROW_H,
						Color = rowBg,
						theme = theme,
						engine_window = renderer.Window,
					}, dt)
				end

				-- expand arrow
				Immco.Text({
					x = x + 6,
					y = rowY + 8,
					TextSize = 11,
					Font = font,
					text = isExpanded and "▼" or "▶",
					Color = theme.SecondaryTextColor,
					engine_window = renderer.Window,
					theme = theme,
				}, dt)

				-- thread id
				Immco.Text({
					x = x + 24,
					y = rowY + 8,
					TextSize = 13,
					Font = font,
					text = entry.id,
					Color = theme.TextColor,
					engine_window = renderer.Window,
					theme = theme,
				}, dt)

				-- status with semantic color
				Immco.Text({
					x = x + 24 + col1w,
					y = rowY + 8,
					TextSize = 13,
					Font = font,
					text = entry.status,
					Color = STATUS_COLORS[entry.status] or STATUS_COLORS.unavailable,
					engine_window = renderer.Window,
					theme = theme,
				}, dt)

				y += THREAD_ROW_H

				-- ── inline stack trace ───────────────────────────────────────────
				if isExpanded then
					local traceLines = {}
					for line in string.gmatch(stackTrace(entry.thread), "[^\r\n]+") do
						table.insert(traceLines, line)
					end
					local traceH = math.max(1, #traceLines) * THREAD_TRACE_H + 12

					Immco.Rectangle({
						x = x,
						y = y,
						width = innerW,
						height = traceH,
						Color = { R = 0.07, G = 0.07, B = 0.09, A = 1 },
						theme = theme,
						engine_window = renderer.Window,
					}, dt)

					local ty = y + 6
					if #traceLines == 0 then
						Immco.Text({
							x = x + 34,
							y = ty,
							TextSize = 12,
							Font = font,
							text = "Stack trace unavailable",
							Color = theme.SecondaryTextColor,
							engine_window = renderer.Window,
							theme = theme,
						}, dt)
					else
						for _, line in ipairs(traceLines) do
							Immco.Text({
								x = x + 34,
								y = ty,
								TextSize = 12,
								Font = font,
								text = line,
								Color = theme.SecondaryTextColor,
								engine_window = renderer.Window,
								theme = theme,
							}, dt)
							ty += THREAD_TRACE_H
						end
					end

					y += traceH
				end
			end
		end,
	}, dt)
end

local function drawStackTraces(params, dt)
	local lines = {}
	for _, entry in ipairs(threads()) do
		table.insert(lines, entry.id .. " [" .. entry.status .. "]")
		for line in string.gmatch(stackTrace(entry.thread), "[^\r\n]+") do
			table.insert(lines, "    " .. line)
		end
		table.insert(lines, "")
	end
	if #lines == 0 then
		table.insert(lines, "No Kilang threads are registered.")
	end

	contentHeight = #lines * 18 + 20
	Immco.Scroller({
		id = "output-stack-traces",
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
		ViewHeight = params.height,
		ContentHeight = contentHeight,
		ScrollSpeed = 50,
		ScrollLerpSpeed = 20,
		renderer = renderer,
		window = renderer.Window,
		theme = theme,
		RetainedStorage = storage,
		callback = function(scroll)
			local y = scroll.y + 20
			for _, line in ipairs(lines) do
				Immco.Text({
					x = scroll.x + 10,
					y = y,
					TextSize = 14,
					Font = Argon:CreateFont(theme.Font),
					text = line,
					Color = theme.TextColor,
					engine_window = renderer.Window,
					theme = theme,
				}, dt)
				y += 18
			end
		end,
	}, dt)
end

local function drawProfiler(params, dt)
	local data = {}
	local perfStats = (renderer and renderer.PerfStats) or (ProfilerService and ProfilerService.PERF_STATS) or {}

	local keys = {}
	for k in pairs(perfStats) do
		table.insert(keys, k)
	end
	table.sort(keys)

	for _, key in ipairs(keys) do
		local val = perfStats[key]
		local valStr = ""
		local category = "General"

		if string.find(key, "_ms$") then
			category = "Timing"
			valStr = string.format("%.3f ms", tonumber(val) or 0)
		elseif key == "fps" then
			category = "FPS"
			valStr = string.format("%.1f", tonumber(val) or 0)
		else
			category = "Counter"
			valStr = tostring(val)
		end

		table.insert(data, { category = category, key = key, val = valStr })
	end

	local font = Argon:CreateFont(theme.Font)
	local innerX = params.x + 8
	local innerW = params.width - 16
	local col1w = 110
	local col3w = 140
	local col2w = math.max(100, innerW - col1w - col3w)

	local headerH = 28
	local rowH = 24
	local totalH = headerH + math.max(1, #data) * rowH

	Immco.Scroller({
		id = "output-profiler-scroller",
		x = params.x,
		y = params.y,
		width = params.width,
		height = params.height,
		ViewHeight = params.height,
		ContentHeight = totalH + 10,
		ScrollSpeed = 50,
		ScrollLerpSpeed = 20,
		renderer = renderer,
		window = renderer.Window,
		theme = theme,
		RetainedStorage = storage,
		callback = function(scroll)
			local y = scroll.y + 4
			local x = innerX

			-- Header
			Immco.Rectangle({
				x = x,
				y = y,
				width = innerW,
				height = headerH,
				Color = theme.SecondaryColor,
				theme = theme,
				engine_window = renderer.Window,
			}, dt)
			Immco.Text({
				x = x + 8,
				y = y + 6,
				TextSize = 13,
				Font = font,
				text = "Category",
				Color = theme.SecondaryTextColor,
				engine_window = renderer.Window,
				theme = theme,
			}, dt)
			Immco.Text({
				x = x + 8 + col1w,
				y = y + 6,
				TextSize = 13,
				Font = font,
				text = "Stat Name",
				Color = theme.SecondaryTextColor,
				engine_window = renderer.Window,
				theme = theme,
			}, dt)
			Immco.Text({
				x = x + 8 + col1w + col2w,
				y = y + 6,
				TextSize = 13,
				Font = font,
				text = "Value",
				Color = theme.SecondaryTextColor,
				engine_window = renderer.Window,
				theme = theme,
			}, dt)

			y += headerH

			if #data == 0 then
				Immco.Text({
					x = x + 8,
					y = y + 4,
					TextSize = 13,
					Font = font,
					text = "Waiting for perf stats...",
					Color = theme.SecondaryTextColor,
					engine_window = renderer.Window,
					theme = theme,
				}, dt)
				return
			end

			for i, entry in ipairs(data) do
				local rowBg = (i % 2 == 0) and { R = 0.12, G = 0.12, B = 0.12, A = 1 } or nil
				if rowBg then
					Immco.Rectangle({
						x = x,
						y = y,
						width = innerW,
						height = rowH,
						Color = rowBg,
						theme = theme,
						engine_window = renderer.Window,
					}, dt)
				end

				-- Category
				Immco.Text({
					x = x + 8,
					y = y + 4,
					TextSize = 12,
					Font = font,
					text = entry.category,
					Color = theme.SecondaryTextColor,
					engine_window = renderer.Window,
					theme = theme,
				}, dt)

				-- Stat Name
				Immco.Text({
					x = x + 8 + col1w,
					y = y + 4,
					TextSize = 12,
					Font = font,
					text = entry.key,
					Color = theme.TextColor,
					engine_window = renderer.Window,
					theme = theme,
				}, dt)

				-- Value
				Immco.Text({
					x = x + 8 + col1w + col2w,
					y = y + 4,
					TextSize = 12,
					Font = font,
					text = entry.val,
					Color = theme.AccentColor or theme.TextColor,
					engine_window = renderer.Window,
					theme = theme,
				}, dt)

				y += rowH
			end
		end,
	}, dt)
end

renderer.Pool.new("2d", function()
	local dt = renderer.RuntimeLibrary.dt
	local position = Output.AbsolutePosition
	local size = Output.AbsoluteSize
	Output.Size = theme.OutputCoordinates.Size
	Output.Position = theme.OutputCoordinates.Position
	if not position or not size then
		return
	end

	contentHeight = 0
	Immco.Widget({
		x = position.X,
		y = position.Y + 5,
		width = size.X,
		height = size.Y,
		title = "Output",
		tabs = tabs,
		renderer = renderer,

		activeTab = activeTab,
		OnTabChanged = function(index)
			activeTab = index
		end,
		theme = theme,
		engine_window = renderer.Window,
		callback = function(params)
			if activeTab == 1 then
				drawOutput(params, dt)
			elseif activeTab == 2 then
				drawThreads(params, dt)
			elseif activeTab == 3 then
				drawStackTraces(params, dt)
			else
				drawProfiler(params, dt)
			end
		end,
	}, dt)
end)
