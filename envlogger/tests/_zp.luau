local s = string.char(40, 181, 47, 253)
print("outside s[1]=" .. tostring(s[1]))

local function f1(d, p)
	return d[p]
end
print("f1 d[p]      =" .. tostring(f1(s, 1)))

local function f2(d, p, i)
	return d[p + i]
end
print("f2 d[p+i]    =" .. tostring(f2(s, 1, 0)))

local function f3(d, p, n)
	local acc = 0
	local k = p
	for _ = 1, n do
		acc = acc + (d[k] or 0)
		k = k + 1
	end
	return acc
end
print("f3 loop      =" .. tostring(f3(s, 1, 4)))

local function f4(d, p, n)
	local acc = 0
	for i = 0, n - 1 do
		local idx = p + i
		local v = d[idx]
		acc = acc + (v or 0)
	end
	return acc
end
print("f4 loop      =" .. tostring(f4(s, 1, 4)))

local function f5(d, p, n)
	local acc = 0
	for i = 0, n - 1 do
		acc = acc + (d[p + i] or 0)
	end
	return acc
end
print("f5 loop      =" .. tostring(f5(s, 1, 4)))
