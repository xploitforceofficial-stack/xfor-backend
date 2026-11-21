local Sandbox = require("../src/core/sandbox")

local cases = {
	[[
local r = Random.new(1)
print("v", r:NextNumber())
]],
	[[
local r = Random.new(1)
print("i", r:NextInteger(1, 10))
]],
	[[
print("unseeded", Random.new():NextNumber())
]],
	[[
local r = Random.new(1)
local c = r:Clone()
print("clone", c:NextNumber() == r:NextNumber())
]],
	[[
local r = Random.new(1)
print("uv", r:NextUnitVector().Magnitude)
]],
}

for i, src in ipairs(cases) do
	local result = Sandbox.run(src, { timeout = 30, maxExplored = 0 })
	local out = {}
	for _, entry in ipairs(result.outputs or {}) do
		out[#out + 1] = tostring(entry.text)
	end
	print(string.format("case %d ok=%s err=%s out=%s", i, tostring(result.ok),
		tostring(result.err):sub(1, 80), table.concat(out, " | ")))
end
