-- description: "Creates a shader-based frame for custom rendering."
local GuiObject = require("@GuiObject")
local argon = require("@Argon")

local propTable = {
	Name = "ShaderFrame",
	AbsoluteSize = nil,
	AbsolutePosition = nil,
	Shader = nil,
}

GuiObject.inherit(propTable)

local function clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

propTable.render = function(window, object, dt, renderer)
	if not object.Visible then
		return
	end

	local pos, size = GuiObject.render(window, object, dt, renderer)
	object.AbsolutePosition = pos
	object.AbsoluteSize = size

	local shader = object.Shader
	if shader and shader._type == "2d" then
		object._frameCount = (object._frameCount or 0) + 1
		local time = os.clock()
		local safeW = math.max(size.X, 1)
		local safeH = math.max(size.Y, 1)
		local mouse = argon:GetMousePosition()
		local localX = clamp((mouse and mouse.X or 0) - pos.X, 0, safeW)
		local localY = clamp((mouse and mouse.Y or 0) - pos.Y, 0, safeH)
		local mouseUVX = localX / safeW
		local mouseUVY = localY / safeH

		shader:SetUniform("u_time", time)
		shader:SetUniform("u_deltaTime", dt)
		shader:SetUniform("u_frame", object._frameCount)
		shader:SetUniform("u_resolution", { safeW, safeH })
		shader:SetUniform("u_mouse", { localX, localY })
		shader:SetUniform("u_mouseUV", { mouseUVX, mouseUVY })
		shader:SetUniform("u_framePos", { pos.X, pos.Y })
		shader:SetUniform("iTime", time)
		shader:SetUniform("iTimeDelta", dt)
		shader:SetUniform("iFrame", object._frameCount)
		shader:SetUniform("iResolution", { safeW, safeH, 1 })
		shader:SetUniform("iMouse", { localX, localY, localX, localY })

		local compiled, compileError = shader:Compile(window)
		if compiled then
			argon:DrawRuntimeShaderRectangle(window, shader._shader, {
				x = pos.X,
				y = pos.Y,
				width = size.X,
				height = size.Y,
			})
		elseif object._shaderCompileError ~= compileError then
			object._shaderCompileError = compileError
			warn(`ShaderFrame failed to compile SkSL: {compileError}`)
		end
	end

	GuiObject.renderChildren(window, object, dt, renderer)

	return pos, size
end

return {
	class = "ShaderFrame",
	render = propTable.render,
	callback = function(instance, renderer)
		instance:SetProperties(propTable)
		return instance
	end,
	inherit = function(tble)
		GuiObject.inherit(tble)
	end,
}
