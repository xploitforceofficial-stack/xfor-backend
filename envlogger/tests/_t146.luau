local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")
local src = fs.readFile("../Samples/Luraph/luraph-v14.6.lua")
print("start", os.clock())
local r = Sandbox.run(src, {
  timeout = 120, allowHttp = false, maxExplored = 0, softInstanceCall = true,
  noInstrument = true,
})
print("done", os.clock(), "err", tostring(r.err), "exhausted", tostring(r.exhausted), r.exhaustedReason)
print("stages", #(r.stages or {}), "vm", #(r.vmTrace or {}))
