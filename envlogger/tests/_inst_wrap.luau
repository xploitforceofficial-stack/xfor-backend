local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local src = "local p = nil print(p.Position) p:SetControlPoints({})"
local w = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
print("wrapped:", w)
local t = Instrument.apply(w, { operators = true })
print("instrumented:", t)
local t2 = Instrument.apply(w, { operators = false })
print("noops:", t2)
