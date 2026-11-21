local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local cases = {
  "print(workspace.CurrentCamera.CFrame.Position)",
  "print(__FUHD_SAFE_INDEX__(workspace, \"CurrentCamera\").CFrame.Position)",
  "print(a.b.C.Position)",
  "print(x.Y.Z.Position)",
}
for _, s in ipairs(cases) do
  local w, e = SrcEdit.wrapSafeIndexing(s, Instrument.tokenize)
  print("IN :", s)
  print("OUT:", w or ("ERR: " .. tostring(e)))
end
