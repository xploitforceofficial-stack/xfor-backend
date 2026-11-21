local Datatypes = require("./datatypes")
local EnumItem = require("./enumitem")

local Workspace = {}

local function enum(name: string): any
	return EnumItem.new(name)
end

local built = false
local model: { [string]: any } = {}
local scalars: { [string]: any } = {}

local function ensure(): (any, any)
	if built then
		return model, scalars
	end
	built = true

	local d = Datatypes.build()
	local function vec(x: number, y: number, z: number): any
		return d.Vector3.new(x, y, z)
	end
	local function cframe(x: number?, y: number?, z: number?): any
		return d.CFrame.new(x or 0, y or 0, z or 0)
	end
	local function color(r: number, g: number, b: number): any
		return d.Color3.new(r, g, b)
	end
	local function v2(x: number, y: number): any
		return d.Vector2.new(x, y)
	end
	local function brick(name: string): any
		return d.BrickColor.new(name)
	end

	local function material(name: string, value: number): any
		return EnumItem.new(name, value)
	end

	model.Camera = {
		className = "Camera",
		properties = {
			CFrame = cframe(0, 50, 0),
			Focus = cframe(0, 0, 0),
			FieldOfView = 70,
			PerspectiveFieldOfView = 70,
			DiagonalFieldOfView = 70,
			MaxAxisFieldOfView = 70,

			FieldOfViewMode = EnumItem.new("Vertical", 0),

			CameraType = EnumItem.new("Custom"),
			CameraSubject = nil,
			ViewportSize = v2(1280, 720),
			NearPlaneZ = 0.1,
			FarPlaneZ = 1000,
			HeadLocked = false,
			Archivable = true,
		},
	}

	model.Part = {
		className = "Part",
		properties = {
			CFrame = cframe(0, 0, 0),
			Position = vec(0, 0, 0),
			Size = vec(4, 1.2, 4),
			Orientation = vec(0, 0, 0),
			RotVelocity = vec(0, 0, 0),
			Velocity = vec(0, 0, 0),
			AssemblyLinearVelocity = vec(0, 0, 0),
			AssemblyAngularVelocity = vec(0, 0, 0),
			Anchored = true,

			AssemblyMass = math.huge,
			CanCollide = true,
			CanTouch = true,
			CanQuery = true,
			Transparency = 0,
			Reflectance = 0,

			Material = material("Plastic", 256),
			Color = color(0.639, 0.635, 0.647),
			BrickColor = brick("Medium stone grey"),
			Mass = 0,
			Archivable = true,
		},
	}

	model.Terrain = {
		className = "Terrain",
		properties = {
			WaterColor = color(0.082, 0.322, 0.549),
			WaterTransparency = 0.5,
			WaterWaveSize = 0,
			WaterWaveSpeed = 10,
			MaterialColors = {},
			CellSize = vec(4, 4, 4),
			Size = vec(1024, 1024, 1024),
			CanCollide = true,
			Anchored = true,
			AssemblyMass = math.huge,
			Archivable = true,
		},
	}

	model.Baseplate = {
		className = "Part",
		properties = {
			CFrame = cframe(0, -10, 0),
			Position = vec(0, -10, 0),
			Size = vec(512, 20, 512),
			Anchored = true,
			AssemblyMass = math.huge,
			Material = material("Concrete", 816),
			Color = color(0.4, 0.4, 0.4),
			BrickColor = brick("Dark stone grey"),
		},
	}

	model.SpawnLocation = {
		className = "SpawnLocation",
		properties = {
			CFrame = cframe(0, 0, 0),
			Position = vec(0, 0, 0),
			Size = vec(16, 1, 16),
			Anchored = true,
			AssemblyMass = math.huge,
			CanCollide = true,
			Material = material("Concrete", 816),
			Color = color(0.306, 0.659, 1),
			BrickColor = brick("Bright blue"),
			Neutral = false,
			Duration = 5,
			Enabled = true,
			Archivable = true,
		},
	}

	model.Folder = { className = "Folder", properties = { Archivable = true } }
	model.Model = { className = "Model", properties = { Archivable = true } }
	model.Debris = { className = "Folder", properties = { Archivable = true } }

	scalars.Gravity = 196.2
	scalars.DistributedGameTime = 0
	scalars.StreamingEnabled = false
	scalars.FallenPartsDestroyHeight = -500
	scalars.Ambient = color(0.5, 0.5, 0.5)
	scalars.Brightness = 1
	scalars.GlobalWind = vec(0, 0, 0)
	scalars.AirDensity = 1.2
	scalars.FloodHeight = 0
	scalars.InsertPoint = vec(0, 0, 0)
	scalars.AllowThirdPartySales = false
	scalars.FallHeightEnabled = false
	scalars.ClientAnimatorThrottling = enum("Default")
	scalars.AuthorityMode = enum("Automatic")
	scalars.LuauTypeCheckMode = enum("Default")

	return model, scalars
end

function Workspace.child(name: string): any?
	ensure()
	return model[name]
end

function Workspace.children(): { [string]: any }
	ensure()
	return model
end

function Workspace.scalar(name: string): any?
	ensure()
	return scalars[name]
end

return Workspace
