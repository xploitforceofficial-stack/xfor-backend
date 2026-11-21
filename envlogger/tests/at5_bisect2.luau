local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run("print('hello')", { timeout = 15, maxExplored = 0 })
print("tiny ok:", r.ok, "err:", tostring(r.err):sub(1, 200))
for _, e in ipairs(r.outputs or {}) do print("out:", e.text) end

local fs = require("@lune/fs")
local source = fs.readFile("tests/at5_fixture.lua")
local result = Sandbox.run(source, { timeout = 120, maxExplored = 0 })
print("fixture ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
