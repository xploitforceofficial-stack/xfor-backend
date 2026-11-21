local PrngTrace = {}

local RING_CAP = 64
local ring: { number } = {}
local member: { [number]: boolean } = {}

function PrngTrace.reset()
	ring = {}
	member = {}
end

function PrngTrace.mark(value: number)
	if member[value] then
		return
	end
	ring[#ring + 1] = value
	member[value] = true
	if #ring > RING_CAP then
		local evicted = table.remove(ring, 1)
		if evicted ~= nil then
			member[evicted] = nil
		end
	end
end

function PrngTrace.contains(value: any): boolean
	return type(value) == "number" and member[value] == true
end

function PrngTrace.containsAny(...): boolean
	for i = 1, select("#", ...) do
		if PrngTrace.contains((select(i, ...))) then
			return true
		end
	end
	return false
end

return PrngTrace
