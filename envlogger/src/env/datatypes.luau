	local PrngTrace = require("./prngtrace")
local Serializer = require("../core/serializer")
local Symbol = require("../core/symbol")
local Spy = require("../core/spy")
local EnumItem = require("./enumitem")

local Datatypes = {}

local function argumentList(...: any): string
	local count = select("#", ...)
	local parts = table.create(count)
	for i = 1, count do
		local value = select(i, ...)
		parts[i] = Serializer.numberLiteral(tonumber(value) or 0)
	end
	return table.concat(parts, ", ")
end

local function defineValueType(
	typeName: string,
	fields: { string },
	constructorName: string?,
	computed: { [string]: (any) -> any }?
): ({ [string]: any }, (...number) -> any)
	local class = {}
	local metatable = {}

	local HIDDEN = "\1"
	local function hidden(field: string): string
		return HIDDEN .. field
	end
	metatable.__index = function(self: any, key: any): any
		if computed then
			local fn = computed[key]
			if fn ~= nil then
				return fn(self)
			end
		end
		if type(key) == "string" then
			local stored = rawget(self, hidden(key))
			if stored ~= nil then
				return stored
			end
			return class[key]
		end
		return class[key]
	end
	metatable.__metatable = "The metatable is locked"

	metatable.__newindex = function(_: any, key: any): never
		error("Unable to assign property '" .. tostring(key) .. "'. Property is read only", 2)
	end

	local ctorName = constructorName or (typeName .. ".new")

	local function construct(...: number): any
		local instance = setmetatable({}, metatable)
		for index, field in ipairs(fields) do
			local value = select(index, ...)
			rawset(instance, hidden(field), tonumber(value) or 0)
		end
		Symbol.tag(instance, {
			kind = "datatype",
			expression = ctorName .. "(" .. argumentList(...) .. ")",
			typeName = typeName,
		})
		return instance
	end

	local function componentwise(operation: (a: number, b: number) -> number)
		return function(left: any, right: any): any
			local values = {}
			for index, field in ipairs(fields) do
				local a = if type(left) == "table" then (rawget(left, hidden(field)) or 0) else tonumber(left) or 0
				local b = if type(right) == "table" then (rawget(right, hidden(field)) or 0) else tonumber(right) or 0
				values[index] = operation(a, b)
			end
			return construct(table.unpack(values))
		end
	end

	metatable.__add = componentwise(function(a, b)
		return a + b
	end)
	metatable.__sub = componentwise(function(a, b)
		return a - b
	end)
	metatable.__mul = componentwise(function(a, b)
		return a * b
	end)
	metatable.__div = componentwise(function(a, b)
		return if b == 0 then 0 else a / b
	end)

	metatable.__unm = function(self: any): any
		local values = {}
		for index, field in ipairs(fields) do
			values[index] = -(rawget(self, hidden(field)) or 0)
		end
		return construct(table.unpack(values))
	end

	metatable.__eq = function(left: any, right: any): boolean
		if type(left) ~= "table" or type(right) ~= "table" then
			return false
		end
		for _, field in ipairs(fields) do
			if rawget(left, hidden(field)) ~= rawget(right, hidden(field)) then
				return false
			end
		end
		return true
	end

	metatable.__tostring = function(self: any): string
		local parts = {}
		for index, field in ipairs(fields) do
			parts[index] = tostring(rawget(self, hidden(field)) or 0)
		end
		return table.concat(parts, ", ")
	end

	return class, construct, hidden
end

function Datatypes.build(): { [string]: any }
	local out: { [string]: any } = {}

	local vector3Class: { [string]: any }
	local makeVector3: (...number) -> any
	vector3Class, makeVector3 = defineValueType("Vector3", { "X", "Y", "Z" }, "Vector3.new", {
		Magnitude = function(self: any): number
			return math.sqrt((self.X * self.X) + (self.Y * self.Y) + (self.Z * self.Z))
		end,
		Unit = function(self: any): any
			local magnitude = math.sqrt((self.X * self.X) + (self.Y * self.Y) + (self.Z * self.Z))
			if magnitude == 0 then
				return makeVector3(0, 0, 0)
			end
			return makeVector3(self.X / magnitude, self.Y / magnitude, self.Z / magnitude)
		end,
	})
	function vector3Class:Dot(other: any): number
		return (self.X * (other.X or 0)) + (self.Y * (other.Y or 0)) + (self.Z * (other.Z or 0))
	end
	function vector3Class:Cross(other: any): any
		return makeVector3(
			self.Y * other.Z - self.Z * other.Y,
			self.Z * other.X - self.X * other.Z,
			self.X * other.Y - self.Y * other.X
		)
	end
	function vector3Class:Lerp(other: any, alpha: number): any
		return makeVector3(
			self.X + (other.X - self.X) * alpha,
			self.Y + (other.Y - self.Y) * alpha,
			self.Z + (other.Z - self.Z) * alpha
		)
	end
	function vector3Class:Abs(): any
		return makeVector3(math.abs(self.X), math.abs(self.Y), math.abs(self.Z))
	end
	function vector3Class:FuzzyEq(other: any, epsilon: number?): boolean
		local eps = epsilon or 1e-5
		return math.abs(self.X - other.X) <= eps
			and math.abs(self.Y - other.Y) <= eps
			and math.abs(self.Z - other.Z) <= eps
	end
	function vector3Class:Max(...: any): any
		local mx, my, mz = self.X, self.Y, self.Z
		for i = 1, select("#", ...) do
			local o = select(i, ...)
			mx = math.max(mx, o.X); my = math.max(my, o.Y); mz = math.max(mz, o.Z)
		end
		return makeVector3(mx, my, mz)
	end
	function vector3Class:Min(...: any): any
		local mx, my, mz = self.X, self.Y, self.Z
		for i = 1, select("#", ...) do
			local o = select(i, ...)
			mx = math.min(mx, o.X); my = math.min(my, o.Y); mz = math.min(mz, o.Z)
		end
		return makeVector3(mx, my, mz)
	end
	function vector3Class:Ceil(): any
		return makeVector3(math.ceil(self.X), math.ceil(self.Y), math.ceil(self.Z))
	end
	function vector3Class:Floor(): any
		return makeVector3(math.floor(self.X), math.floor(self.Y), math.floor(self.Z))
	end
	function vector3Class:Sign(): any
		local function sign(value: number): number
			if value > 0 then return 1 elseif value < 0 then return -1 end
			return 0
		end
		return makeVector3(sign(self.X), sign(self.Y), sign(self.Z))
	end
	function vector3Class:Angle(other: any, axis: any?): number
		local dot = self:Dot(other)
		local m1 = self.Magnitude
		local m2 = other.Magnitude
		if m1 == 0 or m2 == 0 then
			return 0
		end
		local angle = math.acos(math.clamp(dot / (m1 * m2), -1, 1))
		if axis ~= nil and type(axis.Dot) == "function" then

			if self:Cross(other):Dot(axis) < 0 then
				angle = -angle
			end
		end
		return angle
	end
	out.Vector3 = {
		new = makeVector3,
		zero = makeVector3(0, 0, 0),
		one = makeVector3(1, 1, 1),
		xAxis = makeVector3(1, 0, 0),
		yAxis = makeVector3(0, 1, 0),
		zAxis = makeVector3(0, 0, 1),
		FromNormalId = function()
			return makeVector3(0, 1, 0)
		end,
		FromAxis = function()
			return makeVector3(1, 0, 0)
		end,
	}

	local _vector2Class: { [string]: any }
	local makeVector2: (...number) -> any
	_vector2Class, makeVector2 = defineValueType("Vector2", { "X", "Y" }, "Vector2.new", {
		Magnitude = function(self: any): number
			return math.sqrt((self.X * self.X) + (self.Y * self.Y))
		end,
		Unit = function(self: any): any
			local magnitude = math.sqrt((self.X * self.X) + (self.Y * self.Y))
			if magnitude == 0 then
				return makeVector2(0, 0)
			end
			return makeVector2(self.X / magnitude, self.Y / magnitude)
		end,
	})
	function _vector2Class:Ceil(): any
		return makeVector2(math.ceil(self.X), math.ceil(self.Y))
	end
	function _vector2Class:Dot(other: any): number
		return (self.X * (other.X or 0)) + (self.Y * (other.Y or 0))
	end
	function _vector2Class:Cross(other: any): number
		return self.X * (other.Y or 0) - self.Y * (other.X or 0)
	end
	function _vector2Class:FuzzyEq(other: any, epsilon: number?): boolean
		local eps = epsilon or 1e-5
		return math.abs(self.X - other.X) <= eps and math.abs(self.Y - other.Y) <= eps
	end
	function _vector2Class:Sign(): any
		local function sign(value: number): number
			if value > 0 then return 1 elseif value < 0 then return -1 end
			return 0
		end
		return makeVector2(sign(self.X), sign(self.Y))
	end
	function _vector2Class:Max(...: any): any
		local mx, my = self.X, self.Y
		for i = 1, select("#", ...) do
			local o = select(i, ...)
			mx = math.max(mx, o.X); my = math.max(my, o.Y)
		end
		return makeVector2(mx, my)
	end
	function _vector2Class:Min(...: any): any
		local mx, my = self.X, self.Y
		for i = 1, select("#", ...) do
			local o = select(i, ...)
			mx = math.min(mx, o.X); my = math.min(my, o.Y)
		end
		return makeVector2(mx, my)
	end
	function _vector2Class:Lerp(other: any, alpha: number): any
		return makeVector2(
			self.X + (other.X - self.X) * alpha,
			self.Y + (other.Y - self.Y) * alpha
		)
	end
	function _vector2Class:Angle(other: any, axis: any?): number
		local dot = self:Dot(other)
		local m1 = self.Magnitude
		local m2 = other.Magnitude
		if m1 == 0 or m2 == 0 then
			return 0
		end
		return math.acos(math.clamp(dot / (m1 * m2), -1, 1))
	end
	function _vector2Class:Floor(): any
		return makeVector2(math.floor(self.X), math.floor(self.Y))
	end
	function _vector2Class:Abs(): any
		return makeVector2(math.abs(self.X), math.abs(self.Y))
	end
	out.Vector2 = {
		new = makeVector2,
		zero = makeVector2(0, 0),
		one = makeVector2(1, 1),
		xAxis = makeVector2(1, 0),
		yAxis = makeVector2(0, 1),
	}

	local function roundInt16(value: number?): number
		local n = math.floor(tonumber(value) or 0)
		return ((n + 32768) % 65536) - 32768
	end
	local _, makeVector2int16Raw = defineValueType("Vector2int16", { "X", "Y" }, "Vector2int16.new")
	local function makeVector2int16(x: any, y: any): any
		return makeVector2int16Raw(roundInt16(x), roundInt16(y))
	end
	out.Vector2int16 = {
		new = makeVector2int16,
		zero = makeVector2int16(0, 0),
	}
	local _, makeVector3int16Raw = defineValueType("Vector3int16", { "X", "Y", "Z" }, "Vector3int16.new")
	local function makeVector3int16(x: any, y: any, z: any): any
		return makeVector3int16Raw(roundInt16(x), roundInt16(y), roundInt16(z))
	end
	out.Vector3int16 = {
		new = makeVector3int16,
		zero = makeVector3int16(0, 0, 0),
	}

	local _, makeUDim = defineValueType("UDim", { "Scale", "Offset" }, "UDim.new")
	out.UDim = { new = makeUDim }

	local udim2Class = {}

	local function udim2Components(value: any): ({ number }, { number })
		local scales = { 0, 0 }
		local offsets = { 0, 0 }
		if type(value) == "table" then
			scales[1] = tonumber(value.X ~= nil and value.X.Scale or nil) or 0
			offsets[1] = tonumber(value.X ~= nil and value.X.Offset or nil) or 0
			scales[2] = tonumber(value.Y ~= nil and value.Y.Scale or nil) or 0
			offsets[2] = tonumber(value.Y ~= nil and value.Y.Offset or nil) or 0
		end
		return scales, offsets
	end
	udim2Class.new = nil
	local udim2Meta = {}
	udim2Meta.__metatable = "The metatable is locked"
	udim2Meta.__index = udim2Class
	function udim2Class:Lerp(other: any, alpha: number): any
		local ss, so = udim2Components(self)
		local os, oo = udim2Components(other)
		return out.UDim2.new(
			ss[1] + (os[1] - ss[1]) * alpha,
			so[1] + (oo[1] - so[1]) * alpha,
			ss[2] + (os[2] - ss[2]) * alpha,
			so[2] + (oo[2] - so[2]) * alpha
		)
	end
	udim2Meta.__add = function(left: any, right: any): any
		local ls, lo = udim2Components(left)
		local rs, ro = udim2Components(right)
		return out.UDim2.new(ls[1] + rs[1], lo[1] + ro[1], ls[2] + rs[2], lo[2] + ro[2])
	end
	udim2Meta.__sub = function(left: any, right: any): any
		local ls, lo = udim2Components(left)
		local rs, ro = udim2Components(right)
		return out.UDim2.new(ls[1] - rs[1], lo[1] - ro[1], ls[2] - rs[2], lo[2] - ro[2])
	end
	udim2Meta.__mul = function(left: any, right: any): any
		local scalar = if type(right) == "number" then right else if type(left) == "number" then left else nil
		if scalar then
			local s, o = udim2Components(if type(left) == "table" then left else right)
			return out.UDim2.new(s[1] * scalar, o[1] * scalar, s[2] * scalar, o[2] * scalar)
		end
		local ls, lo = udim2Components(left)
		local rs, ro = udim2Components(right)
		return out.UDim2.new(ls[1] * rs[1], lo[1] * ro[1], ls[2] * rs[2], lo[2] * ro[2])
	end
	udim2Meta.__eq = function(left: any, right: any): boolean
		if type(left) ~= "table" or type(right) ~= "table" then
			return false
		end
		local ls, lo = udim2Components(left)
		local rs, ro = udim2Components(right)
		return ls[1] == rs[1] and lo[1] == ro[1] and ls[2] == rs[2] and lo[2] == ro[2]
	end
	udim2Meta.__tostring = function(self: any): string
		local s, o = udim2Components(self)
		return string.format("{%s, %s}, {%s, %s}",
			Serializer.numberLiteral(s[1]), Serializer.numberLiteral(o[1]),
			Serializer.numberLiteral(s[2]), Serializer.numberLiteral(o[2]))
	end

	out.UDim2 = {
		new = function(xScale: any?, xOffset: any?, yScale: any?, yOffset: any?): any

			local xs, xo, ys, yo
			if type(xScale) == "table" and xScale.Scale ~= nil then
				xs, xo = tonumber(xScale.Scale) or 0, tonumber(xScale.Offset) or 0
				if type(xOffset) == "table" and xOffset.Scale ~= nil then
					ys, yo = tonumber(xOffset.Scale) or 0, tonumber(xOffset.Offset) or 0
				else
					ys, yo = 0, 0
				end
			else
				xs, xo = tonumber(xScale) or 0, tonumber(xOffset) or 0
				ys, yo = tonumber(yScale) or 0, tonumber(yOffset) or 0
			end
			local instance = {
				X = makeUDim(xs, xo),
				Y = makeUDim(ys, yo),
				Width = makeUDim(xs, xo),
				Height = makeUDim(ys, yo),
			}
			return setmetatable(Symbol.tag(instance, {
				kind = "datatype",
				expression = string.format(
					"UDim2.new(%s)",
					argumentList(xs, xo, ys, yo)
				),
				typeName = "UDim2",
			}), udim2Meta)
		end,
		fromScale = function(x: number, y: number): any
			return out.UDim2.new(x, 0, y, 0)
		end,
		fromOffset = function(x: number, y: number): any
			return out.UDim2.new(0, x, 0, y)
		end,
	}
	udim2Class.new = out.UDim2.new

	out.Path2DControlPoint = {
		new = function(...: any): any
			local given = select("#", ...)
			local position, leftTangent, rightTangent = ...

			for index = 1, given do
				local slot = select(index, ...)
				if Symbol.typeName(slot) ~= "UDim2" then
					local got = Symbol.typeName(slot)
					if type(got) ~= "string" or got == "" then
						got = type(Spy.unwrap(slot) or slot)
					end
					error("invalid argument #" .. tostring(index)
						.. " to 'new' (UDim2 expected, got " .. got .. ")", 2)
				end
			end
			local zero = out.UDim2.new(0, 0, 0, 0)
			local instance = {
				Position = position or zero,
				LeftTangent = leftTangent or zero,
				RightTangent = rightTangent or zero,
			}
			return Symbol.tag(instance, {
				kind = "datatype",
				expression = "Path2DControlPoint.new()",
				typeName = "Path2DControlPoint",
			})
		end,
	}

	local color3Class: { [string]: any }
	local makeColor3: (...number) -> any
	color3Class, makeColor3 = defineValueType("Color3", { "R", "G", "B" }, "Color3.new")
	function color3Class:Lerp(other: any, alpha: number): any
		return makeColor3(
			self.R + (other.R - self.R) * alpha,
			self.G + (other.G - self.G) * alpha,
			self.B + (other.B - self.B) * alpha
		)
	end
	function color3Class:ToHex(): string
		return string.format(
			"%02x%02x%02x",
			math.floor(self.R * 255 + 0.5),
			math.floor(self.G * 255 + 0.5),
			math.floor(self.B * 255 + 0.5)
		)
	end

	local function hsvToRgb(h: number, s: number, v: number): (number, number, number)
		h = h % 1
		local i = math.floor(h * 6)
		local f = h * 6 - i
		local p = v * (1 - s)
		local q = v * (1 - f * s)
		local t = v * (1 - (1 - f) * s)
		if i % 6 == 0 then return v, t, p
		elseif i % 6 == 1 then return q, v, p
		elseif i % 6 == 2 then return p, v, t
		elseif i % 6 == 3 then return p, q, v
		elseif i % 6 == 4 then return t, p, v
		end
		return v, p, q
	end

	function color3Class:ToHSV(): (number, number, number)

		local r = math.clamp(self.R, 0, 1)
		local g = math.clamp(self.G, 0, 1)
		local b = math.clamp(self.B, 0, 1)
		local max = math.max(r, g, b)
		local min = math.min(r, g, b)
		local delta = max - min
		local h = 0
		if delta > 0 then
			if max == r then
				h = ((g - b) / delta) % 6
			elseif max == g then
				h = (b - r) / delta + 2
			else
				h = (r - g) / delta + 4
			end
			h /= 6
		end
		local s = if max == 0 then 0 else delta / max
		return h, s, max
	end

	local rawColor3 = makeColor3
	makeColor3 = function(r: any?, g: any?, b: any?): any
		return rawColor3(
			math.clamp(tonumber(r) or 0, 0, 1),
			math.clamp(tonumber(g) or 0, 0, 1),
			math.clamp(tonumber(b) or 0, 0, 1)
		)
	end

	out.Color3 = {
		new = makeColor3,
		fromRGB = function(r: number?, g: number?, b: number?): any
			return makeColor3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
		end,

		toHSV = function(color: any): (number, number, number)
			if Symbol.typeName(color) ~= "Color3" then
				error("Color3.toHSV requires a Color3 argument", 2)
			end
			return color:ToHSV()
		end,
		fromHSV = function(...: any): any
			if select("#", ...) < 3 then
				error("Color3.fromHSV requires three arguments", 2)
			end
			local h, s, v = ...
			local r, g, b = hsvToRgb(tonumber(h) or 0, tonumber(s) or 0, tonumber(v) or 0)
			return makeColor3(r, g, b)
		end,
		fromHex = function(hex: any): any
			if hex == nil then
				error("Color3.fromHex requires one argument", 2)
			end
			local text = string.gsub(tostring(hex or ""), "^#", "")
			if #text == 6 and string.match(text, "^%x%x%x%x%x%x$") then
				local r = tonumber(string.sub(text, 1, 2), 16) or 0
				local g = tonumber(string.sub(text, 3, 4), 16) or 0
				local b = tonumber(string.sub(text, 5, 6), 16) or 0
				return makeColor3(r / 255, g / 255, b / 255)
			end
			return makeColor3(1, 1, 1)
		end,
	}

	local CFH = "\1"
	local cfHidden = function(field: string): string
		return CFH .. field
	end
	local cframeMeta = {}
	cframeMeta.__metatable = "The metatable is locked"
	local _cframeIdentity: any = nil
	cframeMeta.__index = function(self: any, key: any): any
		if key == "Rotation" then
			local own = rawget(self, cfHidden("Rotation"))
			if own ~= nil then
				return own
			end
			if not _cframeIdentity then
				_cframeIdentity = setmetatable({}, cframeMeta)
				rawset(_cframeIdentity, cfHidden("X"), 0)
				rawset(_cframeIdentity, cfHidden("Y"), 0)
				rawset(_cframeIdentity, cfHidden("Z"), 0)
				rawset(_cframeIdentity, cfHidden("Position"), makeVector3(0, 0, 0))
				rawset(_cframeIdentity, cfHidden("p"), makeVector3(0, 0, 0))
				rawset(_cframeIdentity, cfHidden("LookVector"), makeVector3(0, 0, -1))
				rawset(_cframeIdentity, cfHidden("RightVector"), makeVector3(1, 0, 0))
				rawset(_cframeIdentity, cfHidden("UpVector"), makeVector3(0, 1, 0))
				rawset(_cframeIdentity, cfHidden("XVector"), makeVector3(1, 0, 0))
				rawset(_cframeIdentity, cfHidden("YVector"), makeVector3(0, 1, 0))
				rawset(_cframeIdentity, cfHidden("ZVector"), makeVector3(0, 0, 1))
				rawset(_cframeIdentity, cfHidden("Rotation"), _cframeIdentity)
				Symbol.tag(_cframeIdentity, {
					kind = "datatype",
					expression = "CFrame.new()",
					typeName = "CFrame",
				})
			end
			return _cframeIdentity
		end
		local stored = if type(key) == "string" then rawget(self, cfHidden(key)) else nil
		if stored ~= nil then
			return stored
		end
		return cframeMeta[key]
	end
	cframeMeta.__newindex = function(_: any, key: any): never
		error("Unable to assign property '" .. tostring(key) .. "'. Property is read only", 2)
	end

	local function makeCFrame(x: number?, y: number?, z: number?): any
		local px, py, pz = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
		local instance = setmetatable({}, cframeMeta)
		rawset(instance, cfHidden("X"), px)
		rawset(instance, cfHidden("Y"), py)
		rawset(instance, cfHidden("Z"), pz)
		rawset(instance, cfHidden("Position"), makeVector3(px, py, pz))
		rawset(instance, cfHidden("p"), makeVector3(px, py, pz))
		rawset(instance, cfHidden("LookVector"), makeVector3(0, 0, -1))
		rawset(instance, cfHidden("RightVector"), makeVector3(1, 0, 0))
		rawset(instance, cfHidden("UpVector"), makeVector3(0, 1, 0))
		rawset(instance, cfHidden("XVector"), makeVector3(1, 0, 0))
		rawset(instance, cfHidden("YVector"), makeVector3(0, 1, 0))
		rawset(instance, cfHidden("ZVector"), makeVector3(0, 0, 1))
		return Symbol.tag(instance, {
			kind = "datatype",
			expression = "CFrame.new(" .. argumentList(px, py, pz) .. ")",
			typeName = "CFrame",
		})
	end

	cframeMeta.__mul = function(left: any, right: any): any
		local lx = if type(left) == "table" then rawget(left, cfHidden("X")) or 0 else 0
		local ly = if type(left) == "table" then rawget(left, cfHidden("Y")) or 0 else 0
		local lz = if type(left) == "table" then rawget(left, cfHidden("Z")) or 0 else 0
		local rx = if type(right) == "table" then rawget(right, cfHidden("X")) or 0 else 0
		local ry = if type(right) == "table" then rawget(right, cfHidden("Y")) or 0 else 0
		local rz = if type(right) == "table" then rawget(right, cfHidden("Z")) or 0 else 0
		return makeCFrame(lx + rx, ly + ry, lz + rz)
	end
	cframeMeta.__add = cframeMeta.__mul
	cframeMeta.__sub = function(left: any, right: any): any
		local lx = rawget(left, cfHidden("X")) or 0
		local ly = rawget(left, cfHidden("Y")) or 0
		local lz = rawget(left, cfHidden("Z")) or 0
		local rx = if type(right) == "table" then rawget(right, cfHidden("X")) or 0 else 0
		local ry = if type(right) == "table" then rawget(right, cfHidden("Y")) or 0 else 0
		local rz = if type(right) == "table" then rawget(right, cfHidden("Z")) or 0 else 0
		return makeCFrame(lx - rx, ly - ry, lz - rz)
	end
	cframeMeta.__eq = function(left: any, right: any): boolean
		if type(left) ~= "table" or type(right) ~= "table" then
			return false
		end
		return rawget(left, cfHidden("X")) == rawget(right, cfHidden("X"))
			and rawget(left, cfHidden("Y")) == rawget(right, cfHidden("Y"))
			and rawget(left, cfHidden("Z")) == rawget(right, cfHidden("Z"))
	end
	cframeMeta.__tostring = function(self: any): string

		local parts = {}
		for _, n in { self:GetComponents() } do
			table.insert(parts, tostring(n))
		end
		return table.concat(parts, ", ")
	end
	function cframeMeta:Inverse(): any
		return makeCFrame(-self.X, -self.Y, -self.Z)
	end
	function cframeMeta:Lerp(other: any, alpha: number): any
		return makeCFrame(
			self.X + (other.X - self.X) * alpha,
			self.Y + (other.Y - self.Y) * alpha,
			self.Z + (other.Z - self.Z) * alpha
		)
	end
	function cframeMeta:ToWorldSpace(other: any): any
		return makeCFrame(self.X + other.X, self.Y + other.Y, self.Z + other.Z)
	end
	function cframeMeta:ToObjectSpace(other: any): any
		return makeCFrame(self.X - other.X, self.Y - other.Y, self.Z - other.Z)
	end
	function cframeMeta:GetComponents(): ...number
		return self.X, self.Y, self.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1
	end
	cframeMeta.components = cframeMeta.GetComponents

	out.CFrame = {
		new = makeCFrame,
		identity = makeCFrame(0, 0, 0),
		Angles = function()
			return makeCFrame(0, 0, 0)
		end,
		fromEulerAnglesXYZ = function()
			return makeCFrame(0, 0, 0)
		end,
		fromEulerAnglesYXZ = function()
			return makeCFrame(0, 0, 0)
		end,
		fromEulerAngles = function()
			return makeCFrame(0, 0, 0)
		end,
		fromOrientation = function()
			return makeCFrame(0, 0, 0)
		end,
		fromAxisAngle = function()
			return makeCFrame(0, 0, 0)
		end,
		fromMatrix = function(pos: any)
			if type(pos) == "table" then
				return makeCFrame(pos.X, pos.Y, pos.Z)
			end
			return makeCFrame(0, 0, 0)
		end,
		lookAt = function(from: any)
			if type(from) == "table" then
				return makeCFrame(from.X, from.Y, from.Z)
			end
			return makeCFrame(0, 0, 0)
		end,
		lookAlong = function(at: any)
			if type(at) == "table" then
				return makeCFrame(at.X, at.Y, at.Z)
			end
			return makeCFrame(0, 0, 0)
		end,
		fromRotationBetweenVectors = function()
			return makeCFrame(0, 0, 0)
		end,
	}

	local function makeRegion3(min: any?, max: any?): any
		local mn = min
		local mx = max
		if type(mn) ~= "table" then
			mn = makeVector3(tonumber(min) or 0, 0, 0)
		end
		if type(mx) ~= "table" then
			mx = makeVector3(tonumber(max) or 0, 0, 0)
		end
		local size = makeVector3(mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z)
		local center = makeCFrame((mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2, (mn.Z + mx.Z) / 2)
		return Symbol.tag({
			Min = mn,
			Max = mx,
			Size = size,
			CFrame = center,
			ExpandToGrid = function(_self: any, resolution: any): any

				local step = tonumber(resolution)
				if step == nil or step ~= step or step <= 0 or step == math.huge then

					return makeRegion3(mn, mx)
				end
				return makeRegion3(
					makeVector3(
						math.floor(mn.X / step) * step,
						math.floor(mn.Y / step) * step,
						math.floor(mn.Z / step) * step
					),
					makeVector3(
						math.ceil(mx.X / step) * step,
						math.ceil(mx.Y / step) * step,
						math.ceil(mx.Z / step) * step
					)
				)
			end,
		}, {
			kind = "datatype",
			expression = "Region3.new(Vector3.new(), Vector3.new())",
			typeName = "Region3",
		})
	end
	out.Region3 = { new = makeRegion3 }

	out.Region3int16 = {
		new = function(min: any?, max: any?): any
			local region = makeRegion3(min, max)
			local descriptor = Symbol.get(region)
			if descriptor ~= nil then
				descriptor.expression = "Region3int16.new(Vector3int16.new(), Vector3int16.new())"
				descriptor.typeName = "Region3int16"
			end
			return region
		end,
	}

	out.NumberRange = {
		new = function(min: number?, max: number?): any
			local low = tonumber(min) or 0
			local high = tonumber(max) or low
			if high < low then
				error("NumberRange.new: min must be less than or equal to max")
			end
			return Symbol.tag({ Min = low, Max = high }, {
				kind = "datatype",
				expression = "NumberRange.new(" .. argumentList(low, high) .. ")",
				typeName = "NumberRange",
			})
		end,
	}

	out.Rect = {
		new = function(minX: any?, minY: any?, maxX: any?, maxY: any?): any

			local loX, loY, hiX, hiY
			if type(minX) == "table" and minX.X ~= nil then
				local minV, maxV = minX, if type(minY) == "table" then minY else minX
				loX, loY = tonumber(minV.X) or 0, tonumber(minV.Y) or 0
				hiX, hiY = tonumber(maxV.X) or 0, tonumber(maxV.Y) or 0
			else
				loX, loY = tonumber(minX) or 0, tonumber(minY) or 0
				hiX, hiY = tonumber(maxX) or 0, tonumber(maxY) or 0
			end
			return Symbol.tag({
				Min = makeVector2(loX, loY),
				Max = makeVector2(hiX, hiY),
				Width = math.abs(hiX - loX),
				Height = math.abs(hiY - loY),
				Size = makeVector2(math.abs(hiX - loX), math.abs(hiY - loY)),
			}, {
				kind = "datatype",
				expression = "Rect.new(" .. argumentList(loX, loY, hiX, hiY) .. ")",
				typeName = "Rect",
			})
		end,
	}

	local brickColorNames: { [string]: { number } } = {
		White = { 0.972549, 0.972549, 0.972549 },
		Grey = { 0.639216, 0.635294, 0.647059 },
		Gray = { 0.639216, 0.635294, 0.647059 },
		LightYellow = { 0.996078, 0.909804, 0.568627 },
		BrightYellow = { 0.968627, 0.870588, 0.258824 },
		BrightOrange = { 0.886275, 0.517647, 0.121569 },
		BrightRed = { 0.768627, 0.156863, 0.109804 },
		BrightBlue = { 0.098039, 0.462745, 0.823529 },
		ElectricBlue = { 0.113725, 0.564706, 0.937255 },
		BrightGreen = { 0, 1, 0 },
		DarkGreen = { 0.156863, 0.294118, 0.211765 },
		Green = { 0, 1, 0 },
		Red = { 1, 0, 0 },
		Blue = { 0, 0, 1 },
		Black = { 0.082353, 0.086275, 0.096078 },
		MediumStoneGrey = { 0.639216, 0.635294, 0.647059 },

		["Bright green"] = { 0.294118, 0.592157, 0.294118 },
		["Bright red"] = { 0.768627, 0.156863, 0.109804 },
		["Bright blue"] = { 0.050980, 0.411765, 0.674510 },
		["Bright yellow"] = { 0.960784, 0.803922, 0.188235 },
		["Bright orange"] = { 0.854902, 0.521569, 0.254902 },
		["Dark green"] = { 0.156863, 0.498039, 0.278431 },
		["Medium stone grey"] = { 0.639216, 0.635294, 0.647059 },
		["Dark stone grey"] = { 0.388235, 0.372549, 0.384314 },
		["Really red"] = { 0.639216, 0.294118, 0.294118 },
		["White"] = { 0.949020, 0.952941, 0.952941 },
		["Black"] = { 0.105882, 0.164706, 0.207843 },
	}
	out.BrickColor = {
		new = function(value: any): any
			local numberValue = tonumber(value)
			local label: any
			if numberValue then
				label = "BrickColor " .. numberValue
			elseif type(value) == "string" then
				label = value
			else
				label = "Medium stone grey"
			end
			local rgb = brickColorNames[label]
			local color = if rgb then makeColor3(rgb[1], rgb[2], rgb[3]) else makeColor3(0.639216, 0.635294, 0.647059)

			local nameToNumber: { [string]: number } = {
				["Bright green"] = 37, ["Bright red"] = 21, ["Bright blue"] = 23,
				["Bright yellow"] = 24, ["Bright orange"] = 105, ["Dark green"] = 28,
				["Medium stone grey"] = 194, ["Dark stone grey"] = 199,
				["Really red"] = 1004, ["White"] = 1, ["Black"] = 26,
			}
			return Symbol.tag({
				Name = label,
				Color = color,
				Number = numberValue or nameToNumber[label] or 194,
				r = color.R,
				g = color.G,
				b = color.B,
			}, {
				kind = "datatype",
				expression = "BrickColor.new(" .. Serializer.stringLiteral(label) .. ")",
				typeName = "BrickColor",
			})
		end,
		random = function(): any
			return out.BrickColor.new("Bright red")
		end,
		palette = function(number: any): any
			return out.BrickColor.new(tonumber(number) or 194)
		end,
		White = function(): any
			return out.BrickColor.new("White")
		end,
		Gray = function(): any
			return out.BrickColor.new("Medium stone grey")
		end,
		DarkGray = function(): any
			return out.BrickColor.new("Dark stone grey")
		end,
		Black = function(): any
			return out.BrickColor.new("Black")
		end,
		Red = function(): any
			return out.BrickColor.new("Bright red")
		end,
		Green = function(): any
			return out.BrickColor.new("Bright green")
		end,
		Blue = function(): any
			return out.BrickColor.new("Bright blue")
		end,
		Yellow = function(): any
			return out.BrickColor.new("Bright yellow")
		end,
	}

	out.TweenInfo = {
		new = function(duration: number?, easingStyle: any?, easingDirection: any?, repeatCount: any?, reverses: any?, delayTime: any?): any
			local seconds = tonumber(duration) or 1

			local style = if type(easingStyle) == "table" and easingStyle.Name
				then easingStyle else EnumItem.new("Quad", 3)
			return Symbol.tag({
				Time = seconds,
				DelayTime = tonumber(delayTime) or 0,
				RepeatCount = tonumber(repeatCount) or 0,
				Reverses = reverses == true,
				EasingStyle = style,
				EasingDirection = if type(easingDirection) == "table" and easingDirection.Name
					then easingDirection else EnumItem.new("Out", 1),
			}, {
				kind = "datatype",
				expression = "TweenInfo.new(" .. Serializer.numberLiteral(seconds) .. ")",
				typeName = "TweenInfo",
			})
		end,
	}

	out.Ray = {
		new = function(origin: any, direction: any): any
			local ray = Symbol.tag({ Origin = origin, Direction = direction }, {
				kind = "datatype",
				expression = "Ray.new(Vector3.new(), Vector3.new())",
				typeName = "Ray",
			})
			rawset(ray, "ClosestPoint", function(self: any, point: any): any
				local o = self.Origin or makeVector3()
				local d = self.Direction or makeVector3(0, -1, 0)
				local to = point - o
				local mag = d.Magnitude
				if mag == 0 then return o end
				local proj = to:Dot(d) / (mag * mag)
				proj = math.max(0, math.min(1, proj))
				return o + d * proj
			end)
			return ray
		end,
	}

	local function makeFlagSet(typeName: string, flagNames: { string }, expression: string): any
		return function(...: any): any
			local values: { [string]: any } = {}
			for _, name in ipairs(flagNames) do
				values[name] = false
			end

			local function apply(item: any)
				if item == nil then
					return
				end
				local itemType = type(item)
				if itemType == "table" or itemType == "userdata" then
					local ok, itemName = pcall(function()
						return (item :: any).Name
					end)
					if ok and itemName ~= nil and values[tostring(itemName)] ~= nil then
						values[tostring(itemName)] = true
						return
					end

					if itemType == "table" then
						for key, value in pairs(item) do
							local name = if type(key) == "table" and (key :: any).Name ~= nil
								then tostring((key :: any).Name)
								else tostring(key)
							if values[name] ~= nil then
								values[name] = value == true
							end
						end
					end
				end
			end
			for i = 1, select("#", ...) do
				apply((select(i, ...)))
			end

			local proxy = setmetatable({}, {
				__index = values,
				__iter = function()
					return next, values
				end,
				__metatable = "The metatable is locked",
				__newindex = function(_, k: any): never
					error(string.format("%s cannot be assigned to", tostring(k)), 2)
				end,
			})
			return Symbol.tag(proxy, {
				kind = "datatype",
				expression = expression,
				typeName = typeName,
			})
		end
	end
	out.Faces = {
		new = makeFlagSet("Faces", { "Top", "Bottom", "Front", "Back", "Left", "Right" }, "Faces.new({})"),
	}
	out.Axes = {
		new = makeFlagSet("Axes", { "X", "Y", "Z", "Top", "Bottom", "Front", "Back", "Left", "Right" }, "Axes.new({})"),
	}

	out.ColorSequenceKeypoint = {
		new = function(time: number?, value: any?, _: any?): any
			local color = if type(value) == "table" and value.R ~= nil then value else makeColor3(1, 1, 1)
			return Symbol.tag({
				Time = tonumber(time) or 0,
				Value = color,
			}, {
				kind = "datatype",
				expression = "ColorSequenceKeypoint.new(" .. Serializer.numberLiteral(tonumber(time) or 0) .. ", Color3.new())",
				typeName = "ColorSequenceKeypoint",
			})
		end,
	}
	out.NumberSequenceKeypoint = {
		new = function(time: number?, value: number?, envelope: number?): any
			return Symbol.tag({
				Time = tonumber(time) or 0,
				Value = tonumber(value) or 0,
				Envelope = tonumber(envelope) or 0,
			}, {
				kind = "datatype",
				expression = "NumberSequenceKeypoint.new(" .. Serializer.numberLiteral(tonumber(time) or 0)
					.. ", " .. Serializer.numberLiteral(tonumber(value) or 0) .. ")",
				typeName = "NumberSequenceKeypoint",
			})
		end,
	}

	out.ColorSequence = {
		new = function(first: any, second: any): any
			local keypoints: { any } = {}
			if type(first) == "table" and first.Time ~= nil and first.Value ~= nil then

				keypoints = { first }
			elseif type(first) == "table" and first.R == nil and second == nil and #first > 0 then

				for _, k in ipairs(first) do
					table.insert(keypoints, k)
				end
			else
				local a = if type(first) == "table" and first.R ~= nil then first else makeColor3(1, 1, 1)
				local b = if type(second) == "table" and second.R ~= nil then second else a
				keypoints = {
					out.ColorSequenceKeypoint.new(0, a),
					out.ColorSequenceKeypoint.new(1, b),
				}
			end
			return Symbol.tag({ Keypoints = keypoints }, {
				kind = "datatype",
				expression = "ColorSequence.new(Color3.new())",
				typeName = "ColorSequence",
			})
		end,
	}
	out.NumberSequence = {
		new = function(...: any): any
			local keypoints = {}
			local args = { ... }
			if #args == 1 and type(args[1]) == "table" then
				for _, k in ipairs(args[1]) do
					table.insert(keypoints, k)
				end
			elseif #args == 1 and type(args[1]) == "number" then

				table.insert(keypoints, out.NumberSequenceKeypoint.new(0, args[1]))
				table.insert(keypoints, out.NumberSequenceKeypoint.new(1, args[1]))
			elseif #args == 2 and type(args[1]) == "number" and type(args[2]) == "number" then

				table.insert(keypoints, out.NumberSequenceKeypoint.new(0, args[1]))
				table.insert(keypoints, out.NumberSequenceKeypoint.new(1, args[2]))
			else
				for _, k in ipairs(args) do
					table.insert(keypoints, k)
				end
			end
			return Symbol.tag({ Keypoints = keypoints }, {
				kind = "datatype",
				expression = "NumberSequence.new(...)",
				typeName = "NumberSequence",
			})
		end,
	}

	local sharedStorage: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
	local sharedFrozen: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

	local function isShared(value: any): boolean
		return type(value) == "table" and sharedStorage[value] ~= nil
	end

	local function checkSharedValue(value: any, level: number)
		local valueType = type(value)
		if valueType == "function" or valueType == "thread" then
			error("SharedTable values cannot be functions or threads", level)
		end
		if valueType == "table" and not isShared(value) and Symbol.get(value) == nil then
			error("SharedTable values cannot be Lua tables", level)
		end
	end

	local function makeShared(storage: { [any]: any }, frozen: boolean): any
		local handle: any = {}
		sharedStorage[handle] = storage
		if frozen then
			sharedFrozen[handle] = true
		end
		setmetatable(handle, {
			__index = function(_: any, key: any): any
				return storage[key]
			end,
			__newindex = function(_: any, key: any, value: any)
				if sharedFrozen[handle] then
					error("Attempt to modify a frozen SharedTable", 2)
				end
				local keyType = type(key)
				if keyType ~= "string" and keyType ~= "number" then
					error("SharedTable keys must be strings or numbers", 2)
				end
				checkSharedValue(value, 3)
				storage[key] = value
			end,
			__len = function(): number
				local count = 0
				for _ in pairs(storage) do
					count += 1
				end
				return count
			end,
			__metatable = "The metatable is locked",
		})
		return Symbol.tag(handle, {
			kind = "datatype",
			expression = "SharedTable.new()",
			typeName = "SharedTable",
		})
	end

	local function cloneShared(handle: any, deep: boolean, frozen: boolean, seen: { [any]: any }): any
		local existing = seen[handle]
		if existing ~= nil then
			return existing
		end
		local copy = makeShared({}, false)
		seen[handle] = copy

		local target = sharedStorage[copy]
		for key, value in pairs(sharedStorage[handle]) do
			if deep and isShared(value) then
				target[key] = cloneShared(value, true, frozen, seen)
			else
				target[key] = value
			end
		end
		if frozen then
			sharedFrozen[copy] = true
		end
		return copy
	end

	local function expectShared(value: any, member: string): any
		if not isShared(value) then
			error(member .. " requires a SharedTable argument", 3)
		end
		return sharedStorage[value]
	end

	local function expectMutable(value: any, member: string): any
		local storage = expectShared(value, member)
		if sharedFrozen[value] then
			error("Attempt to modify a frozen SharedTable", 3)
		end
		return storage
	end

	out.SharedTable = {
		new = function(initial: any?): any
			local storage: { [any]: any } = {}
			if type(initial) == "table" then
				for key, value in pairs(initial) do
					checkSharedValue(value, 3)
					storage[key] = value
				end
			end
			return makeShared(storage, false)
		end,
		clone = function(shared: any, deep: any?): any
			expectShared(shared, "SharedTable.clone")
			return cloneShared(shared, deep == true, false, {})
		end,
		cloneAndFreeze = function(shared: any, deep: any?): any
			expectShared(shared, "SharedTable.cloneAndFreeze")
			return cloneShared(shared, deep == true, true, {})
		end,
		isFrozen = function(shared: any): boolean
			expectShared(shared, "SharedTable.isFrozen")
			return sharedFrozen[shared] == true
		end,
		size = function(shared: any): number
			local storage = expectShared(shared, "SharedTable.size")
			local count = 0
			for _ in pairs(storage) do
				count += 1
			end
			return count
		end,
		clear = function(shared: any)
			local storage = expectMutable(shared, "SharedTable.clear")
			for key in pairs(storage) do
				storage[key] = nil
			end
		end,
		increment = function(shared: any, key: any, delta: any): any
			local storage = expectMutable(shared, "SharedTable.increment")
			local current = storage[key]
			if type(current) ~= "number" then
				error("SharedTable.increment requires a number value", 2)
			end
			storage[key] = current + (tonumber(delta) or 0)
			return current
		end,
		update = function(shared: any, key: any, transform: any)
			local storage = expectMutable(shared, "SharedTable.update")
			if type(transform) ~= "function" then
				error("SharedTable.update requires a function argument", 2)
			end
			local updated = transform(storage[key])
			checkSharedValue(updated, 2)
			storage[key] = updated
		end,
	}

	local unseededCounter = 0

	out.Random = {
		new = function(seed: any?): any
			if seed ~= nil and type(Spy.unwrap(seed) or seed) ~= "number" then
				local got = Symbol.typeName(seed)
				if type(got) ~= "string" or got == "" then
					got = type(Spy.unwrap(seed) or seed)
				end
				error("invalid argument #1 to 'new' (number expected, got " .. got .. ")", 2)
			end

			local unwrappedSeed = tonumber(Spy.unwrap(seed) or seed)

			local Fidelity = require("./fidelity")
			local box: { stHi: number, stLo: number } = { stHi = 0, stLo = 0 }

			local function seedState(base: number)

				box.stHi, box.stLo = Fidelity.pcgSeed(base)
			end

			local function next32(): number
				local out = Fidelity.pcgNext32(box.stHi, box.stLo)
				box.stHi, box.stLo = Fidelity.pcgStep(box.stHi, box.stLo)
				return out
			end

			local function nextFloat(): number
				local rl = next32()
				local rh = next32()
				return (rl + rh * 4294967296) * 5.421010862427522e-20
			end

			local function nextInteger(l: number, u: number): number
				local span = bit32.band(u - l, 0xFFFFFFFF)
				local o = next32()
				local a0 = (span + 1) % 65536
				local a1 = math.floor((span + 1) / 65536)
				local b0 = o % 65536
				local b1 = math.floor(o / 65536)
				local ll = a0 * b0
				local mid = a1 * b0 + a0 * b1 + math.floor(ll / 65536)
				local hh = a1 * b1 + math.floor(mid / 65536)
				return l + (hh % 4294967296)
			end

			if unwrappedSeed ~= nil then
				seedState(unwrappedSeed)
			else

				unseededCounter += 1
				local entropy = (math.random(0, 0x7FFFFFFF) * 65536
					+ math.random(0, 0xFFFF)) % 4294967296
				entropy = (entropy
					+ math.floor(os.clock() * 1000000)
					+ unseededCounter * 2654435761) % 4294967296
				seedState(entropy)
			end

			local rng: any = {}
			rng.__box = box

			rng.NextNumber = function(_self: any, ...: any): number
				local given = select("#", ...)
				if given ~= 0 and given ~= 2 then
					error("Random:NextNumber requires 0 or 2 arguments", 2)
				end
				local low, high = ...
				local value = nextFloat()
				PrngTrace.mark(value)
				if given == 2 then
					local lo = tonumber(low) or 0
					local hi = tonumber(high) or 0
					local ranged = lo + value * (hi - lo)
					PrngTrace.mark(ranged)

					return ranged
				end
				return value
			end				rng.NextInteger = function(_self: any, low: any?, high: any?): number
					if low == nil then
						error("invalid argument #1 to 'NextInteger' (number expected, got nil)", 2)
					end
					if high == nil then
						error("invalid argument #2 to 'NextInteger' (number expected, got nil)", 2)
					end
					local lo = tonumber(low)
					local hi = tonumber(high)
					if lo == nil or lo % 1 ~= 0 then
						error("invalid argument #1 to 'NextInteger' (number has no integer representation)", 2)
					end
					if hi == nil or hi % 1 ~= 0 then
						error("invalid argument #2 to 'NextInteger' (number has no integer representation)", 2)
					end
					if hi < lo then
						error("invalid argument #2 to 'NextInteger' (max must be greater than or equal to min)", 2)
					end
					local drawn = nextInteger(lo, hi)
					PrngTrace.mark(drawn)
					return drawn
				end

			rng.NextUnitVector = function(): any
				return makeVector3(
					nextFloat() * 2 - 1,
					nextFloat() * 2 - 1,
					nextFloat() * 2 - 1
				).Unit
			end

			rng.Shuffle = function(_self: any, target: any): any
				if type(target) ~= "table" then
					error(string.format(
						"invalid argument #1 to 'Shuffle' (table expected, got %s)",
						globals.typeof(target)), 2)
				end
				local count = #target
				for i = count, 2, -1 do
					local roll = math.floor(nextFloat() * i) + 1
					if roll > i then
						roll = i
					end
					if roll ~= i then
						target[i], target[roll] = target[roll], target[i]
					end
				end
				return target
			end

			rng.Clone = function(_self: any): any

				local copy = out.Random.new(0)
				copy.__box.stHi = box.stHi
				copy.__box.stLo = box.stLo
				return copy
			end

			rng.__box = box
			require("./fidelity").registerTree(rng)
			return Symbol.tag(rng, {
				kind = "datatype",
				expression = "Random.new(" .. Serializer.numberLiteral(unwrappedSeed or 0) .. ")",
				typeName = "Random",
			})
		end,
	}

	out.RaycastParams = {
		new = function(): any
			return Symbol.tag({
				FilterType = 0,
				FilterDescendantsInstances = {},
				IgnoreWater = false,
				RespectCanCollide = false,
			}, {
				kind = "datatype",
				expression = "RaycastParams.new()",
				typeName = "RaycastParams",
			})
		end,
	}

	out.OverlapParams = {
		new = function(): any
			return Symbol.tag({
				FilterType = 0,
				FilterDescendantsInstances = {},
				MaxParts = 2000,
			}, {
				kind = "datatype",
				expression = "OverlapParams.new()",
				typeName = "OverlapParams",
			})
		end,
	}

	out.FloatCurveKey = {
		new = function(time: number?, value: number?, interpolation: any?): any
			return Symbol.tag({
				Time = tonumber(time) or 0,
				Value = tonumber(value) or 0,
				Interpolation = interpolation or EnumItem.new("Linear", 0),
				LeftTangent = 0,
				RightTangent = 0,
			}, {
				kind = "datatype",
				expression = "FloatCurveKey.new()",
				typeName = "FloatCurveKey",
			})
		end,
	}

	out.ValueCurveKey = {
		new = function(time: number?, value: number?, interpolation: any?): any
			return Symbol.tag({
				Time = tonumber(time) or 0,
				Value = tonumber(value) or 0,
				Interpolation = interpolation or EnumItem.new("Linear", 0),
			}, {
				kind = "datatype",
				expression = "ValueCurveKey.new()",
				typeName = "ValueCurveKey",
			})
		end,
	}

	out.RotationCurveKey = {
		new = function(time: number?, value: any?, interpolation: any?): any
			return Symbol.tag({
				Time = tonumber(time) or 0,
				Value = value or makeCFrame(),
				Interpolation = interpolation or EnumItem.new("Linear", 0),
				LeftTangent = 0,
				RightTangent = 0,
			}, {
				kind = "datatype",
				expression = "RotationCurveKey.new()",
				typeName = "RotationCurveKey",
			})
		end,
	}

	out.CatalogSearchParams = {
		new = function(): any
			return Symbol.tag({
				SearchKeyword = "",
				CategoryFilter = EnumItem.new("None", 0),
				SortType = EnumItem.new("Relevance", 0),
				SortAggregation = EnumItem.new("PriceLowHigh", 0),
				SalesTypeFilter = EnumItem.new("All", 0),
				MinPrice = 0,
				MaxPrice = math.huge,
				CreatorName = "",
				CreatorId = 0,
				Limit = 100,
				CategoryFilters = {},
				AssetTypes = {},
				IncludeOffSale = false,
				BundleTypes = {},
			}, {
				kind = "datatype",
				expression = "CatalogSearchParams.new()",
				typeName = "CatalogSearchParams",
			})
		end,
	}

	out.SecurityCapabilities = {
		new = function(value: any?): any
			local caps: any
			caps = Symbol.tag({
				Value = tonumber(value) or 0,
				Add = function(_self: any, other: any): any
					local otherValue = if type(other) == "table" and other.Value then tonumber(other.Value) or 0 else tonumber(other) or 0
					return out.SecurityCapabilities.new(bit32.bor(tonumber(caps.Value) or 0, otherValue))
				end,
				Add1 = function(_self: any, bits: any): any
					return out.SecurityCapabilities.new(bit32.bor(tonumber(caps.Value) or 0, tonumber(bits) or 0))
				end,
				Remove = function(_self: any, other: any): any
					local otherValue = if type(other) == "table" and other.Value then tonumber(other.Value) or 0 else tonumber(other) or 0
					return out.SecurityCapabilities.new(bit32.band(tonumber(caps.Value) or 0, bit32.bnot(otherValue)))
				end,
				Has = function(_self: any, other: any): boolean
					local otherValue = if type(other) == "table" and other.Value then tonumber(other.Value) or 0 else tonumber(other) or 0
					return bit32.band(tonumber(caps.Value) or 0, otherValue) == otherValue
				end,
				Contains = function(_self: any, other: any): boolean
					local otherValue = if type(other) == "table" and other.Value then tonumber(other.Value) or 0 else tonumber(other) or 0
					return bit32.band(tonumber(caps.Value) or 0, otherValue) == otherValue
				end,
			}, {
				kind = "datatype",
				expression = "SecurityCapabilities.new()",
				typeName = "SecurityCapabilities",
			})
			return caps
		end,
		fromCurrent = function(): any
			return out.SecurityCapabilities.new(0)
		end,
		None = function(): any
			return out.SecurityCapabilities.new(0)
		end,
		Default = function(): any
			return out.SecurityCapabilities.new(0)
		end,
	}

	local function datetimeFromTable(t: { [string]: number }): any
		local timestamp = math.floor(os.time({
			year = t.Year or 1970, month = t.Month or 1, day = t.Day or 1,
			hour = t.Hour or 0, min = t.Minute or 0, sec = t.Second or 0,
		}) - ((t.Offset or 0) * 3600))
		return out.DateTime.fromUnixTimestamp(timestamp)
	end

	out.DateTime = {
		now = function(): any
			return out.DateTime.fromUnixTimestamp(math.floor(os.time()))
		end,
		fromUnixTimestamp = function(seconds: any): any
			local t = tonumber(seconds) or 0
			local broken = os.date("!*t", t) :: any
			local millis = math.floor((t % 1) * 1000)
			local dt = {
				UnixTimestamp = math.floor(t),
				UnixTimestampMillis = math.floor(t * 1000),
				Year = broken.year,
				Month = broken.month,
				Day = broken.day,
				Hour = broken.hour,
				Minute = broken.min,
				Second = broken.sec,
				Millisecond = millis,
				IsCurrent = false,
			}
			dt.ToIsoDate = function(): string
				return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", broken.year, broken.month, broken.day, broken.hour, broken.min, broken.sec)
			end
			dt.ToUniversalTime = function(): any
				return {
					Year = broken.year,
					Month = broken.month,
					Day = broken.day,
					Hour = broken.hour,
					Minute = broken.min,
					Second = broken.sec,
					Millisecond = millis,
				}
			end
			dt.ToLocalTime = function(): any
				local localBroken = os.date("*t", t) :: any
				return {
					Year = localBroken.year,
					Month = localBroken.month,
					Day = localBroken.day,
					Hour = localBroken.hour,
					Minute = localBroken.min,
					Second = localBroken.sec,
					Millisecond = millis,
				}
			end

			local function formatWith(bt: any, fmt: any): string
				if type(fmt) ~= "string" then
					return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", bt.year, bt.month, bt.day, bt.hour, bt.min, bt.sec)
				end
				local repl = {
					yyyy = string.format("%04d", bt.year),
					YYYY = string.format("%04d", bt.year),
					yy = string.format("%02d", bt.year % 100),
					MM = string.format("%02d", bt.month),
					dd = string.format("%02d", bt.day),
					DD = string.format("%02d", bt.day),
					HH = string.format("%02d", bt.hour),
					hh = string.format("%02d", ((bt.hour - 1) % 12) + 1),
					mm = string.format("%02d", bt.min),
					ss = string.format("%02d", bt.sec),
				}

				local order = { "yyyy", "YYYY", "MM", "dd", "DD", "HH", "hh", "mm", "ss", "yy" }
				local result = fmt
				for _, tok in ipairs(order) do
					result = result:gsub(tok, repl[tok])
				end
				return result
			end
			dt.FormatUniversalTime = function(_self: any, fmt: any?, _locale: any?): any
				if type(_self) == "string" then
					return formatWith(broken, _self)
				end
				return formatWith(broken, fmt)
			end
			dt.FormatLocalTime = function(_self: any, fmt: any?, _locale: any?): any
				local lt = os.date("*t", t) :: any
				if type(_self) == "string" then
					return formatWith(lt, _self)
				end
				return formatWith(lt, fmt)
			end
			return Symbol.tag(dt, {
				kind = "datatype",
				expression = "DateTime.now()",
				typeName = "DateTime",
			})
		end,
		fromUnixTimestampMillis = function(millis: any): any
			return out.DateTime.fromUnixTimestamp((tonumber(millis) or 0) / 1000)
		end,
		fromIsoDate = function(iso: string): any
			local year, month, day, hour, minute, second = string.match(tostring(iso), "(%d%d%d%d)-(%d%d)-(%d%d)T?(%d*):?([%d]*):?([%d]*)")
			return datetimeFromTable({
				Year = tonumber(year) or 1970,
				Month = tonumber(month) or 1,
				Day = tonumber(day) or 1,
				Hour = tonumber(hour) or 0,
				Minute = tonumber(minute) or 0,
				Second = tonumber(second) or 0,
				Offset = 0,
			})
		end,
		fromLocalTime = function(t: any): any
			return datetimeFromTable(t or {})
		end,
		fromUniversalTime = function(t: any): any
			return datetimeFromTable(t or {})
		end,
	}

	local materialDefaults: { [string]: { number } } = {
		Plastic = { 0.7, 0.3, 0.5, 1, 1 },
		Wood = { 0.35, 0.48, 0.2, 1, 1 },
		Metal = { 7.85, 0.35, 0.15, 1, 1 },
		Rubber = { 1.5, 1.3, 0.8, 1, 1 },
		Ice = { 0.92, 0.02, 0.05, 1, 1 },
	}
	out.PhysicalProperties = {
		new = function(materialOrDensity: any, friction: any?, elasticity: any?, frictionWeight: any?, elasticityWeight: any?): any
			local density, fric, elas, fricW, elasW: number, number, number, number, number
			if type(materialOrDensity) == "number" then
				density = materialOrDensity
				fric = tonumber(friction) or 0.3
				elas = tonumber(elasticity) or 0.5
				fricW = tonumber(frictionWeight) or 1
				elasW = tonumber(elasticityWeight) or 1
			else
				local name = if type(materialOrDensity) == "table" and materialOrDensity.Name then tostring(materialOrDensity.Name) else "Plastic"
				local defaults = materialDefaults[name] or materialDefaults.Plastic
				density, fric, elas, fricW, elasW = defaults[1], defaults[2], defaults[3], defaults[4], defaults[5]
			end
			return Symbol.tag({
				Density = density,
				Friction = fric,
				Elasticity = elas,
				FrictionWeight = fricW,
				ElasticityWeight = elasW,
			}, {
				kind = "datatype",
				expression = "PhysicalProperties.new()",
				typeName = "PhysicalProperties",
			})
		end,
	}

	local function rejectUnknownFont(value: any, where: string)
		if EnumItem.isEnumItem(value) and value.Name == "Unknown" then
			error("Enum.Font.Unknown can't be passed to " .. where, 3)
		end
	end
	out.Font = {
		new = function(family: string?, weight: any?, style: any?): any
			return Symbol.tag({
				Family = family or "rbxasset://fonts/families/SourceSansPro.json",
				Weight = weight or 0,
				Style = style or 0,
			}, {
				kind = "datatype",
				expression = "Font.new()",
				typeName = "Font",
			})
		end,
		fromEnum = function(fontEnum: any): any
			rejectUnknownFont(fontEnum, "Font.fromEnum")
			local family = "SourceSansPro"
			if EnumItem.isEnumItem(fontEnum) then
				family = tostring(fontEnum.Name)
			end
			return Symbol.tag({
				Family = string.format("rbxasset://fonts/families/%s.json", family),
				Weight = 0,
				Style = 0,
			}, {
				kind = "datatype",
				expression = "Font.fromEnum(Enum.Font." .. family .. ")",
				typeName = "Font",
			})
		end,
	}

	out.__rejectUnknownFont = rejectUnknownFont

	out.PathWaypoint = {
		new = function(position: any?, action: any?, label: any?): any
			return Symbol.tag({
				Position = position or makeVector3(),
				Action = if type(action) == "table" and action.Name then action else EnumItem.new("Walk", 0),
				Label = tostring(label or ""),
			}, {
				kind = "datatype",
				expression = "PathWaypoint.new()",
				typeName = "PathWaypoint",
			})
		end,
	}

	return out
end

return Datatypes
