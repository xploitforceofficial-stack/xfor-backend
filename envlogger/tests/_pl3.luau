local luau = require("@lune/luau")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec1.lua")
print("len", #src)
local ok = pcall(function() luau.load(src) end)
print("compile:", ok)

local pre = "local __FUHD_CHECK__ = __FUHD_CHECK__;"
local ok2 = pcall(function() luau.load(pre .. src) end)
print("compile+prelude:", ok2)
