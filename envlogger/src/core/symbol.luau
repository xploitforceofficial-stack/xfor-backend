export type Kind = "spy" | "instance" | "datatype" | "closure" | "service"

export type Descriptor = {
	kind: Kind,

	expression: string,

	typeName: string?,

	detail: { [string]: any }?,
}

local Symbol = {}

local registry: { [any]: Descriptor } = setmetatable({}, { __mode = "k" }) :: any

function Symbol.tag<T>(object: T, descriptor: Descriptor): T
	registry[object :: any] = descriptor
	return object
end

function Symbol.get(object: any): Descriptor?
	if object == nil then
		return nil
	end
	return registry[object]
end

function Symbol.expression(object: any): string?
	local descriptor = registry[object]
	return descriptor and descriptor.expression
end

function Symbol.isKind(object: any, kind: Kind): boolean
	local descriptor = registry[object]
	return descriptor ~= nil and descriptor.kind == kind
end

function Symbol.typeName(object: any): string
	local descriptor = registry[object]
	if descriptor and descriptor.typeName then
		return descriptor.typeName
	end
	return type(object)
end

return Symbol
