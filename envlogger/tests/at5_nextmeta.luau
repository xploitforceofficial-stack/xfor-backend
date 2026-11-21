local Spy = require("../src/core/spy")

local realNext = next
local function sandboxNext(subject: any, control: any): any
	local subj = Spy.unwrap(subject)
	if type(subj) == "userdata" and Spy.is(subject) then
		return nil
	end
	if type(subj) == "table" then

	end
	return realNext(subj, control)
end

local t1 = { a = 1 }
print("plain:", sandboxNext(t1, nil))

local spyVal = Spy.new("workspace", {}, nil, false, 0)
local t2 = { x = spyVal }
print("spy-in-table subj type:", type(t2))
local unwrapped = Spy.unwrap(t2)
print("unwrapped == t2:", unwrapped == t2, type(unwrapped))
print("spy-in-table:", sandboxNext(t2, nil))

local spyTable = Spy.new("t", {}, { a = 9 }, true, 0)
local u3 = Spy.unwrap(spyTable)
print("unwrap(spyTable):", type(u3), u3 and u3.a)
print("spy-of-table next:", sandboxNext(spyTable, nil))
