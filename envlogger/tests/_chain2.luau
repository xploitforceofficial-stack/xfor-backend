local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local cases = {
  "local p = nil print(p.Position)",
  "print(game.Workspace.CurrentCamera.Position)",
  "print(t.foo.Position)",
  "print(a.b.Cam.Position)",
  "local p = nil p:SetControlPoints({})",
  "print(workspace.CurrentCamera.CFrame.Position)",
  "R[rd] = R[ra][K[rb]]",
}
for _, src in ipairs(cases) do
  local w, e = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
  print("IN :", src)
  print("OUT:", w or ("ERR: " .. tostring(e)))
end
