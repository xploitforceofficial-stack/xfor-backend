local luau = require("@lune/luau")

local chunk = "return string.byte(\"A\")"

local function try(name: string, opts: any)
	local fn = luau.load(chunk, opts)
	local ok, res = pcall(fn)
	print(name, "ok:", ok, "res:", tostring(res))
end

try("empty-noinject", {
	environment = {},
	injectGlobals = false,
	debugName = "",
	codegenEnabled = true,
})

try("meta-noinject", {
	environment = setmetatable({}, { __index = _G }),
	injectGlobals = false,
	debugName = "",
	codegenEnabled = true,
})
