local luau = require("@lune/luau")

local src = [[local Wa,ya,bb,C,H
H=Wa[ya]bb,C=0,H[0x348c]Ya=C~=bb
]]
local ok, err = pcall(luau.load, src, { debugName = "t" })
print("parse:", ok, err)
