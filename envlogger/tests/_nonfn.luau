local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local cases = {
  "print(getPart().Position)",
  "print(f(x).Position)",
  "print((a).Position)",
  "local p = nil print(p.Position)",
}
for _, s in ipairs(cases) do
  local w, e = SrcEdit.wrapSafeIndexing(s, Instrument.tokenize)
  print("IN :", s)
  print("OUT:", w or ("ERR: " .. tostring(e)))
end
