local function check(id, fn, expected)
	local ok, err = pcall(fn)
	err = tostring(err)

	if ok then
		print("dtc", id)
	elseif expected and err:find(expected, 1, true) then
		print("ud", id)
	else
		print("ud", id)
	end
end

check(3, function()
	Color3.toHSV("x")
end, "Color3.toHSV requires a Color3 argument")

check(4, function()
	Color3.fromHSV()
end, "Color3.fromHSV requires three arguments")

check(5, function()
	Color3.fromHex()
end, "Color3.fromHex requires one argument")

check(6, function()
	InstanceHandle.new()
end, "InstanceHandle.new requires an Instance argument")

check(8, function()
	Random.new():NextNumber(1)
end, "Random:NextNumber requires 0 or 2 arguments")

check(9, function()
	task.spawn()
end, "invalid argument #1 to 'spawn' (function or thread expected)")

check(10, function()
	task.delay()
end, "invalid argument #2 to 'delay' (function or thread expected)")

check(11, function()
	game:GetService("TextService"):GetTextSize("test", 16, Enum.Font.Unknown, Vector2.new(100, 100))
end, "Enum.Font.Unknown can't be passed to TextService:GetTextSize()")

check(12, function()
	Font.fromEnum(Enum.Font.Unknown)
end, "Enum.Font.Unknown can't be passed to Font.fromEnum")

check(13, function()
	game:GetService("GeometryService"):GenerateFragmentSites()
end, "GeometryService:GenerateFragmentSites")

check(14, function()
	game:GetService("GeometryService"):FragmentAsync()
end, "GeometryService:FragmentAsync")

check(15, function()
	game:GetService("GeometryService"):SweepPartAsync()
end, "GeometryService:SweepPartAsync")

check(16, function()
	game:GetService("DataStoreService"):GetDataStore("")
end, "DataStore name can't be empty string")

check(17, function()
	game:GetService("DataStoreService"):GetDataStore("test", "")
end, "DataStore scope can't be empty string")

check(18, function()
	game:GetService("DataStoreService"):GetDataStore("test")
end, "DataStore can't be accessed from client")
