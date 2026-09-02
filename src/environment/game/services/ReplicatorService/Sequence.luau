local Sequence = {}
Sequence.Modulus = 2 ^ 32
Sequence.HalfRange = 2 ^ 31

function Sequence.Normalize(value)
	return math.floor(tonumber(value) or 0) % Sequence.Modulus
end

function Sequence.Next(value)
	return (Sequence.Normalize(value) + 1) % Sequence.Modulus
end

function Sequence.IsNewer(a, b)
	a, b = Sequence.Normalize(a), Sequence.Normalize(b)
	local difference = (a - b) % Sequence.Modulus
	return difference ~= 0 and difference < Sequence.HalfRange
end

function Sequence.IsNewerOrEqual(a, b)
	return Sequence.Normalize(a) == Sequence.Normalize(b) or Sequence.IsNewer(a, b)
end

return Sequence
