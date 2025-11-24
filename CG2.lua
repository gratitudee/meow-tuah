local getgenv = getgenv
local printconsole = printconsole
local GetModuleFromRepo = GetModuleFromRepo
local Drawing = Drawing
local getgc = getgc
local fireclickdetector = fireclickdetector

do
	if getgenv().CG2_SCRIPT_LOADED == true then
		printconsole("Failed to initialise script, please rejoin the game.", Color3.new(1, 0, 0))
		return
	end
	-- Services and Utility
	local Services = GetModuleFromRepo("Services.lua")
	local Utility = GetModuleFromRepo("Utility.lua")
	local UI = GetModuleFromRepo("UI.lua")
	local SaveManager = GetModuleFromRepo("SaveManager.lua")
	local ThemeManager = GetModuleFromRepo("ThemeManager.lua")

	if not Services or not Utility or not UI then
		printconsole("Failed to load meow-tuah", Color3.new(1, 0, 0))
		return
	end

	-- References
	local Workspace = Services.Workspace
	local RunService = Services.RunService
	local ReplicatedStorage = Services.ReplicatedStorage
	local CoreGui = Services.CoreGui
	local VirtualInputManager = Services.VirtualInputManager
	local TextService = Utility.GetService("TextService")
	local StatsService = Utility.GetService("Stats")

	local Player = Utility.GetPlayer()
	local IndexedGetTextSize = Utility.index(TextService, "GetTextSize")
	local Camera = Utility.index(Workspace, "CurrentCamera")
	local SendKeyEvent = Utility.index(VirtualInputManager, "SendKeyEvent")
	local Heartbeat = Utility.index(RunService, "Heartbeat")
	local RenderStepped = Utility.index(RunService, "RenderStepped")
	local WorldToViewportPoint = Utility.index(Camera, "WorldToViewportPoint")
	local FindFirstChild = Utility.FindFirstChild
	local FindFirstChildOfClass = Utility.FindFirstChildOfClass
	local FindFirstChildWhichIsA = Utility.FindFirstChildWhichIsA
	local GetChildren = Utility.GetChildren
	local GetDescendants = Utility.index(game, "GetDescendants")
	local Trinkets = FindFirstChild(Workspace, "Trinkets") or FindFirstChild(Workspace, "TrinketSpawns")
	local Animations = FindFirstChild(ReplicatedStorage, "Animations")

	-- T A B L E S
	local CleanupRegistry = {
		Connections = {},
		Functions = {},
		Objects = {},
	}
	local TrinketShared = {
		Trinkets = {},
		Connections = {},
		_initialized = false,
	}

	local MainScript = {
		Font = "System",
		TextSize = 18,
		FontMap = {
			Monospace = Drawing.Fonts.Monospace,
			System = Drawing.Fonts.System,
			Plex = Drawing.Fonts.Plex,
		},
	}
	local TrinketESP = {
		Settings = {
			Enabled = false,
			ShowName = false,
			ShowDistance = false,
			ShowValue = false,
			ShowHighlight = false,
			MaxDistance = 1000,
			NameColor = Color3.new(1, 1, 1),
			NameAlpha = 1,
			DistanceColor = Color3.new(1, 1, 1),
			DistanceAlpha = 1,
			ValueColor = Color3.new(1, 1, 1),
			ValueAlpha = 1,
			HighlightFillColor = Color3.new(1, 0, 0),
			HighlightFillAlpha = 1,
			HighlightOutlineColor = Color3.new(1, 1, 1),
			HighlightOutlineAlpha = 1,
		},
		Drawings = {},
		Connections = {},
		_initialized = false,
	}

	local TrinketAutograb = {
		Settings = {
			Enabled = false,
			MaxDistance = 100,
		},
		Connections = {},
		_initialized = false,
	}

	local PerfectSlide = {
		Settings = {
			Enabled = true,
			CurrentReplicator = nil,
			CurrentCharacter = nil,
		},
		State = {
			LastGCSearch = 0,
			TimeBetweenSearch = 1,
		},
		Connections = {},
		_initialized = false,
	}

	local AutoParry = {
		Settings = {
			Enabled = false,
			MaxDistance = 5,
			AnimationPercentage = 50,
			PingAdjustment = 100,
			AdjustTimingsBySlider = 0,
		},
		State = {
			Connections = {},
			EntityData = {},
			Parrying = false,
		},
		AllowList = {},
	}

	local ValueMap = {
		["Fork"] = 5,
		["Blood Ruby"] = 10,
		["Ruby"] = 10,
		["Amethyst"] = 10,
		["Spoon"] = 5,
		["Plate"] = 5,
		["Diamond"] = 10,
		["Chain"] = 5,
		["Sapphire"] = 10,
		["Goblet"] = 5,
		["Bowl"] = 5,
		["Emerald"] = 10,
		["Model"] = 67,
	}

	local AnimationNameWhitelist = {
		"Swing",
		"Critical",
		"Thrust",
	}

	-- Util funcs
	local function GetPing()
		local PerformanceStats = FindFirstChild(StatsService, "Network")
		if not PerformanceStats then
			return 0
		end

		local ServerStats = FindFirstChild(PerformanceStats, "ServerStatsItem")
		if not ServerStats then
			return 0
		end

		local DataPing = FindFirstChild(ServerStats, "Data Ping")
		if not DataPing then
			return 0
		end

		return DataPing:GetValue()
	end

	local function ContainsWhitelistedName(name)
		for _, allowed in ipairs(AnimationNameWhitelist) do
			if string.find(name, allowed) then
				return true
			end
		end
		return false
	end

	local function GetAnimationAllowList()
		if not Animations then
			printconsole("Failed to parse animations, auto parry won't function.", Color3.new(1, 0, 0))
			return
		end

		for _, SubFolder in pairs(GetChildren(Animations)) do
			for _, Animations in pairs(GetDescendants(SubFolder)) do
				if Animations:IsA("Animation") and ContainsWhitelistedName(Animations.Name) then
					table.insert(AutoParry.AllowList, Animations.AnimationId)
				end
			end
		end
	end

	local function GetTextSize(text, size, font)
		local bounds = IndexedGetTextSize(TextService, text, size, font, Vector2.new(9999, 9999))
		return bounds.X, bounds.Y
	end

	local function SendKeyUpKeyDown(Key, Delay)
		SendKeyEvent(VirtualInputManager, true, Key, false, nil)
		task.wait(Delay)
		SendKeyEvent(VirtualInputManager, false, Key, false, nil)
	end

	local function GetItemValue(Name)
		return ValueMap[Name]
	end

	local function Clear(drawings)
		for t, obj in pairs(drawings) do
			if t == "Highlight" then
				obj.Adornee = nil
			else
				obj.Visible = false
			end
		end
	end

	local function WorldToScreen(World)
		local Screen, InBounds = WorldToViewportPoint(Camera, World)
		return Vector2.new(Screen.X, Screen.Y), InBounds, Screen.Z
	end

	local function CleanupEverything()
		if FindFirstChild(CoreGui, "CG2Highlights") then
			FindFirstChild(CoreGui, "CG2Highlights"):Destroy()
		end

		for _, connectionList in pairs({
			CleanupRegistry.Connections,
			TrinketShared.Connections,
			TrinketESP.Connections,
			TrinketAutograb.Connections,
			PerfectSlide.Connections,
		}) do
			for i, connection in ipairs(connectionList) do
				if typeof(connection) == "RBXScriptConnection" then
					connection:Disconnect()
				end
			end
			table.clear(connectionList)
		end

		for i, cleanupFunc in ipairs(CleanupRegistry.Functions) do
			pcall(cleanupFunc)
		end
		table.clear(CleanupRegistry.Functions)

		for i, object in ipairs(CleanupRegistry.Objects) do
			if object and object.Destroy then
				pcall(function()
					object:Destroy()
				end)
			end
		end
		table.clear(CleanupRegistry.Objects)

		for _, DrawingDict in pairs(TrinketESP.Drawings) do
			for k, Drawings in pairs(DrawingDict) do
				if k ~= "Highlight" then
					Drawings:Remove()
					Drawings = nil
				else
					Drawings:Destroy()
					Drawings = nil
				end
			end
		end

		TrinketShared._initialized = false
		TrinketESP._initialized = false
		TrinketAutograb._initialized = false
		PerfectSlide._initialized = false
		table.clear(TrinketShared.Trinkets)
	end

	-- UI Init
	local Window = UI:Window({
		Name = "MEOW TUAH",
		Size = UDim2.new(0, 600, 0, 500),
		GradientTitle = {
			Enabled = true,
			Start = Color3.fromRGB(255, 0, 0),
			Middle = Color3.fromRGB(0, 255, 0),
			End = Color3.fromRGB(0, 0, 255),
			Speed = 1,
		},
	})

	local AutoParryPage = Window:Page({
		Name = "Auto Parry",
		Columns = 1,
	})

	local AutoParrySection1 = AutoParryPage:Section({
		Name = "Main",
		Side = 1,
	})

	local AutoParryToggle = AutoParrySection1:Toggle({
		Name = "Auto Parry",
		Flag = "Auto_Parry_Toggle",
		Default = false,
		Callback = function(value)
			AutoParry.Settings.Enabled = value
		end,
	})

	AutoParryToggle:Keybind({
		Name = "Auto Parry Key",
		Flag = "Auto_Parry_Keybind",
		Default = Enum.KeyCode.E,
		Mode = "Hold",
		Callback = function(toggled)
			AutoParryToggle:Set(toggled)
		end,
	})

	AutoParrySection1:Slider({
		Name = "Auto Parry Max Distance",
		Flag = "Auto_Parry_Max_Distance",
		Min = 1,
		Max = 20,
		Default = 10,
		Callback = function(value)
			AutoParry.Settings.MaxDistance = tonumber(value)
		end,
	})

	AutoParrySection1:Slider({
		Name = "Animation Percentage",
		Flag = "Auto_Parry_Animation_Percentage",
		Min = 1,
		Max = 100,
		Default = 50,
		Suffix = "%",
		Callback = function(value)
			AutoParry.Settings.AnimationPercentage = tonumber(value)
		end,
	})

	AutoParrySection1:Slider({
		Name = "Ping Adjustment",
		Flag = "Auto_Parry_Ping_Adjustment",
		Min = 0,
		Max = 200,
		Default = 100,
		Suffix = "%",
		Callback = function(value)
			AutoParry.Settings.PingAdjustment = tonumber(value)
		end,
	})

	local TrinketPage = Window:Page({
		Name = "Trinkets",
		Columns = 2,
	})

	local TrinketESPSection = TrinketPage:Section({
		Name = "Visuals",
		Side = 1,
	})

	local TrinketAutoGrabSection = TrinketPage:Section({
		Name = "Auto-Grab",
		Side = 2,
	})

	local Movement = Window:Page({
		Name = "Movement",
		Columns = 1,
	})

	local Settings = Window:Page({
		Name = "Settings",
		Columns = 2,
	})

	local MovementSection = Movement:Section({
		Name = "Main",
		Side = 1,
	})

	local Config = Settings:Section({
		Name = "Configuration",
		Side = 1,
	})

	local SettingsSection = Settings:Section({
		Name = "Settings",
		Side = 2,
	})

	Config:Label("Preset Themes", "Center")
	local PresetThemes = {
		{ "Default", "Default" },
		{ "Bitchbot", "Bitchbot" },
		{ "Onetap", "Onetap" },
		{ "Aqua", "Aqua" },
		{ "Fent", "Fent" },
	}

	for _, theme in pairs(PresetThemes) do
		Config:Button({
			Name = "Load " .. theme[1],
			Callback = function()
				if UI.Themes[theme[2]] then
					for themeName, color in pairs(UI.Themes[theme[2]]) do
						UI:ChangeTheme(themeName, color)
					end
					UI:Notification("Loaded " .. theme[1] .. " theme!", 3, Color3.fromRGB(0, 255, 0))
				end
			end,
		})
	end

	SettingsSection:Button({
		Name = "Unload Script",
		Risky = false,
		Callback = function()
			UI:Unload()
			CleanupEverything()
		end,
	})

	local PerfectSlideToggle = MovementSection:Toggle({
		Name = "Perfect Slide",
		Flag = "Perfect_Slide_Toggle",
		Default = PerfectSlide.Settings.Enabled,
		Callback = function(value)
			PerfectSlide.Settings.Enabled = value
		end,
	})

	PerfectSlideToggle:Keybind({
		Name = "Perfect Slide Bind",
		Flag = "Perfect_Slide_Keybind",
		Default = Enum.KeyCode.E,
		Mode = "Hold",
		Callback = function(toggled)
			PerfectSlideToggle:Set(toggled)
		end,
	})

	TrinketESPSection:Toggle({
		Name = "Trinket ESP",
		Flag = "Trinket_ESP_Toggle",
		Default = TrinketESP.Settings.Enabled,
		Callback = function(value)
			TrinketESP.Settings.Enabled = value
		end,
	})

	TrinketESPSection:Toggle({
		Name = "Name",
		Flag = "Trinket_Name_ESP_Toggle",
		Default = TrinketESP.Settings.ShowName,
		Callback = function(value)
			TrinketESP.Settings.ShowName = value
		end,
	}):Colorpicker({
		Name = "Name ESP Color",
		Flag = "Trinket_Name_ESP_Color",
		Default = TrinketESP.Settings.NameColor,
	})

	TrinketESPSection:Toggle({
		Name = "Distance",
		Flag = "Trinket_Distance_ESP_Toggle",
		Default = TrinketESP.Settings.ShowDistance,
		Callback = function(value)
			TrinketESP.Settings.ShowDistance = value
		end,
	}):Colorpicker({
		Name = "Distance ESP Color",
		Flag = "Trinket_Distance_ESP_Color",
		Default = TrinketESP.Settings.DistanceColor,
	})

	TrinketESPSection:Toggle({
		Name = "Value",
		Flag = "Trinket_Value_ESP_Toggle",
		Default = TrinketESP.Settings.ShowValue,
		Callback = function(value)
			TrinketESP.Settings.ShowValue = value
		end,
	}):Colorpicker({
		Name = "Value ESP Color",
		Flag = "Trinket_Value_ESP_Color",
		Default = TrinketESP.Settings.ValueColor,
	})

	HighlightESPToggle = TrinketESPSection:Toggle({
		Name = "Highlight",
		Flag = "Trinket_Highlight_ESP_Toggle",
		Default = TrinketESP.Settings.ShowHighlight,
		Callback = function(value)
			TrinketESP.Settings.ShowHighlight = value
		end,
	})

	TrinketESPSection:Label("Highlight Fill", "Left"):Colorpicker({
		Name = "Highlight Fill ESP Color",
		Flag = "Trinket_Highlight_Fill_ESP_Color",
		Default = TrinketESP.Settings.HighlightFillColor,
	})

	TrinketESPSection:Label("Highlight Outline", "Left"):Colorpicker({
		Name = "Highlight Outline ESP Color",
		Flag = "Trinket_Highlight_Outline_ESP_Color",
		Default = TrinketESP.Settings.HighlightOutlineColor,
	})

	TrinketESPSection:Slider({
		Name = "Trinket ESP Max Distance",
		Flag = "Trinket_ESP_Max_Distance",
		Min = 1,
		Max = 1000,
		Default = TrinketESP.Settings.MaxDistance,
		Callback = function(value)
			TrinketESP.Settings.MaxDistance = tonumber(value)
		end,
	})

	TrinketAutoGrabSection:Toggle({
		Name = "Trinket Auto Grab",
		Flag = "Trinket_AutoGrab_Toggle",
		Default = TrinketAutograb.Settings.Enabled,
		Callback = function(value)
			TrinketAutograb.Settings.Enabled = value
		end,
	})

	TrinketAutoGrabSection:Slider({
		Name = "Trinket Auto Grab Max Distance",
		Flag = "Trinket_AutoGrab_Max_Distance",
		Min = 1,
		Max = 100,
		Default = TrinketAutograb.Settings.MaxDistance,
		Callback = function(value)
			TrinketAutograb.Settings.MaxDistance = tonumber(value)
		end,
	})

	-- UI Update
	UI:Connect(RunService.Heartbeat, function()
		local nameColorData = UI.Flags.Trinket_Name_ESP_Color
		if
			nameColorData
			and (
				nameColorData.Color ~= TrinketESP.Settings.NameColor
				or nameColorData.Alpha ~= TrinketESP.Settings.NameAlpha
			)
		then
			TrinketESP.Settings.NameColor = nameColorData.Color
			TrinketESP.Settings.NameAlpha = nameColorData.Alpha or 1
			for _, drawings in pairs(TrinketESP.Drawings) do
				if drawings.Name then
					drawings.Name.Color = nameColorData.Color
					drawings.Name.Transparency = 1 - (nameColorData.Alpha or 1)
				end
			end
		end

		local distanceColorData = UI.Flags.Trinket_Distance_ESP_Color
		if
			distanceColorData
			and (
				distanceColorData.Color ~= TrinketESP.Settings.DistanceColor
				or distanceColorData.Alpha ~= TrinketESP.Settings.DistanceAlpha
			)
		then
			TrinketESP.Settings.DistanceColor = distanceColorData.Color
			TrinketESP.Settings.DistanceAlpha = distanceColorData.Alpha or 1
			for _, drawings in pairs(TrinketESP.Drawings) do
				if drawings.Distance then
					drawings.Distance.Color = distanceColorData.Color
					drawings.Distance.Transparency = 1 - (distanceColorData.Alpha or 1)
				end
			end
		end

		local valueColorData = UI.Flags.Trinket_Value_ESP_Color
		if
			valueColorData
			and (
				valueColorData.Color ~= TrinketESP.Settings.ValueColor
				or valueColorData.Alpha ~= TrinketESP.Settings.ValueAlpha
			)
		then
			TrinketESP.Settings.ValueColor = valueColorData.Color
			TrinketESP.Settings.ValueAlpha = valueColorData.Alpha or 1
			for _, drawings in pairs(TrinketESP.Drawings) do
				if drawings.Value then
					drawings.Value.Color = valueColorData.Color
					drawings.Value.Transparency = 1 - (valueColorData.Alpha or 1)
				end
			end
		end

		local highlightFillData = UI.Flags.Trinket_Highlight_Fill_ESP_Color
		if
			highlightFillData
			and (
				highlightFillData.Color ~= TrinketESP.Settings.HighlightFillColor
				or highlightFillData.Alpha ~= TrinketESP.Settings.HighlightFillAlpha
			)
		then
			TrinketESP.Settings.HighlightFillColor = highlightFillData.Color
			TrinketESP.Settings.HighlightFillAlpha = highlightFillData.Alpha or 1
			for _, drawings in pairs(TrinketESP.Drawings) do
				if drawings.Highlight then
					drawings.Highlight.FillColor = highlightFillData.Color
					drawings.Highlight.FillTransparency = highlightFillData.Alpha or 1
				end
			end
		end

		local highlightOutlineData = UI.Flags.Trinket_Highlight_Outline_ESP_Color
		if
			highlightOutlineData
			and (
				highlightOutlineData.Color ~= TrinketESP.Settings.HighlightOutlineColor
				or highlightOutlineData.Alpha ~= TrinketESP.Settings.HighlightOutlineAlpha
			)
		then
			TrinketESP.Settings.HighlightOutlineColor = highlightOutlineData.Color
			TrinketESP.Settings.HighlightOutlineAlpha = highlightOutlineData.Alpha or 1
			for _, drawings in pairs(TrinketESP.Drawings) do
				if drawings.Highlight then
					drawings.Highlight.OutlineColor = highlightOutlineData.Color
					drawings.Highlight.OutlineTransparency = highlightOutlineData.Alpha or 1
				end
			end
		end
	end)

	function AutoParry:SimulateKeyFromKeyEvents(KeyCode)
		if AutoParry.State.Parrying then
			return
		end

		AutoParry.State.Parrying = true
		SendKeyEvent(VirtualInputManager, true, KeyCode, false, nil)
		local KeyPressDelay = math.random(0.045, 0.087)
		task.delay(KeyPressDelay, function()
			AutoParry.State.Parrying = false
			SendKeyEvent(VirtualInputManager, false, KeyCode, false, nil)
		end)
	end

	function AutoParry:Initialise()
		if self.State.Connections.Heartbeat then
			return
		end

		self:StartPlayerMonitoring()
	end

	function AutoParry:StartPlayerMonitoring()
		for _, player in ipairs(Utility.GetChildren(Services.Players)) do
			if player:IsA("Player") then
				self:MonitorPlayer(player)
			end
		end

		self.State.Connections.PlayerAdded = Utility.index(Services.Players, "PlayerAdded"):Connect(function(player)
			self:MonitorPlayer(player)
		end)

		self.State.Connections.PlayerRemoving = Utility.index(Services.Players, "PlayerRemoving")
			:Connect(function(player)
				self:CleanupPlayer(player)
			end)
	end

	function AutoParry:CleanupPlayer(player)
		if self.State.Connections[player] then
			self.State.Connections[player]:Disconnect()
			self.State.Connections[player] = nil
		end

		local charConnectionKey = player.Name .. "Character"
		if self.State.Connections[charConnectionKey] then
			self.State.Connections[charConnectionKey]:Disconnect()
			self.State.Connections[charConnectionKey] = nil
		end

		for key, connection in pairs(self.State.Connections) do
			if typeof(key) == "userdata" and key.Parent and key.Parent.Parent == player.Character then
				connection:Disconnect()
				self.State.Connections[key] = nil
			end
		end
	end

	function AutoParry:MonitorPlayer(player)
		local function setupCharacter(character)
			if not character then
				return
			end

			local humanoid = FindFirstChildOfClass(character, "Humanoid")
			local animator = humanoid and FindFirstChildOfClass(humanoid, "Animator")
			if not animator then
				return
			end

			local connectionKey = player.Name .. "AnimationPlayed"
			if self.State.Connections[connectionKey] then
				self.State.Connections[connectionKey]:Disconnect()
			end

			self.State.Connections[connectionKey] = Utility.index(animator, "AnimationPlayed")
				:Connect(function(track: AnimationTrack)
					if not table.find(AutoParry.AllowList, track.Animation.AnimationId) then
						return
					end

					self:OnAnimationPlayed(player, character, track)
				end)
		end

		local character = Utility.GetCharacter(player)
		if character then
			setupCharacter(character)
		end

		local charConnectionKey = player.Name .. "Character"
		if self.State.Connections[charConnectionKey] then
			self.State.Connections[charConnectionKey]:Disconnect()
		end

		self.State.Connections[charConnectionKey] = Utility.index(player, "CharacterAdded"):Connect(function(character)
			setupCharacter(character)
		end)
	end

	function AutoParry:OnAnimationPlayed(player, character, track)
		if not self.Settings.Enabled or player == Player then
			return
		end

		local localCharacter = Utility.GetCharacter(Player)
		local localRootPart = localCharacter and FindFirstChild(localCharacter, "HumanoidRootPart")
		local enemyRootPart = FindFirstChild(character, "HumanoidRootPart")

		if not localRootPart or not enemyRootPart then
			return
		end

		local distance = (enemyRootPart.Position - localRootPart.Position).Magnitude
		if distance > self.Settings.MaxDistance then
			return
		end

		local ping = GetPing()
		local pingAdjustment = (ping / 1000) * 100 * (self.Settings.PingAdjustment / 100)
		local adjustedPercentage = self.Settings.AnimationPercentage - pingAdjustment

		local connectionKey = player.Name .. "_" .. track.Animation.AnimationId

		if self.State.Connections[connectionKey] then
			self.State.Connections[connectionKey]:Disconnect()
		end

		self.State.Connections[connectionKey] = RunService.Heartbeat:Connect(function()
			if not track or not track.IsPlaying then
				self.State.Connections[connectionKey]:Disconnect()
				self.State.Connections[connectionKey] = nil
				return
			end

			local progressPercentage = (track.TimePosition / track.Length) * 100

			if progressPercentage >= adjustedPercentage then
				self:ExecuteParry()
				if self.State.Connections[connectionKey] then
					self.State.Connections[connectionKey]:Disconnect()
					self.State.Connections[connectionKey] = nil
				end
			end
		end)
	end

	function AutoParry:OnAttackDetected(player, character, track)
		if not self.Settings.Enabled then
			return
		end

		local localCharacter = Utility.GetCharacter(Player)
		local localRootPart = localCharacter and FindFirstChild(localCharacter, "HumanoidRootPart")
		local enemyRootPart = FindFirstChild(character, "HumanoidRootPart")

		if not localRootPart or not enemyRootPart then
			return
		end

		local distance = (enemyRootPart.Position - localRootPart.Position).Magnitude
		if distance > self.Settings.MaxDistance then
			return
		end

		self:ExecuteParry()
		print("Auto parry triggered at " .. self.Settings.AnimationPercentage .. "% animation progress")
	end

	function AutoParry:ExecuteParry()
		AutoParry:SimulateKeyFromKeyEvents(Enum.KeyCode.F)
	end

	function AutoParry:Toggle()
		self.Settings.Enabled = not self.Settings.Enabled
		if not self.Settings.Enabled then
			self:ClearTarget()
		end
		print("Auto Parry:", self.Settings.Enabled)
	end

	function AutoParry:SetMaxDistance(distance)
		self.Settings.MaxDistance = distance
	end

	function AutoParry:Cleanup()
		for name, connection in pairs(self.State.Connections) do
			if typeof(connection) == "RBXScriptConnection" then
				connection:Disconnect()
			end
		end
		table.clear(self.State.Connections)
	end

	table.insert(CleanupRegistry.Functions, function()
		AutoParry:Cleanup()
	end)

	function PerfectSlide:DoSlide()
		SendKeyUpKeyDown(Enum.KeyCode.LeftControl, 0.01)
		SendKeyUpKeyDown(Enum.KeyCode.Space, 0.01)
	end

	function PerfectSlide:CanSlide()
		if not PerfectSlide.Settings.CurrentReplicator then
			return false
		end

		local replicator = PerfectSlide.Settings.CurrentReplicator

		local blocklist = {
			"SlideCooldown",
			"Stun",
			"TrueStun",
			"Carried",
			"Downed",
			"Blocking",
			"Swinging",
			"Glorying",
			"Gloried",
			"Executing",
			"Executed",
			"Doing",
			"BeingDone",
			"Critting",
			"Crouching",
			"Knockdown",
		}

		for _, state in pairs(blocklist) do
			if replicator:Has(state) then
				return false
			end
		end

		return replicator:Has("Sprinting")
	end

	function PerfectSlide:FilterGCForReplicator()
		local Now = tick()
		if Now - PerfectSlide.State.LastGCSearch < PerfectSlide.State.TimeBetweenSearch then
			return nil
		end
		PerfectSlide.State.LastGCSearch = Now

		for _, trash in pairs(getgc()) do
			if type(trash) == "table" and rawget(trash, "Tokens") and rawget(trash, "Listeners") then
				if trash.Character == PerfectSlide.Settings.CurrentCharacter then
					PerfectSlide.Settings.CurrentReplicator = trash
					return trash
				end
			end
		end
		return nil
	end

	function PerfectSlide:Initialise()
		if self._initialized then
			return
		end

		local SlideHeartbeat = Heartbeat:Connect(function()
			if not PerfectSlide.Settings.Enabled then
				return
			end

			if not PerfectSlide.Settings.CurrentCharacter then
				PerfectSlide.Settings.CurrentCharacter = Utility.index(Player, "Character")
				return
			end

			if not PerfectSlide.Settings.CurrentReplicator then
				PerfectSlide:FilterGCForReplicator()
				return
			end

			local CanSlide = PerfectSlide:CanSlide()
			if CanSlide then
				PerfectSlide:DoSlide()
			end
		end)

		local SlideCharacterAdded = Utility.index(Player, "CharacterAdded"):Connect(function(Character)
			if PerfectSlide.Settings.CurrentReplicator then
				PerfectSlide.Settings.CurrentReplicator = nil
				PerfectSlide.Settings.CurrentCharacter = Character
			end
		end)

		self._initialized = true
		table.insert(CleanupRegistry, SlideHeartbeat)
		table.insert(CleanupRegistry, SlideCharacterAdded)
	end

	function TrinketESP:Render()
		local Settings = self.Settings
		if not Settings.Enabled then
			for _, drawings in pairs(self.Drawings) do
				for t, obj in pairs(drawings) do
					if t == "Highlight" then
						obj.Adornee = nil
					else
						obj.Visible = false
					end
				end
			end
			return
		end

		local Character = Utility.GetCharacter(Player)
		if not Character then
			return
		end

		local Head = Character:FindFirstChild("Head") or Character:FindFirstChild("HumanoidRootPart")
		if not Head then
			return
		end

		local HeadPos = Head.Position
		local MaxDist = Settings.MaxDistance

		local DrawingsTable = self.Drawings
		local Trinkets = TrinketShared.Trinkets

		for Trinket, Data in pairs(Trinkets) do
			local drawings = DrawingsTable[Data.ID]
			if not drawings then
				continue
			end

			if not Data.IsActive then
				Clear(drawings)
				continue
			end

			local pos, onScreen = WorldToScreen(Trinket.Position)
			if not onScreen then
				Clear(drawings)
				continue
			end

			local distance = (Trinket.Position - HeadPos).Magnitude
			if distance > MaxDist then
				Clear(drawings)
				continue
			end

			local NameText = Data.Name or "Unknown"
			local DistanceText = "[" .. math.floor(distance) .. "m]"
			local ValueText = tostring(Data.Value) or "N/A"

			local ShowName = drawings.Name and Settings.ShowName
			local ShowDistance = drawings.Distance and Settings.ShowDistance
			local ShowValue = drawings.Value and Settings.ShowValue
			local ShowHighlight = drawings.Highlight and Settings.ShowHighlight

			local NameWidth = ShowName and select(1, GetTextSize(NameText, drawings.Name.Size, drawings.Name.Font)) or 0
			local DistWidth = ShowDistance
					and select(1, GetTextSize(DistanceText, drawings.Distance.Size, drawings.Distance.Font))
				or 0
			local ValueWidth = ShowValue and select(1, GetTextSize(ValueText, drawings.Value.Size, drawings.Value.Font))
				or 0

			local LineHeight = 14
			local Row1Width = NameWidth + DistWidth
			local MaxWidth = math.max(Row1Width, ValueWidth)

			local x0 = pos.X - MaxWidth * 0.5
			local y1 = pos.Y
			local y2 = pos.Y + LineHeight

			local x = x0

			if ShowName then
				local obj = drawings.Name
				obj.Text = NameText
				obj.Position = Vector2.new(x, y1)
				obj.Visible = true
				x = x + NameWidth
			else
				drawings.Name.Visible = false
			end

			if ShowDistance then
				local obj = drawings.Distance
				obj.Text = DistanceText
				obj.Position = Vector2.new(x, y1)
				obj.Visible = true
			else
				drawings.Distance.Visible = false
			end

			if ShowValue then
				local obj = drawings.Value
				obj.Text = ValueText
				obj.Position = Vector2.new(x0 + (MaxWidth - ValueWidth) * 0.5, y2)
				obj.Visible = true
			else
				drawings.Value.Visible = false
			end

			if ShowHighlight then
				drawings.Highlight.Adornee = Data.Model
			else
				drawings.Highlight.Adornee = nil
			end
		end
	end

	function TrinketESP:UpdateFontSettings()
		for _, drawings in pairs(self.Drawings) do
			if drawings.Name then
				drawings.Name.Size = MainScript.TextSize
				drawings.Name.Font = MainScript.FontMap[MainScript.Font] or Drawing.Fonts.System
			end
			if drawings.Distance then
				drawings.Distance.Size = MainScript.TextSize
				drawings.Distance.Font = MainScript.FontMap[MainScript.Font] or Drawing.Fonts.System
			end
			if drawings.Value then
				drawings.Value.Size = MainScript.TextSize
				drawings.Value.Font = MainScript.FontMap[MainScript.Font] or Drawing.Fonts.System
			end
		end
	end

	function TrinketESP:Initialise()
		if self._initialized then
			return
		end

		local Highlights = Utility.FindFirstChild(CoreGui, "CG2Highlights")
		if not Highlights then
			Highlights = Instance.new("Folder")
			Highlights.Name = "CG2Highlights"
			Highlights.Parent = CoreGui
		end

		TrinketESP.Drawings = TrinketESP.Drawings or {}
		for Trinket, Data in pairs(TrinketShared.Trinkets) do
			Data.ID = Data.ID

			local TrinketNameDraw = Drawing.new("Text")
			TrinketNameDraw.Visible = false
			TrinketNameDraw.Position = Vector2.new(0, 0)
			TrinketNameDraw.Text = Data.Name or "Unknown"
			TrinketNameDraw.Color = TrinketESP.Settings.NameColor
			TrinketNameDraw.Size = MainScript.TextSize
			TrinketNameDraw.Font = Drawing.Fonts[MainScript.Font]

			local DistanceNameDraw = Drawing.new("Text")
			DistanceNameDraw.Visible = false
			DistanceNameDraw.Position = Vector2.new(0, 0)
			DistanceNameDraw.Text = "[0m]"
			DistanceNameDraw.Color = TrinketESP.Settings.DistanceColor
			DistanceNameDraw.Size = MainScript.TextSize
			DistanceNameDraw.Font = Drawing.Fonts[MainScript.Font]

			local ValueNameDraw = Drawing.new("Text")
			ValueNameDraw.Visible = false
			ValueNameDraw.Position = Vector2.new(0, 0)
			ValueNameDraw.Text = Data.Value or "N/A"
			ValueNameDraw.Color = TrinketESP.Settings.ValueColor
			ValueNameDraw.Size = MainScript.TextSize
			ValueNameDraw.Font = Drawing.Fonts[MainScript.Font]

			local Highlight = Instance.new("Highlight")
			Highlight.Name = Data.ID
			Highlight.Parent = Highlights
			Highlight.Enabled = true
			Highlight.Adornee = nil
			Highlight.FillColor = TrinketESP.Settings.HighlightFillColor
			Highlight.OutlineColor = TrinketESP.Settings.HighlightOutlineColor

			TrinketESP.Drawings[Data.ID] = {
				Name = TrinketNameDraw,
				Value = ValueNameDraw,
				Distance = DistanceNameDraw,
				Highlight = Highlight,
			}
		end

		local RenderConnection = RenderStepped:Connect(function()
			self:Render()
		end)

		table.insert(CleanupRegistry.Connections, RenderConnection)
		self._initialized = true
	end

	function TrinketESP:Toggle()
		self.Settings.Enabled = not self.Settings.Enabled
	end

	function TrinketESP:SetMaxDistance(Distance)
		self.Settings.MaxDistance = Distance
	end

	function TrinketAutograb:Initialise()
		if self._initialized then
			return
		end

		local HeartbeatConnection = Heartbeat:Connect(function()
			if not self.Settings.Enabled then
				return
			end

			local Character = Utility.GetCharacter(Player)
			if not Character then
				return
			end

			local Humanoid = FindFirstChildOfClass(Character, "Humanoid")
			local RootPart = FindFirstChild(Character, "Head") or FindFirstChild(Character, "HumanoidRootPart")

			if not RootPart or not Humanoid or Humanoid.Health <= 0 then
				return
			end

			for Trinket, Data in pairs(TrinketShared.Trinkets) do
				if not Data.IsActive or not Data.ClickDetector then
					continue
				end

				local Distance = (RootPart.Position - Trinket.Position).Magnitude
				if Distance > self.Settings.MaxDistance then
					continue
				end

				local Detector = Data.ClickDetector
				if Distance <= Detector.MaxActivationDistance then
					fireclickdetector(Detector)
				end
			end
		end)

		table.insert(CleanupRegistry.Connections, HeartbeatConnection)
		self._initialized = true
	end

	function TrinketAutograb:Toggle()
		self.Settings.Enabled = not self.Settings.Enabled
	end

	function TrinketShared:Initialise()
		if self._initialized then
			return
		end

		if not Trinkets then
			printconsole("Trinkets folder not found!", Color3.new(1, 0, 0))
			return
		end

		for i, Trinket: Instance in pairs(GetChildren(Trinkets)) do
			local Model = FindFirstChildWhichIsA(Trinket, "Model", true)
			local ClickDetector = FindFirstChildWhichIsA(Trinket, "ClickDetector", true)
			TrinketShared.Trinkets[Trinket] = {
				IsActive = Model ~= nil,
				ClickDetector = ClickDetector,
				Name = Model and Model.Name or nil,
				Model = Model,
				Value = Model and GetItemValue(Model.Name) or nil,
				ID = i,
			}

			local addedConnection = Utility.index(Trinket, "ChildAdded"):Connect(function(Child)
				local ClickDetector = FindFirstChildWhichIsA(Trinket, "ClickDetector", true)
				local SharedTrinket = TrinketShared.Trinkets[Trinket]
				SharedTrinket.IsActive = true
				SharedTrinket.Name = Child.Name
				SharedTrinket.Value = ValueMap[Child.Name] or nil
				SharedTrinket.ClickDetector = ClickDetector or nil
				SharedTrinket.Model = Child
			end)

			local removedConnection = Utility.index(Trinket, "ChildRemoved"):Connect(function(Child)
				local SharedTrinket = TrinketShared.Trinkets[Trinket]
				SharedTrinket.IsActive = false
				SharedTrinket.Name = nil
				SharedTrinket.Value = nil
				SharedTrinket.ClickDetector = nil
				SharedTrinket.Model = nil
			end)

			table.insert(CleanupRegistry.Connections, addedConnection)
			table.insert(CleanupRegistry.Connections, removedConnection)
		end

		self._initialized = true
	end

	GetAnimationAllowList()
	PerfectSlide:Initialise()
	TrinketShared:Initialise()
	TrinketESP:Initialise()
	TrinketAutograb:Initialise()
	UI:KeybindList()
	getgenv().CG2_SCRIPT_LOADED = true
end
