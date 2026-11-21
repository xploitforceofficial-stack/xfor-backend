local fs = require("@lune/fs")
local luau = require("@lune/luau")

local function tryCompile(name: string, text: string)
	local ok, err = pcall(function()
		luau.load(text, { debugName = name, codegenEnabled = true })
	end)
	print(name, ok and "COMPILES" or ("FAIL: " .. tostring(err):sub(1, 120)))
end

tryCompile("stdlib", fs.readFile("src/env/stdlib.luau"))
tryCompile("sandbox", fs.readFile("src/core/sandbox.luau"))
tryCompile("roblox", fs.readFile("src/env/roblox.luau"))
tryCompile("fidelity", fs.readFile("src/env/fidelity.luau"))
