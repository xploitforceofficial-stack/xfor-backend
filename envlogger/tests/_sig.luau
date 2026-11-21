local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

for _, name in ipairs({"luraph-v14.6", "luraph-v14.7", "luraph-v14.8"}) do
  local src = fs.readFile("../Samples/Luraph/" .. name .. ".lua")

  print(name, "len", #src, "head", src:sub(1, 80):gsub("\n", " "))
end
