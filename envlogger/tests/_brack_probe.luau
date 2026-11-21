local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local cases = {
  "local t = nil print(t[\"Position\"])",
  "local t = nil print(t[k])",
  "return (nil)[\"Position\"]",
  "local a = nil print(a.b.c)",
  "print(x().Position)",
  "print((f())).Position",
}
for _, src in ipairs(cases) do
  local w, e = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
  print("IN :", src)
  print("OUT:", w or ("ERR: " .. tostring(e)))
end
