local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local cases = {
  "local a = {} local b = a.b print(b.Position)",
  "print(t.foo.Position)",
  "print(game.Workspace.CurrentCamera.Position)",
  "local c = x.y.z print(c.Position)",
}
for _, src in ipairs(cases) do
  local w = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
  print("IN :", src)
  print("OUT:", w)
end
