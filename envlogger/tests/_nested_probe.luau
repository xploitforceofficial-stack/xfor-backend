local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local cases = {
  "local a = nil print(a[K[rb]])",
  "R[rd] = R[ra][K[rb]]",
  "local x = t[a][b] print(x)",
  "local o = nil o[K[i]] = 1",
  "print(obj[K[rb]][K[rc]])",
  "local p = nil print(p.Position)",
}
for _, src in ipairs(cases) do
  local w, e = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
  print("IN :", src)
  print("OUT:", w or ("ERR: " .. tostring(e)))
end
