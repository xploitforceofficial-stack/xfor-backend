local Symbol = require("../core/symbol")

local EnumItem = {}

local registry: { [string]: any } = {}

local created: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local meta: any

function EnumItem.new(name: string, value: number?, enumType: any?): any

	local typeKey = if type(enumType) == "table" then tostring(enumType) else "-"
	local key = tostring(name) .. "\0" .. tostring(value or 0) .. "\0" .. typeKey
	local existing = registry[key]
	if existing then
		return existing
	end
	local item = setmetatable({
		Name = name,
		Value = value or 0,
		EnumType = enumType,
	}, meta)

	Symbol.tag(item, {
		kind = "datatype",
		expression = "EnumItem.new(" .. tostring(name) .. ")",
		typeName = "EnumItem",
	})
	registry[key] = item
	created[item] = true
	return item
end

function EnumItem.isEnumItem(value: any): boolean
	return type(value) == "table" and created[value] == true
end

local Fidelity = require("./fidelity")
local Symbol = require("../core/symbol")

local isA = function(self: any, enum: any): boolean
	if self == nil then
		error("missing argument #1 to 'IsA' (EnumItem expected)", 2)
	end
	if enum == nil then
		error("missing argument #2 to 'IsA' (Enum expected)", 2)
	end
	return self.EnumType == enum
end
Fidelity.register(isA, "IsA")

meta = {
	__index = function(_self: any, key: any): any
		if key == "IsA" then
			return isA
		end
		return nil
	end,
	__tostring = function(self)

		local sym = Symbol.get(self)
		if sym ~= nil and type(sym.expression) == "string" and sym.expression ~= "" then
			return sym.expression
		end
		local category = self.EnumType
		if category ~= nil then
			local categorySym = Symbol.get(category)
			local categoryName = categorySym and categorySym.expression or nil
			if type(categoryName) == "string" and categoryName ~= "" then
				return categoryName .. "." .. tostring(self.Name)
			end
		end
		return tostring(self.Name)
	end,
	__eq = function(left, right)

		return type(left) == "table" and type(right) == "table"
			and left.Name == right.Name
	end,

	__newindex = function(_: any, key: any): never
		error("Unable to assign property '" .. tostring(key) .. "'. Property is read only", 2)
	end,
	__metatable = "The metatable is locked",
}

return EnumItem
