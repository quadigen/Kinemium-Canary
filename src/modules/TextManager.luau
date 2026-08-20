local typedefs = require("@Argon/typedefs")
local argon = require("@Argon")
local SDLK_BACKSPACE = 0x00000008
local SDLK_RETURN = 0x0000000D
local SDLK_ESCAPE = 0x0000001B

local TextInputManager = {}
TextInputManager._inputs = {} :: { [string]: any }
TextInputManager._focused = nil :: string?

function TextInputManager:Register(id: string, x: number, y: number, width: number, height: number)
	if not self._inputs[id] then
		self._inputs[id] = { text = "" }
	end
	local input = self._inputs[id]
	input.x, input.y, input.width, input.height = x, y, width, height
	return input
end

function TextInputManager:GetState(id: string)
	local input = self._inputs[id]
	if not input then
		return "", false
	end
	return input.text, self._focused == id
end

function TextInputManager:SetText(id: string, text: string)
	local input = self._inputs[id]
	if input then
		input.text = text
	end
end

function TextInputManager:HandleClicks(clicks, window)
	if not clicks or #clicks == 0 then
		return
	end

	for _, click in clicks do
		if not click.Down then
			continue
		end

		local hit = nil
		for id, input in self._inputs do
			if
				click.X >= input.x
				and click.X <= input.x + input.width
				and click.Y >= input.y
				and click.Y <= input.y + input.height
			then
				hit = id
				break
			end
		end

		if hit ~= self._focused then
			local wasFocused = self._focused ~= nil
			self._focused = hit

			if hit and not wasFocused then
				argon:StartTextInput(window)
			elseif not hit and wasFocused then
				argon:StopTextInput(window)
			end
		end
	end
end

function TextInputManager:HandleTextInput(textInputs)
	if not self._focused or not textInputs then
		return
	end
	local input = self._inputs[self._focused]
	if not input then
		return
	end
	for _, str in textInputs do
		input.text ..= str
	end
end

function TextInputManager:HandleKeyDown(keyDowns, onSubmit)
	if not self._focused or not keyDowns then
		return
	end
	local input = self._inputs[self._focused]
	if not input then
		return
	end

	for _, key in keyDowns do
		if key == SDLK_BACKSPACE then
			input.text = input.text:sub(1, -2)
		elseif key == SDLK_RETURN then
			if onSubmit then
				onSubmit(self._focused, input.text)
			end
		elseif key == SDLK_ESCAPE then
			self._focused = nil
		end
	end
end

function TextInputManager:Unfocus()
	self._focused = nil
end

return TextInputManager
