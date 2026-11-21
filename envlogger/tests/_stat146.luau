local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")
local src = fs.readFile("../Samples/Luraph/luraph-v14.6.lua")
local r = Sandbox.run(src, {
  timeout = 40,
  maxNest = 4,
  traceLimit = 5000,
  onProgress = function() end,
  allowHttp = false,
  maxExplored = 0,
  softInstanceCall = true,
})
print("DONE err=", tostring(r.err), "exhausted=", tostring(r.exhausted))
