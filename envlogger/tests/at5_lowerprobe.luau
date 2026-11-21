local Instrument = require("../src/core/instrument")

local src = "local s = { x = workspace }\nlocal k2, v2 = next(s, nil)\nprint(\"spyval:\", k2, v2, type(v2))\n"

local lowered = Instrument.lowerBitwise(src)
print("lowered:", lowered)
