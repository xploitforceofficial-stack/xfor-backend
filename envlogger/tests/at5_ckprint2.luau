local fs = require("@lune/fs")
local luau = require("@lune/luau")

local source = fs.readFile("tests/at5_fixture.lua")
source = string.gsub(source, "\r\n", "\n")

local patched, n = string.gsub(
	source,
	"if checksum%(guardedSource%) ~= %d+ then",
	"print(\"CK_VALUE\", checksum(guardedSource), #guardedSource) if false then"
)
if n ~= 1 then
	print("could not patch checksum site (n=" .. n .. ")")
	return
end

local captured: { string } = {}
local function recPrint(...: any)
	local parts: { string } = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	captured[#captured + 1] = table.concat(parts, "\t")
end

local env: any = {
	print = recPrint,
	string = string,
	type = type,
	tostring = tostring,
	select = select,
	error = error,
	pcall = pcall,
	loadstring = loadstring,
	setmetatable = setmetatable,
	getmetatable = getmetatable,
	next = next,
}

local fn = luau.load(patched, {
	environment = env,
	injectGlobals = false,
	debugName = "",
	codegenEnabled = true,
})

local ok, err = pcall(fn)
print("ok:", ok, "err:", tostring(err):sub(1, 60))
for _, line in ipairs(captured) do
	if string.find(line, "CK_VALUE", 1, true) then
		print("RUNTIME|" .. line)
	end
end
