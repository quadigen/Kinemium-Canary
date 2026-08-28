-- description: "Emits particles in 3D space with a custom image template, and with configurable properties such as Color, Transparency, etc"
local Vector2 = require("@Vector2")
local Vector3 = require("@Vector3")
local Color3 = require("@Color3")
local CFrame = require("@CFrame")
local argon = require("@Argon")
local Enum = require("@EnumMap")
local NumberSequence = require("@NumberSequence")
local NumberSequenceKeypoint = require("@NumberSequenceKeypoint")
local ColorSequence = require("@ColorSequence")
local NumberRange = require("@NumberRange")
local ColorSequenceKeypoint = require("@ColorSequenceKeypoint")

local PARTICLE_ITEM_SIZE = 68

local function getRange(value, defaultMin, defaultMax)
	if type(value) == "number" then
		return value, value
	end
	if type(value) == "table" then
		if value.Min ~= nil and value.Max ~= nil then
			return value.Min, value.Max
		end
	end
	return defaultMin, defaultMax
end

local function randomRange(value, defaultMin, defaultMax)
	local minVal, maxVal = getRange(value, defaultMin, defaultMax)
	if minVal == nil or maxVal == nil then
		return 0
	end
	if minVal == maxVal then
		return minVal
	end
	return minVal + math.random() * (maxVal - minVal)
end

local function clamp01(v)
	if v < 0 then
		return 0
	end
	if v > 1 then
		return 1
	end
	return v
end

local function resolveCullMode(value)
	if type(value) == "number" then
		return value
	end
	if type(value) == "table" and value.Value ~= nil then
		return value.Value
	end
	return 1
end

local function getVector2(value, fallback)
	if type(value) == "table" and value.__type == "Vector2" then
		return value
	end
	return fallback
end

local function evalNumberSequence(seq, t, fallback)
	if type(seq) == "number" then
		return seq
	end
	if type(seq) == "table" and seq.Evaluate then
		return seq:Evaluate(t)
	end
	return fallback
end

local function evalColorSequence(seq, t, fallback)
	if type(seq) == "table" and seq.Evaluate then
		return seq:Evaluate(t)
	end
	if type(seq) == "table" and seq.__type == "Color3" then
		return seq
	end
	return fallback
end

local function getFlipbookMode(value)
	if type(value) == "number" then
		return value
	end
	if type(value) == "table" and value.Value ~= nil then
		return value.Value
	end
	return 0
end

local function getEmitterCFrame(instance)
	local parent = instance.Parent
	if parent then
		if parent.WorldCFrame then
			return parent.WorldCFrame
		end
		if parent.CFrame then
			return parent.CFrame
		end
	end
	return CFrame.new(0, 0, 0)
end

local function getEmissionDirection(cf, normalId)
	if normalId == Enum.NormalId.Bottom then
		return -cf:GetUpVector()
	elseif normalId == Enum.NormalId.Top then
		return cf:GetUpVector()
	elseif normalId == Enum.NormalId.Left then
		return -cf:GetRightVector()
	elseif normalId == Enum.NormalId.Right then
		return cf:GetRightVector()
	elseif normalId == Enum.NormalId.Back then
		return -cf:GetLookVector()
	end
	return cf:GetLookVector()
end

local function getEmitterVelocity(instance)
	local parent = instance.Parent
	if parent then
		if type(parent.AssemblyLinearVelocity) == "table" and parent.AssemblyLinearVelocity.__type == "Vector3" then
			return parent.AssemblyLinearVelocity
		end
		if
			parent.Parent
			and type(parent.Parent.AssemblyLinearVelocity) == "table"
			and parent.Parent.AssemblyLinearVelocity.__type == "Vector3"
		then
			return parent.Parent.AssemblyLinearVelocity
		end
	end
	return Vector3.new(0, 0, 0)
end

local function applySpread(baseDir, basisRight, basisUp, spread)
	if not spread or type(spread) ~= "table" then
		return baseDir
	end

	local spreadX = math.tan(math.rad(spread.X or 0) * 0.5)
	local spreadY = math.tan(math.rad(spread.Y or 0) * 0.5)
	if spreadX == 0 and spreadY == 0 then
		return baseDir
	end

	local rx = (math.random() * 2 - 1) * spreadX
	local ry = (math.random() * 2 - 1) * spreadY
	local dir = baseDir + (basisRight * rx) + (basisUp * ry)
	return dir:Unit()
end

local function buildDefaultColor()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
end

local function buildDefaultTransparency()
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
end

local function buildDefaultSize()
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local propTable = {
	Enabled = true,
	Rate = 20,
	Lifetime = NumberRange.new(1, 2),
	Speed = NumberRange.new(4, 7),
	Rotation = NumberRange.new(0, 0),
	RotSpeed = NumberRange.new(0, 0),
	Size = buildDefaultSize(),
	Color = buildDefaultColor(),
	Transparency = buildDefaultTransparency(),
	Acceleration = Vector3.new(0, 0, 0),
	Drag = 0,
	Restitution = 0.5,
	CollisionGroup = "Particles",
	Friction = 0.3,
	VelocityInheritance = 0,
	TimeScale = 1,
	WindAffectsDrag = false,
	CollideParticles = false,
	CollisionRadius = 0.5,
	EmissionDirection = Enum.NormalId.Top,
	SpreadAngle = Vector2.new(0, 0),
	Texture = "./src/assets/images/placeholder.png",
	EmissionTexture = nil,
	EmissionColor = Color3.new(1, 1, 1),
	EmissionEnergy = 0,
	TransparencyMode = Enum.ParticleTransparencyMode.Alpha,
	BlendMode = Enum.ParticleBlendMode.Mix,
	CullMode = Enum.ParticleCullMode.None,
	BillboardMode = Enum.ParticleBillboardMode.Front,
	UVScale = Vector2.new(1, 1),
	UVOffset = Vector2.new(0, 0),
	FlipbookColumns = 1,
	FlipbookRows = 1,
	FlipbookFramerate = 0,
	FlipbookMode = Enum.ParticleFlipbookMode.Loop,
	FlipbookStartRandom = false,
	MaxParticles = 256,
	LockedToPart = false,
	CastShadow = true,
}

return {
	class = "ParticleEmitter",

	callback = function(instance, renderer, game)
		instance:SetProperties(propTable)

		if _G.IsHeadless or not renderer then
			return instance
		end

		local flipbookTime = 0
		local flipbookFrame = 0
		local flipbookDir = 1
		local particles = {}
		local activeCount = 0
		local emitAccumulator = 0
		local updateFlipbook
		local itemBuffer = buffer.create(math.max(1, instance.MaxParticles) * PARTICLE_ITEM_SIZE)
		local particleTexture = nil

		local function loadTexture()
			if particleTexture then
				argon:Destroy3DTexture(renderer.Window, particleTexture)
				particleTexture = nil
			end
			if type(instance.Texture) == "string" and instance.Texture ~= "" then
				particleTexture = argon:CreateParticleTexture(renderer.Window, instance.Texture)
			end
		end

		local function resizeItemBuffer()
			itemBuffer = buffer.create(math.max(1, instance.MaxParticles) * PARTICLE_ITEM_SIZE)
		end

		local function getCameraCFrame()
			local workspace = game and game:GetService("Workspace")
			local camera = workspace and (workspace.Camera or workspace.CurrentCamera)
			return camera and camera.CFrame
		end

		loadTexture()

		local function emitParticle()
			if activeCount >= instance.MaxParticles then
				return
			end

			local emitterCF = getEmitterCFrame(instance)
			local baseDir = getEmissionDirection(emitterCF, instance.EmissionDirection)
			local dir = applySpread(baseDir, emitterCF:GetRightVector(), emitterCF:GetUpVector(), instance.SpreadAngle)

			local spread = instance.SpreadAngle
			local isFullSphere = spread and spread.X >= 180 and spread.Y >= 180
			if isFullSphere then
				-- true uniform sphere sampling
				local u = math.random() * 2 - 1
				local theta = math.random() * math.pi * 2
				local r = math.sqrt(1 - u * u)
				dir = Vector3.new(r * math.cos(theta), u, r * math.sin(theta))
			else
				dir = applySpread(baseDir, emitterCF:GetRightVector(), emitterCF:GetUpVector(), spread)
			end

			local lifetime = randomRange(instance.Lifetime, 1, 1)
			if lifetime <= 0 then
				return
			end

			local baseVel = dir * randomRange(instance.Speed, 0, 0)
			local inheritance = instance.VelocityInheritance or 0
			if inheritance ~= 0 then
				baseVel = baseVel + getEmitterVelocity(instance) * inheritance
			end

			local rawBodyID = nil
			if game and not instance.LockedToPart and instance.CollideParticles then
				local ups = game:GetService("UnifiedPhysicsService")
				if ups and ups.CreateRawBody then
					rawBodyID = ups.CreateRawBody({
						Position = emitterCF.Position,
						Size = Vector3.new(1, 1, 1) * (instance.CollisionRadius or 0.5) * 2,
						Shape = Enum.PartType.Ball,
						CanCollide = instance.CollideParticles,
						Anchored = false,
						Mass = 1,
						AssemblyLinearVelocity = baseVel,
						Friction = instance.Friction,
						Restitution = instance.Restitution,
						CollisionGroup = instance.CollisionGroup or "Particles",
					})
				end
			end

			activeCount += 1
			particles[activeCount] = {
				bodyID = rawBodyID,
				life = lifetime,
				lifetime = lifetime,
				rotation = math.rad(randomRange(instance.Rotation, 0, 0)),
				rotSpeed = math.rad(randomRange(instance.RotSpeed, 0, 0)),
				axis = dir,
				localOffset = instance.LockedToPart and emitterCF:Inverse() * emitterCF.Position or nil,
				localVelocity = instance.LockedToPart and emitterCF:VectorToObjectSpace(baseVel) or nil,
				-- Fallback physics if UPS is unavailable
				position = not rawBodyID and emitterCF.Position or nil,
				velocity = not rawBodyID and baseVel or nil,
			}
		end

		local function emit(count)
			for _ = 1, count do
				emitParticle()
			end
		end

		-- description: "Emits a specified amount of particles."
		-- args: "self: table, count: number"
		instance.Emit = function(_, count)
			emit(math.max(0, count or 1))
		end

		local function updateParticles(dt)
			local timeScale = instance.TimeScale or 1
			local scaledDt = dt * timeScale

			if instance.Enabled then
				emitAccumulator += (instance.Rate or 0) * dt -- Rate is typically real-time
				local emitCount = math.floor(emitAccumulator)
				if emitCount > 0 then
					emitAccumulator -= emitCount
					emit(emitCount)
				end
			end

			local accel = instance.Acceleration or Vector3.new(0, 0, 0)
			local drag = instance.Drag or 0
			local windAffectsDrag = instance.WindAffectsDrag or false

			local globalWind = Vector3.new(0, 0, 0)
			if windAffectsDrag and game then
				local workspace = game:GetService("Workspace")
				if workspace and type(workspace.GlobalWind) == "table" and workspace.GlobalWind.__type == "Vector3" then
					globalWind = workspace.GlobalWind
				end
			end

			local ups = game and game:GetService("UnifiedPhysicsService")
			local emitterCF = instance.LockedToPart and getEmitterCFrame(instance) or nil

			local i = 1
			while i <= activeCount do
				local p = particles[i]
				p.life -= scaledDt
				if p.life <= 0 then
					if p.bodyID and ups and ups.DeleteRawBody then
						ups.DeleteRawBody(p.bodyID)
					end
					particles[i] = particles[activeCount]
					particles[activeCount] = nil
					activeCount -= 1
				else
					if p.bodyID then
						if ups and ups.ApplyForceToRawBody then
							if accel.X ~= 0 or accel.Y ~= 0 or accel.Z ~= 0 then
								ups.ApplyForceToRawBody(p.bodyID, accel) -- mass is 1
							end

							if drag > 0 then
								local vel = ups.GetRawBodyVelocity(p.bodyID)
								if
									windAffectsDrag and (globalWind.X ~= 0 or globalWind.Y ~= 0 or globalWind.Z ~= 0)
								then
									local force = (globalWind - vel) * (drag * 60)
									ups.ApplyForceToRawBody(p.bodyID, force)
								else
									local force = -vel * (drag * 60)
									ups.ApplyForceToRawBody(p.bodyID, force)
								end
							end
						end
					else
						-- Optional manual physics fallback
						local velocity = p.velocity
						local position = p.position

						-- Apply acceleration
						velocity = velocity + accel * scaledDt

						-- Apply drag
						if drag > 0 then
							if windAffectsDrag then
								velocity = velocity + (globalWind - velocity) * (drag * scaledDt)
							else
								velocity = velocity * (1 - drag * scaledDt)
							end
						end

						p.velocity = velocity
						if instance.LockedToPart and p.localOffset then
							p.localVelocity = (p.localVelocity or Vector3.zero)
								+ emitterCF:VectorToObjectSpace(accel) * scaledDt
							if drag > 0 then
								p.localVelocity = p.localVelocity * (1 - drag * scaledDt)
							end
							p.localOffset = p.localOffset + p.localVelocity * scaledDt
						else
							p.position = position + velocity * scaledDt
						end
					end

					p.rotation += p.rotSpeed * scaledDt
					i += 1
				end
			end
		end

		local function writeMatrix(base, pos, right, up, look, size)
			buffer.writef32(itemBuffer, base, right.X * size)
			buffer.writef32(itemBuffer, base + 4, up.X * size)
			buffer.writef32(itemBuffer, base + 8, look.X * size)
			buffer.writef32(itemBuffer, base + 12, pos.X)
			buffer.writef32(itemBuffer, base + 16, right.Y * size)
			buffer.writef32(itemBuffer, base + 20, up.Y * size)
			buffer.writef32(itemBuffer, base + 24, look.Y * size)
			buffer.writef32(itemBuffer, base + 28, pos.Y)
			buffer.writef32(itemBuffer, base + 32, right.Z * size)
			buffer.writef32(itemBuffer, base + 36, up.Z * size)
			buffer.writef32(itemBuffer, base + 40, look.Z * size)
			buffer.writef32(itemBuffer, base + 44, pos.Z)
			buffer.writef32(itemBuffer, base + 48, 0)
			buffer.writef32(itemBuffer, base + 52, 0)
			buffer.writef32(itemBuffer, base + 56, 0)
			buffer.writef32(itemBuffer, base + 60, 1)
		end

		local function buildParticleItems()
			if activeCount <= 0 then
				return 0
			end

			local ups = game and game:GetService("UnifiedPhysicsService")
			local cameraCF = getCameraCFrame()
			local right = cameraCF and cameraCF:GetRightVector() or Vector3.new(1, 0, 0)
			local up = cameraCF and cameraCF:GetUpVector() or Vector3.new(0, 1, 0)
			local look = cameraCF and -cameraCF:GetLookVector() or Vector3.new(0, 0, 1)
			local emitterCF = instance.LockedToPart and getEmitterCFrame(instance) or nil

			for idx = 1, activeCount do
				local p = particles[idx]
				local age = 1 - (p.life / p.lifetime)
				local t = clamp01(age)
				local size = evalNumberSequence(instance.Size, t, 1)
				local color = evalColorSequence(instance.Color, t, Color3.new(1, 1, 1))
				local transparency = evalNumberSequence(instance.Transparency, t, 0)
				local cr, cg, cb = color:ToRGB()
				local alpha = math.floor(255 * (1 - clamp01(transparency)) + 0.5)

				local pos = Vector3.zero
				if p.bodyID and ups and ups.GetRawBodyPosition then
					pos = ups.GetRawBodyPosition(p.bodyID)
				elseif emitterCF and p.localOffset then
					pos = emitterCF * p.localOffset
				else
					pos = p.position or Vector3.zero
				end

				local rotSin = math.sin(p.rotation)
				local rotCos = math.cos(p.rotation)
				local drawRight = right * rotCos + up * rotSin
				local drawUp = up * rotCos - right * rotSin
				local base = (idx - 1) * PARTICLE_ITEM_SIZE
				writeMatrix(base, pos, drawRight, drawUp, look, size)
				buffer.writeu8(itemBuffer, base + 64, cr)
				buffer.writeu8(itemBuffer, base + 65, cg)
				buffer.writeu8(itemBuffer, base + 66, cb)
				buffer.writeu8(itemBuffer, base + 67, alpha)
			end

			return activeCount
		end

		-- description: "Updates flipbook."
		-- args: "dt: number"
		updateFlipbook = function(dt)
			local cols = math.max(1, tonumber(instance.FlipbookColumns) or 1)
			local rows = math.max(1, tonumber(instance.FlipbookRows) or 1)
			local frames = cols * rows
			local framerate = tonumber(instance.FlipbookFramerate) or 0

			if frames <= 1 then
				return
			end

			if framerate > 0 then
				flipbookTime += dt * framerate
				while flipbookTime >= 1 do
					flipbookTime -= 1
					local mode = getFlipbookMode(instance.FlipbookMode)
					if mode == 1 then
						flipbookFrame = math.min(frames - 1, flipbookFrame + 1)
					elseif mode == 2 then
						if flipbookFrame + flipbookDir >= frames or flipbookFrame + flipbookDir < 0 then
							flipbookDir = -flipbookDir
						end
						flipbookFrame = flipbookFrame + flipbookDir
					elseif mode == 3 then
						flipbookFrame = math.random(0, frames - 1)
					else
						flipbookFrame = (flipbookFrame + 1) % frames
					end
				end
			end

			local baseScale = getVector2(instance.UVScale, Vector2.new(1, 1))
			local baseOffset = getVector2(instance.UVOffset, Vector2.new(0, 0))
			local frameScaleX = 1 / cols
			local frameScaleY = 1 / rows
			local col = flipbookFrame % cols
			local row = math.floor(flipbookFrame / cols)

			local finalScaleX = baseScale.X * frameScaleX
			local finalScaleY = baseScale.Y * frameScaleY
			local finalOffsetX = baseOffset.X + (col * frameScaleX * baseScale.X)
			local finalOffsetY = baseOffset.Y + (row * frameScaleY * baseScale.Y)

			instance._particleUVScale = Vector2.new(finalScaleX, finalScaleY)
			instance._particleUVOffset = Vector2.new(finalOffsetX, finalOffsetY)
		end

		local renderId = renderer.Pool.new("3d", function()
			if activeCount <= 0 then
				return
			end
			local count = buildParticleItems()
			if count > 0 then
				argon:DrawParticles(
					renderer.Window,
					particleTexture,
					itemBuffer,
					count,
					instance._particleUVScale or getVector2(instance.UVScale, Vector2.new(1, 1)),
					instance._particleUVOffset or getVector2(instance.UVOffset, Vector2.new(0, 0)),
					instance.CastShadow ~= false,
					resolveCullMode(instance.CullMode) ~= 0
				)
			end
		end)

		if instance.FlipbookStartRandom then
			local cols = math.max(1, tonumber(instance.FlipbookColumns) or 1)
			local rows = math.max(1, tonumber(instance.FlipbookRows) or 1)
			local frames = cols * rows
			if frames > 1 then
				flipbookFrame = math.random(0, frames - 1)
			end
		end

		renderer.Hook.new("Renderstep", function(dt)
			updateParticles(dt)
			updateFlipbook(dt)
		end)

		instance.Changed:Connect(function(property)
			if property == "Texture" then
				loadTexture()
			elseif property == "UVScale" or property == "UVOffset" then
				updateFlipbook(0)
			elseif
				property == "FlipbookColumns"
				or property == "FlipbookRows"
				or property == "FlipbookFramerate"
				or property == "FlipbookMode"
			then
				updateFlipbook(0)
			elseif property == "MaxParticles" then
				resizeItemBuffer()
			end
		end)

		instance.Destroying:Connect(function()
			if renderId then
				renderer.Pool.Destroy(renderId)
			end
			if particleTexture then
				argon:Destroy3DTexture(renderer.Window, particleTexture)
				particleTexture = nil
			end
			local ups = game and game:GetService("UnifiedPhysicsService")
			for i = 1, activeCount do
				if particles[i] and particles[i].bodyID and ups and ups.DeleteRawBody then
					pcall(ups.DeleteRawBody, particles[i].bodyID)
				end
			end
		end)

		return instance
	end,

	inherit = function(tble)
		for prop, val in pairs(propTable) do
			tble[prop] = val
		end
	end,
}
