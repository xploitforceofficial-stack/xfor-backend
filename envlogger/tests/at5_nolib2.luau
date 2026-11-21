local luau = require("@lune/luau")

local chunk = "return string.byte(\"A\")"

local function try(name: string, opts: any)
	local fn = luau.load(chunk, opts)
	local ok, res = pcall(fn)
	print(name, "ok:", ok, "res:", tostring(res))
end

try("nil-env", {
	environment = nil,
	injectGlobals = true,
	debugName = "",
	codegenEnabled = true,
})

try("empty-inject", {
	environment = {},
	injectGlobals = true,
	debugName = "",
	codegenEnabled = true,
})

try("only-string", {
	environment = { string = string },
	injectGlobals = false,
	debugName = "",
	codegenEnabled = true,
})
