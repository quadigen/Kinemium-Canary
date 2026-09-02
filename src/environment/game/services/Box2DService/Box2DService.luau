local Instance = require("@Instance")
local Enum = require("@EnumMap")
local Vector2 = require("@Vector2")
local native = require("@kinebox2d")
local Service = Instance.new("Box2DService")
Service.ExplorerHidden = true
Service._Intents = Enum.PluginIntents.Physics

-- im sorry people for this horrible code

local worlds = {}
local null = zune.ffi.null
local createBody

local function destroyBody(world, object)
	local record = world.bodies[object]
	if not record then
		return
	end
	for _, connection in pairs(record.connections) do
		connection:Disconnect()
	end
	if record.handle and record.handle ~= null then
		native.Kine_Box2D_DestroyBody(record.handle)
	end
	world.bodies[object] = nil
	world.object.Bodies[object] = nil
	object.BodyID = nil
end

createBody = function(world, object)
	if not object or object.BaseClass ~= "Body2D" or object.Parent ~= world.object or world.bodies[object] then
		return false
	end
	local size = object.Size or Vector2.new(32, 32)
	local position = object.Position or Vector2.new(0, 0)
	local handle = native.Kine_Box2D_CreateBoxBody(
		world.handle,
		position.X,
		position.Y,
		size.X,
		size.Y,
		math.rad(object.Rotation or 0),
		object.Anchored == false and 1 or 0,
		object.Density or 1,
		object.Friction or 0.3,
		object.Restitution or 0,
		object.IsSensor and 1 or 0
	)
	if not handle or handle == null then
		return false
	end
	local velocity = object.LinearVelocity or Vector2.new(0, 0)
	native.Kine_Box2D_SetBodyVelocity(handle, velocity.X, velocity.Y, math.rad(object.AngularVelocity or 0))

	local record = { handle = handle, connections = {}, writing = false }
	world.bodies[object] = record
	world.object.Bodies[object] = true
	object.BodyID = handle

	record.connections.changed = object.Changed:Connect(function(property)
		if record.writing then
			return
		end
		if property == "Anchored" then
			native.Kine_Box2D_SetBodyType(handle, object.Anchored == false and 1 or 0)
		elseif property == "Position" or property == "Rotation" then
			native.Kine_Box2D_SetBodyTransform(
				handle,
				object.Position.X,
				object.Position.Y,
				math.rad(object.Rotation or 0)
			)
		elseif property == "LinearVelocity" or property == "AngularVelocity" then
			local v = object.LinearVelocity or Vector2.new(0, 0)
			native.Kine_Box2D_SetBodyVelocity(handle, v.X, v.Y, math.rad(object.AngularVelocity or 0))
		elseif
			property == "Size"
			or property == "Density"
			or property == "Friction"
			or property == "Restitution"
			or property == "IsSensor"
		then
			destroyBody(world, object)
			createBody(world, object)
		end
	end)
	record.connections.destroying = object.Destroying:Connect(function()
		destroyBody(world, object)
	end)
	return true
end

local function sync(world)
	for object, record in pairs(world.bodies) do
		if object.Parent ~= world.object then
			destroyBody(world, object)
		elseif object.Anchored == false then
			local x, y, a = zune.ffi.alloc(4), zune.ffi.alloc(4), zune.ffi.alloc(4)
			native.Kine_Box2D_GetBodyTransform(record.handle, x, y, a)
			record.writing = true
			world.bodyUpdate(object, Vector2.new(x:readf32(0), y:readf32(0)))
			object.Rotation = math.deg(a:readf32(0))
			record.writing = false
			zune.ffi.free(x)
			zune.ffi.free(y)
			zune.ffi.free(a)
		end
	end
end
local function destroyWorld(world)
	local list = {}
	for object in pairs(world.bodies) do
		table.insert(list, object)
	end
	for _, object in ipairs(list) do
		destroyBody(world, object)
	end
	for _, connection in pairs(world.connections) do
		connection:Disconnect()
	end
	if world.handle and world.handle ~= null then
		native.Kine_Box2D_DestroyWorld(world.handle)
	end
	worlds[world.object] = nil
end
Service.InitRenderer = function(renderer, signal, game)
	Service:SetProperties({
		init = function(object, bodyUpdate)
			if worlds[object] then
				destroyWorld(worlds[object])
			end
			local gravity = object.Gravity or Vector2.new(0, 981)
			local handle = native.Kine_Box2D_CreateWorld(gravity.X, gravity.Y)
			assert(handle and handle ~= null, "Failed to create Box2D world")
			local world = { object = object, handle = handle, bodyUpdate = bodyUpdate, bodies = {}, connections = {} }
			worlds[object] = world
			object._world = world
			for _, child in ipairs(object:GetChildren()) do
				createBody(world, child)
			end
			world.connections.added = object.ChildAdded:Connect(function(child)
				createBody(world, child)
			end)
			world.connections.removed = object.ChildRemoved:Connect(function(child)
				destroyBody(world, child)
			end)
			world.connections.changed = object.Changed:Connect(function(property)
				if property == "Gravity" then
					native.Kine_Box2D_SetGravity(handle, object.Gravity.X, object.Gravity.Y)
				end
			end)
			object.AddBody = function(_, body)
				body.Parent = object
				return createBody(world, body)
			end
			object.RemoveBody = function(_, body)
				destroyBody(world, body)
			end
			object.Clear = function()
				local bodies = {}
				for body in pairs(world.bodies) do
					table.insert(bodies, body)
				end
				for _, body in ipairs(bodies) do
					destroyBody(world, body)
				end
			end
			object.Step = function(_, dt)
				native.Kine_Box2D_StepWithGravity(
					handle,
					dt,
					object.VelocityIterations or 4,
					tonumber(object.Gravity.X),
					tonumber(object.Gravity.Y)
				)
				object.ElapsedTime += dt
				sync(world)
			end
			return handle
		end,
	})
	signal:Connect(function(route, dt)
		if route ~= "RenderStepped" then
			return
		end
		for _, world in pairs(worlds) do
			local object = world.object
			if not object.Paused then
				local step = (object.FixedDeltaTime or dt) * (object.TimeScale or 1)
				native.Kine_Box2D_StepWithGravity(
					world.handle,
					step,
					object.VelocityIterations or 4,
					tonumber(object.Gravity.X),
					tonumber(object.Gravity.Y)
				)
				object.ElapsedTime += step
				sync(world)
			end
		end
	end)
	table.insert(game.ShutdownCallbacks, function()
		local list = {}
		for _, world in pairs(worlds) do
			table.insert(list, world)
		end
		for _, world in ipairs(list) do
			destroyWorld(world)
		end
	end)
end
return Service
