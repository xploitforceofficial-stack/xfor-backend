local zlib = require("../zlib")
local data = "print('hello world') local x = 42 -- test payload"
local raw = zlib.compressDeflate(data)
print("raw deflate len:", #raw, "b1:", raw:byte(1), "b2:", raw:byte(2))
print("roundtrip:", zlib.decompressDeflate(raw) == data)

local hex = ""
for i = 1, #raw do hex ..= string.format("%02x", raw:byte(i)) end
print("hex form:", hex:sub(1, 40))
local back = ""
for i = 1, #hex, 2 do back ..= string.char(tonumber(hex:sub(i, i+1), 16)) end
print("from-hex roundtrip:", zlib.decompressDeflate(back) == data)
