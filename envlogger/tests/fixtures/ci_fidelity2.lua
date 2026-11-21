local p = Instance.new("Part")
print(p.ClassName)
print(p.classname)
print(p.NAME)
print(p.name)
p.Name = "MyPart"
print(p.name)
print(p.NAME)
print(p.parent)
local f = Instance.new("Folder")
f.parent = p
print(f.parent.Name)
print(f.PARENT.Name)
