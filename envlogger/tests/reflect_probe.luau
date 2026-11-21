local roblox = require("@lune/roblox")

local ok, db = pcall(roblox.getReflectionDatabase)
if not ok then
	print("reflection db unavailable:", tostring(db))
	return
end
print("type:", typeof(db))
local counts = {}
for k, v in pairs(db) do
	counts[k] = typeof(v) == "table" and #v or 0
end
local keys = {}
for k in pairs(db) do
	table.insert(keys, k)
end
table.sort(keys)
for _, k in ipairs(keys) do
	print(string.format("db.%-16s len=%d", k, counts[k]))
end

local classes = db.Classes or {}
print("first class:", classes[1] and classes[1].Name)
local function findByName(list, name)
	for _, e in ipairs(list) do
		if e.Name == name then
			return e
		end
	end
	return nil
end
local path2d = findByName(classes, "Path2D")
print("Path2D entry:", path2d ~= nil)
if path2d then
	print("  tags:", tostring(path2d.Tags))
	print("  superclass:", tostring(path2d.Superclass))
	print("  members:", path2d.Members and #path2d.Members or 0)
end
local enums = db.Enums or {}
print("enums:", #enums)
local es = findByName(enums, "EasingStyle")
print("EasingStyle items:", es and es.Items and #es.Items or 0)

local dt = db.DataTypes or {}
print("datatypes:", #dt)
local rd = findByName(dt, "Random")
print("Random datatype:", rd ~= nil, rd and rd.Members and #rd.Members or 0)
