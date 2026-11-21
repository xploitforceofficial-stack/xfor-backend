local neosnappstinks=pcall(function()
local a=SharedTable.new()
local b=SharedTable.new()
a.x=b
b.y=7
local c=SharedTable.cloneAndFreeze(a,true)
b.y=9
assert(c.x.y==7)
local z=pcall(function()c.x.y=1 end)
assert(not z)
end)
print(neosnappstinks and'ud'or'neosnapp reeks like piss')
