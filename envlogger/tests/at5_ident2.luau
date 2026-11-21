local Sandbox = require("../src/core/sandbox")
local src = [[
local t = {}
print("tbl self|", tostring(t == t))
local n = 1
print("num|", tostring(n == 1))
local s = "a"
print("str|", tostring(s == "a"))
local p = Instance.new("Folder")
print("inst self|", tostring(p == p))
print("rawequal|", tostring(rawequal(p, p)))
print("~=|", tostring(p ~= p))
print("same via fn|", tostring((function(a) return a == p end)(p)))
local q = p
print("q==p|", tostring(q == p))
print("typeof q|", typeof(q))
print("rawget state|", tostring(rawget(q, "x")))
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 60 })
if not ok then print("sandbox error:", res) return end
print("ok:", res.ok, "err:", res.err)
for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
