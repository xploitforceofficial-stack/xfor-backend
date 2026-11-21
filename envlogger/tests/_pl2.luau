local luau = require("@lune/luau")
local src = 'return ({c=function(...) return {[1]={...},[2]=select("#",...)}; end}):g({"M"},"O")'
local probe = src
local ok = pcall(function() luau.load(probe) end)
print("plain compile:", ok)

local src2 = src .. ";"
local ok2 = pcall(function() luau.load(src2) end)
print("with semicolon:", ok2)
