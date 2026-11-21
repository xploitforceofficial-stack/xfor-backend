local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")

local src = "local s = { x = workspace }\nlocal k2, v2 = next(s, nil)\nprint(\"spyval:\", k2, v2, type(v2))\n"

local t1 = Instrument.apply(src, { operators = true })
print("apply(ops=true):", t1)
local t2 = Instrument.apply(src, { operators = false })
print("apply(ops=false):", t2)
