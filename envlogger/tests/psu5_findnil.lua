local src = PSU_BODY
local marker = 'return A(I(),{},v())(...);end)'
local mi = src:find(marker, 1, true)
src = src:sub(1, mi + #marker - 2)
PSU_CUTSRC = src
return 'cut ok, len ' .. #src
