local luau = require("@lune/luau")
local ra, ga, ia, ka, ma, na, oa, pa, qa
local ok, err = pcall(luau.load, [[
local ra, ga, ia, ka, ma, na, oa, pa, qa
ra[ga],ra[ia],ra[ka],ra[ma]=na,oa,pa,qa
]], { debugName = "t" })
print("multi-lvalue parse:", ok, err)

local ok2, err2 = pcall(luau.load, [[
local ra, ga, ia, ka, ma, na, oa, pa, qa
local __FUHD_SAFE_INDEX__ = function(a, b) return a[b] end
__FUHD_SAFE_INDEX__(ra, ga),ra[ia],ra[ka],ra[ma]=na,oa,pa,qa
]], { debugName = "t2" })
print("wrapped-first parse:", ok2, err2)
