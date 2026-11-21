local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")
local src = fs.readFile("../Samples/Luraph/luraph-v14.6.lua")
local t0 = os.clock()
local last = t0
local r = Sandbox.run(src, {
  timeout = 60,
  maxNest = 4,
  traceLimit = 50000,
  onProgress = function(info)
    local now = os.clock()
    if now - last > 5 then
      print(string.format("t=%.1f ops=%s bytes=%s", now - t0, tostring(info and info.ops), tostring(info and info.outputBytes)))
      last = now
    end
  end,
  allowHttp = false,
  maxExplored = 0,
  softInstanceCall = true,
})
print("done t=", os.clock()-t0, "err=", tostring(r.err), "exhausted=", tostring(r.exhausted), tostring(r.exhaustedReason))
print("stages=", #(r.stages or {}))
