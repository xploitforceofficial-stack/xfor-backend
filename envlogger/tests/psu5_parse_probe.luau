local fs = require("@lune/fs")

local source = fs.readFile("../Samples/PSU/v5/1.lua")

local ok = pcall(loadstring, source)
print("whole file loads:", ok)

local head = source:sub(1, 283)
print("prologue 0..283:", head:sub(1, 120) .. " ...")
