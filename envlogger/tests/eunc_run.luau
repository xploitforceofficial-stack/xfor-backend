local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("Samples/eunc.lua")

local ok, res = pcall(Sandbox.run, source, {
	timeout = 90,
	maxNest = 1,
	name = "eunc.lua",
})

if not ok then
	print("SANDBOX CRASH:", res)
	return
end

print("ok:", res.ok, "err:", tostring(res.err):sub(1, 200))

local out
if type(res.outputs) == "table" then
	local parts = {}
	for _, item in res.outputs do
		parts[#parts + 1] = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
	end
	out = table.concat(parts, "\n")
elseif type(res.prints) == "table" then
	out = table.concat(res.prints, "\n")
elseif type(res.output) == "table" then
	out = table.concat(res.output, "\n")
elseif type(res.stdout) == "string" then
	out = res.stdout
end

if not out or #out == 0 then

	local keys = {}
	for k in pairs(res) do
		keys[#keys + 1] = tostring(k)
	end
	table.sort(keys)
	print("result keys:", table.concat(keys, ", "))
	local rt = type(res)
	print("result type:", rt)
	if rt == "table" then
		for k, v in pairs(res) do
			local tv = type(v)
			if tv == "table" then
				local n = 0
				for _ in pairs(v) do
					n += 1
				end
				print(string.format("  %s: table(%d)", tostring(k), n))
			else
				print(string.format("  %s: %s = %s", tostring(k), tv, tostring(v):sub(1, 100)))
			end
		end
	end
	return
end

for line in out:gmatch("[^\n]+") do
	if line:find("SCORE") or line:find("score") or line:find("UNC") or line:find("passed") or line:find("failed") then
		print(line)
	end
end

fs.writeFile("./eunc_out.txt", out)
print("full output -> tests/eunc_out.txt (" .. #out .. " bytes)")
