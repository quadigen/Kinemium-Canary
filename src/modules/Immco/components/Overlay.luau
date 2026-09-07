local Overlay = {}

local OVERLAY_PRIORITY = 1_000_000

local queues = setmetatable({}, { __mode = "k" })
local renderIds = setmetatable({}, { __mode = "k" })

function Overlay.Push(renderer, callback)
	local queue = queues[renderer]

	if not queue then
		queue = {}
		queues[renderer] = queue
	end

	if not renderIds[renderer] then
		renderIds[renderer] = renderer.Pool.new("2d", function()
			local currentQueue = queues[renderer]

			if not currentQueue then
				return
			end

			for _, draw in ipairs(currentQueue) do
				draw()
			end

			table.clear(currentQueue)
		end, OVERLAY_PRIORITY)

		return
	end

	queue[#queue + 1] = callback
end

return Overlay
