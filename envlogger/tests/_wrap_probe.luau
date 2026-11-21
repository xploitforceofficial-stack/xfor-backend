local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local cases = {
  "return nil.Position",
  "local p = nil print(p.Position)",
  "local p = nil p:SetControlPoints({})",
  "print(nil.SetControlPoints)",
  "local x = nil x.Position.Y",
  "workspace.CurrentCamera.CFrame.Position",
  "obj.Position = Vector3.new()",
  "for i=1,10 do local v = t[i] print(v.Position) end",
}
for _, src in ipairs(cases) do
  local w, e = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
  print("IN :", src)
  print("OUT:", w or ("ERR: " .. tostring(e)))
end
