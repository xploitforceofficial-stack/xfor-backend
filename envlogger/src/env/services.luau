local Services = {}

local ClassData = require("./classdata")
local Spy = require("../core/spy")

local Zlib: any = nil
do
	local ok, loaded = pcall(require, "../zlib")
	if ok and type(loaded) == "table" and loaded.compressZlib ~= nil then
		Zlib = loaded
	end
end

local Zstd = nil
do
	local ok, mod = pcall(require, "./zstd")
	if ok and type(mod) == "table" and type(mod.decompress) == "function" then
		Zstd = mod
	end
end

local ZstdService = {}
local ZSTD_FAIL_COUNT = 0

local HOST_CACHE: { [string]: string } = {}

local function hostCacheKey(text: string): string
	local function part(from: number, len: number): string
		local n = 0
		local h = 5381
		for i = from, from + len - 1 do
			local b = text:byte(i)
			if b then
				h = (h * 33 + b) % 4294967296
				n += 1
			end
		end
		return tostring(h) .. ":" .. tostring(n)
	end
	return #text .. ":" .. part(1, 64) .. ":" .. part(math.max(1, #text - 63), 64)
end

local function hostZstd(text: string): string?
	local key = hostCacheKey(text)
	local hit = HOST_CACHE[key]
	if hit then
		return hit
	end
	local okProc, proc = pcall(require, "@lune/process")
	if not okProc or type(proc) ~= "table" then
		return nil
	end
	local okFs, fsx = pcall(require, "@lune/fs")
	if not okFs then
		return nil
	end

	local base = string.gsub(proc.cwd or ".", "\\", "/")
	base = string.gsub(base, "/+$", "")
	local dir = base .. "/.zstd_scratch"

	local made = (type(fsx.mkdir) == "function" and pcall(fsx.mkdir, dir))
		or (type(fsx.writeDir) == "function" and pcall(fsx.writeDir, dir))
	if not made and not fsx.isDir(dir) then
		return nil
	end
	local inPath = dir .. "/in.bin"
	local outPath = dir .. "/out.bin"
	pcall(fsx.removeFile, outPath)
	if not (pcall(fsx.writeFile, inPath, text)) then
		return nil
	end
	local script = base .. "/zstd_host.py"
	local okRun, res = pcall(proc.exec, "python", { script, inPath, outPath })
	if not okRun or type(res) ~= "table" or res.code ~= 0 then
		pcall(fsx.removeFile, inPath)
		return nil
	end
	local okRead, out = pcall(fsx.readFile, outPath)
	pcall(fsx.removeFile, inPath)
	pcall(fsx.removeFile, outPath)
	if not okRead or type(out) ~= "string" then
		return nil
	end
	HOST_CACHE[key] = out
	return out
end
function ZstdService.compressString(_self: any, raw: string): string
	if Zlib then
		local ok, packed = pcall(Zlib.compressZlib, raw)
		if ok then
			return "\2z" .. packed
		end
	end
	return "\2z" .. string.reverse(raw)
end
function ZstdService.decompressString(_self: any, text: string): string
	if string.sub(text, 1, 2) == "\2z" then
		local payload = string.sub(text, 3)
		if Zlib then
			local ok, unpacked = pcall(Zlib.decompressZlib, payload)
			if ok then
				return unpacked
			end
		end
		return string.reverse(payload)
	end

	if Zstd and Zstd.isFrame(text) then
		local ok, unpacked = pcall(Zstd.decompress, text)
		if ok and type(unpacked) == "string" then
			return unpacked
		end

		local viaHost = hostZstd(text)
		if viaHost then
			return viaHost
		end
		if not ok then

			local procOk, proc = pcall(require, "@lune/process")
			local dumpDir = procOk and proc.env["ZSTD_FAIL_DIR"] or nil
			local where = ""
			if type(dumpDir) == "string" and #dumpDir > 0 then
				ZSTD_FAIL_COUNT += 1
				local path = dumpDir .. "/fail_" .. tostring(ZSTD_FAIL_COUNT) .. ".bin"
				local saved = pcall(function()
					local fs = require("@lune/fs")
					fs.mkdir(dumpDir)
					fs.writeFile(path, text)
				end)
				if saved then
					where = " -> " .. path
				end
			end
			error("invalid zstd input: " .. tostring(unpacked) .. " (frame " .. #text
				.. " bytes" .. where .. ")", 2)
		end
		error("invalid zstd input: decoder produced no data", 2)
	end
	error("invalid zstd input: not a zstd frame", 2)
end
function ZstdService.compressed(_self: any, data: any): string
	return ZstdService.compressString(_self, tostring(Spy.unwrap(data) or ""))
end
function ZstdService.decompressed(_self: any, data: any): string
	return ZstdService.decompressString(_self, tostring(Spy.unwrap(data) or ""))
end

Services.NAMES = {
	"AnalyticsService",
	"AssetCounterService",
	"AssetService",
	"AudioService",
	"AvatarEditorService",
	"BadgeService",
	"BrowserService",
	"CacheService",
	"Chat",
	"ChatbotUIService",
	"CloudInputService",
	"CollectionService",
	"CommerceService",
	"ContentProvider",
	"ContextActionService",
	"CookiesService",
	"CoreGui",
	"CustomEventService",
	"DataModelPatchService",
	"DataStoreService",
	"Debris",
	"DeviceIdService",
	"ExperienceNotificationService",
	"FaceAnimatorService",
	"FriendService",
	"FriendsService",
	"GamePassService",
	"GamepadService",
	"GroupService",
	"GuiService",
	"GuidRegistryService",
	"HapticService",
	"HttpRbxApiService",
	"HttpService",
	"InGamepadService",
	"InsertService",
	"KeyframeSequenceProvider",
	"KeyboardService",
	"LicensedGameService",
	"Lighting",
	"LinkService",
	"LocalizationService",
	"LogService",
	"LodDataService",
	"LuaChatService",
	"LuaWebService",
	"MarketplaceService",
	"MaterialService",
	"MemoryStoreService",
	"MessagingService",
	"NetworkClient",
	"NetworkServer",
	"NetworkSettings",
	"NotificationService",
	"OmniRecommendationsService",
	"PathfindingService",
	"PhysicsService",
	"Players",
	"PolicyService",
	"ProximityPromptService",
	"PublishService",
	"RbxAnalyticsService",
	"RbxSensorService",
	"RejectService",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"RobloxReplicatedStorage",
	"RunService",
	"ScriptContext",
	"ScriptService",
	"SecurityService",
	"Selection",
	"ServerScriptService",
	"ServerStorage",
	"SharedTableRegistry",
	"SmashService",
	"SocialService",
	"SoundService",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"Stats",
	"StatsService",
	"StreamingService",
	"StudioData",
	"StudioService",
	"Teams",
	"TeleportService",
	"TestService",
	"TextChatService",
	"TextService",
	"ToastNotificationService",
	"TracerService",
	"TweenService",
	"UGCValidationService",
	"UserInputService",
	"UserService",
	"VRService",
	"VirtualInputManager",
	"VirtualUser",
	"VoiceChatService",
	"WebService",
	"Workspace",

	"ABTestService",
	"AccountService",
	"AchievementService",
	"ActivityHistoryEventService",
	"AdService",
	"AntiAddictionService",
	"AnimationClipProvider",
	"AnnotationsService",
	"AppAgeSignalsService",
	"AppLifecycleObserverService",
	"AppRatingPromptService",
	"AppUpdateService",
	"AssetImportService",
	"AssetManagerService",
	"AssetQualityService",
	"AudioFocusService",
	"AuroraService",
	"AvatarChatService",
	"AvatarCreationService",
	"AvatarImportService",
	"BugReporterService",
	"BulkImportService",
	"CalloutService",
	"CaptureService",
	"ChatService",
	"ClientStorageService",
	"CollisionService",
	"CloudCRUDService",
	"CloudExecutionService",
	"CollaboratorsService",
	"ConfigService",
	"ConfigureServerService",
	"ConnectivityService",
	"CreationDBService",
	"CreatorStoreService",
	"DeferredAssetManagerService",
	"DesignFoundationsService",
	"DraftsService",
	"EditableService",
	"EncodingService",
	"EventIngestService",
	"ExampleV2Service",
	"ExperienceAuthService",
	"ExperienceService",
	"ExperienceStateCaptureService",
	"FacialAgeEstimationService",
	"FileManagerService",
	"FlagStandService",
	"FlyweightService",
	"GenerationService",
	"GenericChallengeService",
	"GeometryService",
	"GongService",
	"HarmonyService",
	"HeatmapService",
	"IXPService",
	"ImageScreenCaptureService",
	"InstanceExtensionsService",
	"InternalMessagingService",
	"JointsService",
	"LanguageService",
	"LinkingService",
	"LiveScriptingService",
	"LocalStorageService",
	"LoginService",
	"MLModelDeliveryService",
	"MLService",
	"MaterialGenerationService",
	"MatchmakingService",
	"MemStorageService",
	"MessageBusService",
	"ModerationService",
	"MouseService",
	"OpenCloudService",
	"PackageService",
	"PerformanceControlService",
	"PermissionsService",
	"PlaceAssetIdsService",
	"PlaceStatsService",
	"PlacesService",
	"PlatformCloudStorageService",
	"PlatformFriendsService",
	"PlayerDataService",
	"PlayerEmulatorService",
	"PlayerHydrationService",
	"PlayerViewService",
	"PointsService",
	"RecommendationService",
	"ReflectionService",
	"RobloxServerStorage",
	"RuntimeContentService",
	"RuntimeScriptService",
	"SafetyService",
	"SerializationService",
	"SessionService",
	"SpawnerService",
	"StarterGear",
	"StartupMessageService",
	"StylingService",
	"SystemThemeService",
	"TelemetryService",
	"TextBoxService",
	"ThirdPartyUserService",
	"TimerService",
	"TouchInputService",
	"TutorialService",
	"UGCAvatarService",
	"UniqueIdLookupService",
	"UnvalidatedAssetService",
	"VRStatusService",
	"VideoService",
	"WebSocketService",
	"WebViewService",
}

local byName: { [string]: boolean } = {}
for _, name in ipairs(Services.NAMES) do
	byName[name] = true
end

function Services.isService(name: any): boolean
	if type(name) ~= "string" then
		return false
	end
	return byName[name] == true or ClassData.isService(name)
end

local INSTANCE_CLASSES: { [string]: boolean } = {
	ForceField = true, NoCollisionConstraint = true, BloomEffect = true,
	ColorCorrectionEffect = true, SunRaysEffect = true, BlurEffect = true,
	Atmosphere = true, Clouds = true, Light = true,
	Sky = true, Stars = true,
	Part = true, WedgePart = true, TrussPart = true, CornerWedgePart = true,
	VehicleSeat = true, Seat = true, SpawnLocation = true,
	MeshPart = true, SpecialMesh = true, BlockMesh = true, CylinderMesh = true,
	FileMesh = true, EditableMesh = true,

	UnionOperation = true, NegateOperation = true, IntersectOperation = true,
	PartOperation = true,
	Decal = true, Texture = true, SurfaceAppearance = true,
	Model = true, WorldModel = true, Tool = true, Hopper = true,
	Accessory = true, Shirt = true, Pants = true, ShirtGraphic = true,
	BodyColors = true, CharacterMesh = true,
	Hat = true,
	Folder = true, Configuration = true, OptionalCoordinateFrameValue = true,
	Attachment = true,
	Humanoid = true, HumanoidDescription = true,
	Animator = true, AnimationController = true, AnimationTrack = true,
	AlignPosition = true, AlignOrientation = true, AlignPosition0 = true,
	LinearVelocity = true, AngularVelocity = true, VectorForce = true,
	Torque = true, LineForce = true,
	HingeConstraint = true, BallSocketConstraint = true, PrismaticConstraint = true,
	CylindricalConstraint = true, SpringConstraint = true, RodConstraint = true,
	RopeConstraint = true, SliderSlotConstraint = true,
	Joint = true, Weld = true, ManualWeld = true, Snap = true, Glue = true,
	Motor6D = true, Motor = true, Rotate = true, RotateP = true, RotateV = true,
	BodyPosition = true, BodyGyro = true, BodyVelocity = true, BodyAngularVelocity = true,
	BodyForce = true, BodyThrust = true,
	RocketPropulsion = true,
	ParticleEmitter = true, Fire = true, Smoke = true, Sparkles = true,
	Trail = true, Beam = true, Explosion = true,
	PointLight = true, SpotLight = true, SurfaceLight = true,
	Sound = true, SoundGroup = true, SoundServiceChild = true,
	RemoteEvent = true, RemoteFunction = true,
	BindableEvent = true, BindableFunction = true,
	UnreliableRemoteEvent = true,
	ScreenGui = true, SurfaceGui = true, BillboardGui = true,
	Frame = true, ScrollingFrame = true, CanvasGroup = true,
	TextLabel = true, TextButton = true, TextBox = true,
	ImageLabel = true, ImageButton = true,
	VideoFrame = true, ViewportFrame = true,
	UIListLayout = true, UIGridLayout = true, UITableLayout = true, UIPageLayout = true,
	UICorner = true, UIStroke = true, UIPadding = true, UIScale = true,
	UIGradient = true, UIAspectRatioConstraint = true,
	UISizeConstraint = true, UIRatioLayout = true,
	UITextSizeConstraint = true, UIFlexItem = true,
	ScrollingUIFrame = true,
	IntValue = true, NumberValue = true, StringValue = true, BoolValue = true,
	ObjectValue = true, CFrameValue = true, Vector3Value = true,
	Vector2Value = true, Color3Value = true, BrickColorValue = true,
	RayValue = true, Folder2 = true,
	Script = true, LocalScript = true, ModuleScript = true,
	SpotLightBulb = true,
	SelectionBox = true, SphereHandleAdornment = true, LineHandleAdornment = true,
	BoxHandleAdornment = true, CylinderHandleAdornment = true, ImageHandleAdornment = true,
	Handles = true, ArcHandles = true,
	Notification = true,
	Player = true, Players = true,
	Team = true, Terrain = true, TerrainRegion = true,
	Status = true, Message = true, Hint = true,
	DoubleConstrainedValue = true, IntConstrainedValue = true,
	GameSettings = true,
	Path = true, PathfindingLink = true, PathWaypoint = true,
	PromptService2 = true,
	Highlight = true,
	DragDetector = true,
}

function Services.isKnownClassName(name: any): boolean
	if type(name) ~= "string" then
		return false
	end
	return byName[name] == true or INSTANCE_CLASSES[name] == true or ClassData.isKnown(name)
end

local Datatypes = require("./datatypes")
local EnumItem = require("./enumitem")
local Signal = require("./signal")

local Spy = require("../core/spy")

local d = Datatypes.build()

local function enum(name: string): any
	return EnumItem.new(name)
end
local function color(r: number, g: number, b: number): any
	return d.Color3.new(r, g, b)
end
local function v2(x: number, y: number): any
	return d.Vector2.new(x, y)
end

local function requireArgs(member: string, needed: number, got: number): ()
	if got < needed then
		error(string.format(
			"%s expects %d arguments, got %d",
			member,
			needed,
			got
		), 3)
	end
end

local function memoryStore(): any
	return {
		GetAsync = function(): any
			return nil
		end,
		UpdateAsync = function(): any
			return nil
		end,
		SetAsync = function(): boolean
			return true
		end,
		IncrementAsync = function(): number
			return 1
		end,
		ReadAsync = function(): any
			return nil
		end,
	}
end

local function emptySet(): { any }
	return {}
end

local MEMBERS: { [string]: { props: { [string]: any }, methods: { [string]: any } } } = {
	AnimationClipProvider = {
		methods = {
			GetAnimationClipAsync = function(): any
				return nil
			end,
			GetAnimationClipsFromAvatarAsync = emptySet,

			GetMemStats = function(): { [string]: number }
				return {
					AnimationClipCache = 0,
					AnimationTrackCache = 0,
					KeyframeSequenceCache = 0,
					PendingRequests = 0,
				}
			end,
		},
	},
	GeometryService = {
		methods = {
			GetObbForPartAsync = function(): any
				return nil
			end,
			GetEdgesForPartAsync = emptySet,
			GetMeshEdgesForPartAsync = emptySet,

			GenerateFragmentSites = function(_self: any, ...: any): { any }
				requireArgs("GeometryService:GenerateFragmentSites", 3, select("#", ...))
				return {}
			end,
			FragmentAsync = function(_self: any, ...: any): { any }
				requireArgs("GeometryService:FragmentAsync", 2, select("#", ...))
				return {}
			end,
			SweepPartAsync = function(_self: any, ...: any): { any }
				requireArgs("GeometryService:SweepPartAsync", 3, select("#", ...))
				return {}
			end,
			IntersectAsync = function(_self: any, ...: any): any
				requireArgs("GeometryService:IntersectAsync", 2, select("#", ...))
				return nil
			end,
			UnionAsync = function(_self: any, ...: any): any
				requireArgs("GeometryService:UnionAsync", 2, select("#", ...))
				return nil
			end,
			SubtractAsync = function(_self: any, ...: any): any
				requireArgs("GeometryService:SubtractAsync", 2, select("#", ...))
				return nil
			end,
		},
	},
	JointsService = {
		methods = {
			MakeJoints = function(): any
				return nil
			end,
			RemoveJoints = function() end,
			ClearJoints = function() end,
		},
	},
	MatchmakingService = {
		methods = {
			SubmitAsync = function(): any
				return nil
			end,
			GetMatchmakingResult = function(): any
				return nil
			end,
			SendHeartbeat = function(): any
				return nil
			end,
		},
	},
	MouseService = {
		methods = {
			GetMousePosition = function(): any
				return v2(0, 0)
			end,
			GetMouseDelta = function(): any
				return v2(0, 0)
			end,
			SetMousePosition = function() end,
		},
	},
	OpenCloudService = {
		methods = {
			CreateOpenCloudAuthenticatedRequest = function(): any
				return nil
			end,
		},
	},
	PlacesService = {
		methods = {
			GetPlaceInfoAsync = function(): any
				return {}
			end,
			GetUniverseId = function(): number
				return 0
			end,
			GetPlaceByIdAsync = function(): any
				return nil
			end,
		},
	},
	PlatformFriendsService = {
		methods = {
			GetFriendsAsync = emptySet,
		},
	},
	SerializationService = {
		methods = {
			SerializeInstance = function(): string
				return ""
			end,
			DeserializeInstance = function(): any
				return nil
			end,
			SerializeJoints = function(): string
				return ""
			end,
			DeserializeJoints = function() end,
		},
	},
	SystemThemeService = {
		methods = {
			GetAvailableThemes = emptySet,
			GetCurrentTheme = function(): any
				return nil
			end,
		},
	},
	UniqueIdLookupService = {
		methods = {
			GetFromAssetID = function(): any
				return nil
			end,
			GetFromUserId = function(): any
				return nil
			end,
		},
	},
	WebSocketService = {},
	WebViewService = {},
	ABTestService = {},
	AnalyticsService = {},
	AntiAddictionService = {},
	AssetCounterService = {},
	AssetService = {
		props = { AllowInsertFreeAssets = true },
		methods = {
			GetAssetIdsForPackage = emptySet,
			GetLocalAssetInfoFor = function() return nil end,
			GetAssetBundleContents = function() return nil end,

			CreateEditableMesh = function(): any
				local vertices: { any } = {}
				local mesh = {
					AddVertex = function(_self: any, position: any): number
						local id = #vertices + 1
						vertices[id] = position
						return id
					end,
					GetPosition = function(_self: any, vertexId: number): any
						return vertices[vertexId]
					end,
					Destroy = function() end,
				}
				return mesh
			end,
		},
	},
	AudioService = {
		props = { PlayInBackground = false },
		methods = {
			PauseAll = function() end,
			ResumeAll = function() end,
			SetListener = function() end,
		},
	},
	AvatarEditorService = {},
	BadgeService = {
		methods = {
			UserHasBadgeAsync = function(): boolean
				return false
			end,
			AwardBadge = function(): boolean
				return false
			end,
			TakeBadgeAsync = function(): boolean
				return false
			end,
			GetBadgeInfoAsync = function(): any
				return nil
			end,
		},
	},
	BrowserService = {},
	CaptureService = {
		methods = {
			CaptureSignal = function() end,
			ReleaseCapture = function() end,
		},
	},
	CacheService = {
		methods = {
			GetCache = function(): any
				return nil
			end,
			StartSession = function() end,
			StopSession = function() end,
			GetExpiration = function(): any
				return nil
			end,
			SetExpiration = function() end,
		},
	},
	Chat = {
		methods = {
			Chat = function(): boolean
				return true
			end,
			LoadDefaultSystemChat = function(): any
				return nil
			end,
		},
	},
	ChatbotUIService = {},
	ChatService = {
		methods = {
			GetChannel = function(): any
				return nil
			end,
			GetSpeaker = function(): any
				return nil
			end,
			GetAllChannelNames = emptySet,
		},
	},
	ClientStorageService = {},
	CloudInputService = {},
	CollisionService = {
		methods = {
			RegisterColliders = function() end,
			UnregisterColliders = function() end,
		},
	},
	CollectionService = {
		methods = {
			GetTagged = emptySet,
			GetTags = emptySet,
			HasTag = function(): boolean
				return false
			end,
			AddTag = function() end,
			RemoveTag = function() end,
		},
	},
	CommerceService = {},
	EncodingService = {
		methods = {

			Compress = function(_self: any, data: any): string
				local text = tostring(Spy.unwrap(data) or "")
				return "\1z" .. string.reverse(text)
			end,
			Decompress = function(_self: any, data: any): string
				local text = tostring(Spy.unwrap(data) or "")
				if string.sub(text, 1, 2) == "\1z" then
					return string.reverse(string.sub(text, 3))
				end
				return text
			end,

			CompressZstd = function(_self: any, data: any): string
				local raw = tostring(Spy.unwrap(data) or "")
				local ok, result = pcall(function()
					return "\2z" .. Zlib.compressZlib(raw)
				end)
				if not ok then
					return "\2z" .. string.reverse(raw)
				end
				return result
			end,
			DecompressZstd = function(_self: any, data: any): string
				local text = tostring(Spy.unwrap(data) or "")
				if string.sub(text, 1, 2) ~= "\2z" then
					error("invalid zstd input", 2)
				end
				local payload = string.sub(text, 3)
				local ok, result = pcall(function()
					return Zlib.decompressZlib(payload)
				end)
				if ok then
					return result
				end
				return string.reverse(payload)
			end,
			ZstdCompress = function(_self: any, data: any): any
				return ZstdService.compressed(_self, data)
			end,
			ZstdDecompress = function(_self: any, data: any): any
				return ZstdService.decompressed(_self, data)
			end,
			CompressBuffer = function(_self: any, buf: any, _algorithm: any): any
				local raw = buffer.tostring(Spy.unwrap(buf) or buf)
				local packed = ZstdService.compressString(_self, raw)
				return buffer.fromstring(packed)
			end,
			DecompressBuffer = function(_self: any, buf: any, _algorithm: any): any
				local raw = buffer.tostring(Spy.unwrap(buf) or buf)
				local unpacked = ZstdService.decompressString(_self, raw)
				return buffer.fromstring(unpacked)
			end,
		},
	},
	ContentProvider = {
		props = {

			BaseUrl = "http://www.roblox.com",
			RequestQueueSize = 5,
		},
		methods = {
			PreloadAsync = function() end,
			GetAssetUrl = function(): string
				return "https://www.roblox.com/asset/?id=1"
			end,
			GetIconUrl = function(): string
				return "https://www.roblox.com/asset/?id=1"
			end,
			GetRobloxAssetUrl = function(): string
				return "https://www.roblox.com/asset/?id=1"
			end,
		},
	},
	ContextActionService = {
		methods = {
			BindAction = function() end,
			UnbindAction = function() end,
			BindActivate = function() end,
			BindConstants = function() end,
			GetButton = function(): any
				return nil
			end,
			IsBound = function(): boolean
				return false
			end,
		},
	},
	CookiesService = {},
	CoreGui = {
		props = { Version = 8 },
		methods = {
			GetTheme = function(): any
				return nil
			end,
			GetCoreGuiType = function(): any
				return nil
			end,
		},
	},
	CustomEventService = {},
	DataModelPatchService = {},
	Debris = {
		props = { MaxItems = 200 },
		methods = {
			AddItem = function() end,
		},
	},
	DeviceIdService = {
		methods = {
			GetDeviceId = function(): string
				return "00000000-0000-0000-0000-000000000000"
			end,
		},
	},
	ExperienceNotificationService = {},
	FaceAnimatorService = {},
	FriendService = {
		methods = {
			GetFriendsOnline = emptySet,
		},
	},
	FriendsService = {
		methods = {
			GetFriendsAsync = emptySet,
			GetFriends = emptySet,
		},
	},
	GamePassService = {},
	GamepadService = {
		props = { GamepadCursorEnabled = true },
	},
	GroupService = {
		methods = {
			GetGroupInfoAsync = function(): any
				return { Id = 1, Name = "Group", MemberCount = 1, Owner = { Id = 1, Name = "Roblox" } }
			end,
			GetGroupsAsync = emptySet,
			GetPrimaryGroupInfoAsync = function(): any
				return nil
			end,
			GetRoleInGroup = function(): number
				return 0
			end,
			GetAlliesAsync = emptySet,
			GetEnemiesAsync = emptySet,
		},
	},
	GuiService = {
		props = { SelectedObject = nil, AutoSelectGuiEnabled = true, MenuIsOpen = false },
		methods = {
			GetGuiObjectsAtPosition = emptySet,

			GetGuiInset = function(): (any, any)
				return v2(0, 36), v2(0, 0)
			end,
			IsModalDialog = function(): boolean
				return false
			end,
			IsTenFootInterface = function(): boolean
				return false
			end,
			IsWindowsPhone = function(): boolean
				return false
			end,
			GetErrorType = function(): number
				return 0
			end,
		},
	},
	GuidRegistryService = {},
	HapticService = {
		methods = {
			GetMotor = function(): any
				return nil
			end,
			SetMotor = function() end,
			SetMotorSimple = function() end,
		},
	},
	HttpRbxApiService = {},
	InGamepadService = {},
	InsertService = {
		methods = {
			LoadAsset = function(): any
				return nil
			end,
			LoadAssetVersion = function(): any
				return nil
			end,
			GetAssetList = emptySet,
		},
	},
	KeyboardService = {},
	KeyframeSequenceProvider = {
		methods = {
			GetKeyframeSequenceAsync = function(): any
				return nil
			end,
			GetKeyframeSequence = function(): any
				return nil
			end,
		},
	},
	LicensedGameService = {
		methods = {
			GetKeyCodeMapping = function(): number
				return 0
			end,
		},
	},
	Lighting = {
		props = {
			Brightness = 1,
			Ambient = color(0.5, 0.5, 0.5),
			OutdoorAmbient = color(0.5, 0.5, 0.5),
			ClockTime = 14,
			TimeOfDay = "14:00:00",
			FogEnd = 1000,
			FogStart = 0,
			FogTransparency = 0,
			FogColor = color(0.75, 0.75, 0.75),
			GeographicLatitude = 41.5,
			GlobalShadows = true,
			Shadows = true,
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 1,

			Technology = enum("Future"),
			ColorShift_Top = color(0, 0, 0),
			ColorShift_Bottom = color(0, 0, 0),
			ShadowSoftness = 0.2,
			ExposureCompensation = 0,
			Outlines = false,
			Sky24HourTimeOfDay = 14,
		},
	},
	LinkService = {},
	LocalizationService = {
		props = {
			RobloxLocaleId = "en-us",
			SystemLocaleId = "en-us",
		},
		methods = {
			GetCountryRegionForPlayerAsync = function(): string
				return "US"
			end,
			GetPlayerRegionAsync = function(): string
				return "US"
			end,
			GetSystemLanguageCode = function(): string
				return "en"
			end,
			GetTableForLanguageCode = function(): any
				return {}
			end,
			GetCorescriptLocalizations = function(): { [string]: any }
				return {}
			end,
		},
	},
	LodDataService = {},
	LogService = {
		props = {
			MessageOut = Signal.new("LogService.MessageOut"),
		},
		methods = {
			GetLogHistory = emptySet,
			GetLogHistoryAsync = emptySet,
			ClearOutput = function() end,
		},
	},
	LuaChatService = {},
	LuaWebService = {
		methods = {
			GetAsync = function(): string
				return ""
			end,
			PostAsync = function(): string
				return ""
			end,
		},
	},
	MaterialService = {
		props = { Use2022Materials = false },
	},
	MemoryStoreService = {
		methods = {
			GetMap = function(): any
				return memoryStore()
			end,
			GetSortedMap = function(): any
				return memoryStore()
			end,
			GetQueue = function(): any
				return memoryStore()
			end,
			GetOrderedMap = function(): any
				return memoryStore()
			end,
		},
	},
	MessagingService = {
		methods = {
			PublishAsync = function() end,
			SubscribeAsync = function(): any
				return nil
			end,
		},
	},
	NetworkClient = {
		props = { Ticket = "" },
		methods = {
			Connect = function(): boolean
				return true
			end,
			Disconnect = function() end,
		},
	},
	NetworkServer = {
		props = { Ticket = "" },
		methods = {
			Start = function() end,
			Stop = function() end,
		},
	},
	NetworkSettings = {
		props = {
			IncomingReplicationLag = 0,
			OutgoingReplicationLag = 0,
			NetworkOwnershipPartSize = 0,
		},
	},
	NotificationService = {},
	OmniRecommendationsService = {},
	PathfindingService = {
		props = { EmptyCutoff = 0.5 },
		methods = {
			CreatePath = function(): any
				return nil
			end,
			GetCustomBlockedPaths = emptySet,
		},
	},
	PhysicsService = {
		methods = {
			RegisterCollisionGroup = function() end,
			SetCollisionGroupEnabled = function() end,
			SetPartCollisionGroup = function() end,
			GetCollisionGroupName = function(): string
				return "Default"
			end,
			GetCollisionGroupId = function(): number
				return 1
			end,
			CollisionGroupSet = function(): boolean
				return false
			end,
		},
	},
	PolicyService = {
		methods = {
			GetPolicyInfo = function(): any
				return {}
			end,
		},
	},
	ProximityPromptService = {
		props = { MaxIndicatorsVisible = 5, MaxPromptsVisible = 10 },
		methods = {
			GetEnabledPrompts = emptySet,
		},
	},
	PublishService = {},
	RbxAnalyticsService = {},
	RbxSensorService = {},
	RejectService = {},
	RunService = {
		props = {
			RunState = enum("Running"),
			ClientGitHash = "0.0.0",
			HeartbeatTime = 0,
			HeartbeatTimeMs = 0,
		},
		methods = {
			IsClient = function() return true end,
			IsServer = function() return false end,
			IsRunning = function() return true end,
			IsStudio = function() return false end,
			IsEdit = function() return false end,
			Pause = function() end,
			Run = function() end,
			Stop = function() end,
		},
	},
	ReplicatedFirst = {},
	ReplicatedStorage = {},
	RobloxReplicatedStorage = {},
	ScriptContext = {
		methods = {
			AddStarterScript = function() end,
			SetTimeout = function() end,
		},
	},
	ScriptService = {},
	SecurityService = {},
	Selection = {
		methods = {
			Get = emptySet,
			Set = function() end,
			SetCore = function() end,
		},
	},
	ServerScriptService = {},
	ServerStorage = {},
	SharedTableRegistry = {
		methods = {
			GetSharedTable = function(): any
				return nil
			end,
			SetSharedTable = function() end,
			RemoveSharedTable = function() end,
			WaitForSharedTable = function(): any
				return nil
			end,
		},
	},
	SafetyService = {
		props = { IsCaptureModeForReport = false },
	},
	SmashService = {},
	SocialService = {
		methods = {
			CanSendGameInviteAsync = function(): boolean
				return false
			end,
			CanSendPrivateMessageAsync = function(): boolean
				return false
			end,
			ReportPlayer = function(): boolean
				return false
			end,
			IsGameInviteSupported = function(): boolean
				return false
			end,
			ShowGameInviteUI = function() end,
		},
	},
	SoundService = {
		methods = {
			GetAudioInstances = emptySet,
			GetInputDevices = emptySet,
			GetOutputDevices = emptySet,
		},
		props = {
			RespectFilteringEnabled = false,
			ReverbEnabled = false,
			DiffractionEnabled = false,
			CharacterSoundsUseNewApi = enum("Default"),
			ListenerType = enum("CFrame"),
			DefaultListenerLocation = enum("Default"),

			AmbientReverb = enum("NoReverb"),
			DistanceFactor = 3.33,
			DopplerScale = 1,
			RolloffScale = 1,
			VolumetricAudio = enum("Automatic"),
		},
	},
	StarterGui = {
		props = {
			ResetPlayerGuiOnSpawn = true,
			ShowDevelopmentGui = true,
			ScreenOrientation = enum("LandscapeLeft"),
		},
		methods = {
			SetCore = function() end,
			GetCore = function(): any
				return nil
			end,
			SetCoreGuiEnabled = function() end,
			SetCoreGuiFocused = function() end,
			SetTopbarTransparency = function() end,
			SetPlayerGuiEnabled = function() end,
		},
	},
	StarterPack = {},
	StarterPlayer = {
		props = {
			CharacterAutoLoads = true,
			CharacterLoadTimeout = 0.1,
			EnableMouseLockOption = false,
			UserEmotesEnabled = true,
			CameraMaxZoomDistance = 128,
			CameraMinZoomDistance = 0.5,
			CameraMode = enum("Classic"),
			DevCameraOcclusionMode = enum("Zoom"),
			DevComputerCameraMovementMode = enum("UserChoice"),
			DevTouchCameraMovementMode = enum("UserChoice"),
			AutoJumpEnabled = true,
		},
		methods = {
			LoadCharacter = function() end,
			LoadCharacterWithHumanoidDescription = function() end,
			SetAllowUserTeleports = function() end,
			SetDefaultCameraMode = function() end,
			SetDefaultJumpPower = function() end,
			SetDefaultWalkSpeed = function() end,
		},
	},
	Stats = {
		props = {

			ContactsCount = 0,
			DataReceiveKbps = 0,
			FrameTime = 0,
			HeartbeatTime = 0,
			HeartbeatTimeMs = 0,
			InstanceCount = 0,
			MovingPrimitivesCount = 0,
			PhysicsReceiveKbps = 0,
			PhysicsSendKbps = 0,
			PhysicsStepTime = 0,
			PhysicsStepTimeMs = 0,
			PrimitivesCount = 0,
			RenderCPUFrameTime = 0,
			RenderGPUFrameTime = 0,
			SceneDrawcallCount = 0,
			SceneTriangleCount = 0,
			ShadowsDrawcallCount = 0,
			ShadowsTriangleCount = 0,
			UI2DDrawcallCount = 0,
			UI2DTriangleCount = 0,
			UI3DDrawcallCount = 0,
			UI3DTriangleCount = 0,
		},
		methods = {
			GetStatistic = function(): any
				return nil
			end,
			GetStatisticItem = function(): any
				return nil
			end,
			GetTotalMemoryUsageMb = function(): number
				return 0
			end,
			GetMemoryUsageMbForTag = function(): number
				return 0
			end,
		},
	},
	StatsService = {
		methods = {
			GetStats = function(): any
				return nil
			end,
		},
	},
	StreamingService = {},
	StudioData = {},
	StudioService = {},
	Teams = {
		props = { AutoAssignable = true },
		methods = {
			GetTeams = emptySet,
			GetPlayersInTeam = emptySet,
			GetTeamFromPlayer = function(): any
				return nil
			end,
		},
	},
	TeleportService = {
		props = { CustomizedTeleportUI = true },
		methods = {
			Teleport = function() end,
			TeleportAsync = function() end,
			TeleportToPrivateServer = function() end,
			TeleportPartyAsync = function() end,
			TeleportToSpawnByName = function() end,
			SetTeleportSetting = function() end,
			GetPlayerPlaceInstanceAsync = function(): any
				return nil
			end,
			GetLocalPlayerTeleportData = function(): any
				return nil
			end,
		},
	},
	TestService = {
		props = { IsTesting = false },
		methods = {
			Run = function() end,
			Message = function() end,
			Describe = function() end,
			Expect = function(): any
				return nil
			end,
		},
	},
	ThirdPartyUserService = {
		props = { HasActiveUser = false },
	},
	TextChatService = {
		props = {
			ChatVersion = "TextChatService",
			ChatMode = "Text",
			PlatformIntegratedChat = enum("Default"),
		},
		methods = {
			CreateDefaultTextChannel = function() end,
			CreateTextChannel = function(): any
				return nil
			end,
			GetDefaultTextChannel = function(): any
				return nil
			end,
		},
	},
	TextService = {
		methods = {
			GetTextBoundsAsync = function(): any
				return v2(0, 0)
			end,

			GetTextSize = function(_self: any, text: any, fontSize: any, font: any, frameSize: any): any
				d.__rejectUnknownFont(font, "TextService:GetTextSize()")
				local body = tostring(text or "")
				local size = tonumber(fontSize) or 12
				local perLine = size * 0.5 * #body
				local maxWidth = if type(frameSize) == "table" then (tonumber(frameSize.X) or 0) else 0
				if maxWidth > 0 and perLine > maxWidth then
					return v2(maxWidth, size * math.ceil(perLine / maxWidth))
				end
				return v2(perLine, size)
			end,
			FilterStringAsync = function(): string
				return ""
			end,
			GetNameAsync = function(): string
				return ""
			end,
		},
	},
	ToastNotificationService = {},
	TracerService = {},
	TweenService = {
		methods = {
			Tween = function(): any
				return nil
			end,
			Create = function(): any
				return nil
			end,
		},
	},
	UGCValidationService = {
		methods = {
			Validate = function(): any
				return nil
			end,
			ValidateFull = function(): any
				return nil
			end,
		},
	},
	UserInputService = {
		props = {
			TouchEnabled = true,
			KeyboardEnabled = true,
			MouseEnabled = true,
			GamepadEnabled = false,
			AccelerometerEnabled = false,
			GyroscopeEnabled = false,
			MouseBehavior = 1,
			MouseIconEnabled = true,
			UIPriority = 1,
			UseDefaultCameraControls = true,
			VREnabled = false,
			OnScreenKeyboardVisible = false,
			OnScreenKeyboardSize = v2(0, 0),
			OnScreenKeyboardPosition = v2(0, 0),
			ModalEnabled = false,
			StatusBarTapSignal = nil,
		},
		methods = {
			IsKeyDown = function(): boolean
				return false
			end,
			IsMouseButtonPressed = function(): boolean
				return false
			end,
			GetMouseLocation = function(): any
				return v2(640, 360)
			end,
			GetMouseDelta = function(): any
				return v2(0, 0)
			end,
			IsGamepadConnected = function(): boolean
				return false
			end,
			GetGamepadState = emptySet,
			GetConnectedGamepads = emptySet,
			GetPlatform = function(): number
				return 0
			end,
			GetDeviceIds = emptySet,
			GetFocusedTextBox = function(): any
				return nil
			end,
			GetStringForKeyCode = function(): string
				return ""
			end,
			GetSupportedGamepadKeyCodes = emptySet,
			GamepadSupports = function(): boolean
				return false
			end,
		},
	},
	UserService = {
		methods = {
			GetUserIdFromNameAsync = function(): number
				return 0
			end,
			GetNameFromUserIdAsync = function(): string
				return "Player"
			end,
			GetUserInfosByDisplayNamesAsync = emptySet,
			IsUserNameInUse = function(): boolean
				return false
			end,
			GetUserIdFromDisplayNameAsync = function(): number
				return 0
			end,
			GetDisplayNameFromUserIdAsync = function(): string
				return "Player"
			end,
		},
	},
	VRService = {
		props = { VREnabled = false, VRDevice = "" },
	},
	VirtualInputManager = {
		methods = {
			SendKeyEvent = function() end,
			SendMouseButtonEvent = function() end,
			SendMouseWheelEvent = function() end,
			SendTouchEvent = function() end,
			SendGamepadEvent = function() end,
			SendHapticEvent = function() end,
			SendInputEvent = function() end,
		},
	},
	VirtualUser = {
		methods = {
			Button1Down = function() end,
			Button1Up = function() end,
			Button2Down = function() end,
			Button2Up = function() end,
			CaptureController = function() end,
			ReleaseController = function() end,
			SetMouseIcon = function() end,
			Click = function() end,
			ClickButton = function() end,
		},
	},
	VoiceChatService = {
		methods = {
			joinVoice = function() end,
			rejoinVoice = function() end,
			leaveVoice = function() end,
			GetVoiceChatApiVersion = function(): number
				return 0
			end,
			GetVolumeAsync = function(): number
				return 0
			end,
			SetVolumeAsync = function() end,
		},
	},
	WebService = {
		methods = {
			GetAsync = function(): string
				return ""
			end,
			PostAsync = function(): string
				return ""
			end,
			JSONDecode = function(): any
				return {}
			end,
			JSONEncode = function(): string
				return "{}"
			end,
		},
	},
}

function Services.members(name: string): { props: { [string]: any }, methods: { [string]: any } }?
	return MEMBERS[name]
end

return Services
