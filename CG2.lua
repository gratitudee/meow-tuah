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
	local Library = GetModuleFromRepo("UI.lua")
	local SaveManager = GetModuleFromRepo("SaveManager.lua")
	local ThemeManager = GetModuleFromRepo("ThemeManager.lua")

	if not Services or not Utility then
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

	-- UI Init using new library
	local Window = Library:CreateWindow({
		Title = "MEOW TUAH",
		Center = true,
		AutoShow = true,
		TabPadding = 8,
		MenuFadeTime = 0.2,
	})

	-- Create tabs
	local Tabs = {
		AutoParry = Window:AddTab("Auto Parry"),
		Trinkets = Window:AddTab("Trinkets"),
		Movement = Window:AddTab("Movement"),
		Settings = Window:AddTab("UI Settings"),
	}

	-- Auto Parry Tab
	local AutoParryLeftGroup = Tabs.AutoParry:AddLeftGroupbox("Main")

	local AutoParryToggle = AutoParryLeftGroup:AddToggle("AutoParryToggle", {
		Text = "Auto Parry",
		Default = false,
	})

	AutoParryToggle:AddKeyPicker("AutoParryKey", {
		Default = "E",
		Mode = "Hold",
		Text = "Auto Parry Key",
		NoUI = false,
	})

	AutoParryLeftGroup:AddSlider("AutoParryDistance", {
		Text = "Auto Parry Max Distance",
		Default = 10,
		Min = 1,
		Max = 20,
		Rounding = 0,
	})

	AutoParryLeftGroup:AddSlider("AutoParryPercentage", {
		Text = "Animation Percentage",
		Default = 50,
		Min = 1,
		Max = 100,
		Rounding = 0,
		Suffix = "%",
	})

	AutoParryLeftGroup:AddSlider("AutoParryPing", {
		Text = "Ping Adjustment",
		Default = 100,
		Min = 0,
		Max = 200,
		Rounding = 0,
		Suffix = "%",
	})

	-- Trinkets Tab
	local TrinketsLeftGroup = Tabs.Trinkets:AddLeftGroupbox("Visuals")
	local TrinketsRightGroup = Tabs.Trinkets:AddRightGroupbox("Auto-Grab")

	-- Trinket ESP Toggles
	local TrinketESPToggle = TrinketsLeftGroup:AddToggle("TrinketESP", {
		Text = "Trinket ESP",
		Default = false,
	})

	local TrinketNameToggle = TrinketsLeftGroup:AddToggle("TrinketName", {
		Text = "Name",
		Default = false,
	})

	TrinketsLeftGroup:AddLabel("Name Color"):AddColorPicker("TrinketNameColor", {
		Default = Color3.new(1, 1, 1),
		Title = "Name Color",
	})

	local TrinketDistanceToggle = TrinketsLeftGroup:AddToggle("TrinketDistance", {
		Text = "Distance",
		Default = false,
	})

	TrinketsLeftGroup:AddLabel("Distance Color"):AddColorPicker("TrinketDistanceColor", {
		Default = Color3.new(1, 1, 1),
		Title = "Distance Color",
	})

	local TrinketValueToggle = TrinketsLeftGroup:AddToggle("TrinketValue", {
		Text = "Value",
		Default = false,
	})

	TrinketsLeftGroup:AddLabel("Value Color"):AddColorPicker("TrinketValueColor", {
		Default = Color3.new(1, 1, 1),
		Title = "Value Color",
	})

	local TrinketHighlightToggle = TrinketsLeftGroup:AddToggle("TrinketHighlight", {
		Text = "Highlight",
		Default = false,
	})

	TrinketsLeftGroup:AddLabel("Highlight Fill"):AddColorPicker("TrinketHighlightFill", {
		Default = Color3.new(1, 0, 0),
		Title = "Highlight Fill",
	})

	TrinketsLeftGroup:AddLabel("Highlight Outline"):AddColorPicker("TrinketHighlightOutline", {
		Default = Color3.new(1, 1, 1),
		Title = "Highlight Outline",
	})

	TrinketsLeftGroup:AddSlider("TrinketESPDistance", {
		Text = "Trinket ESP Max Distance",
		Default = 1000,
		Min = 1,
		Max = 1000,
		Rounding = 0,
	})

	-- Auto Grab
	TrinketsRightGroup:AddToggle("TrinketAutoGrab", {
		Text = "Trinket Auto Grab",
		Default = false,
	})

	TrinketsRightGroup:AddSlider("TrinketGrabDistance", {
		Text = "Trinket Auto Grab Max Distance",
		Default = 100,
		Min = 1,
		Max = 100,
		Rounding = 0,
	})

	-- Movement Tab
	local MovementLeftGroup = Tabs.Movement:AddLeftGroupbox("Main")

	local PerfectSlideToggle = MovementLeftGroup:AddToggle("PerfectSlide", {
		Text = "Perfect Slide",
		Default = true,
	})

	PerfectSlideToggle:AddKeyPicker("PerfectSlideKey", {
		Default = "E",
		Mode = "Hold",
		Text = "Perfect Slide Bind",
		NoUI = false,
	})

	-- Settings Tab
	local SettingsLeftGroup = Tabs.Settings:AddLeftGroupbox("Configuration")
	local SettingsRightGroup = Tabs.Settings:AddRightGroupbox("Settings")

	-- Theme buttons
	SettingsLeftGroup:AddLabel("Preset Themes", true)

	local PresetThemes = {
		{ "Default", "Default" },
		{ "Bitchbot", "Bitchbot" },
		{ "Onetap", "Onetap" },
		{ "Aqua", "Aqua" },
		{ "Fent", "Fent" },
	}

	for _, theme in pairs(PresetThemes) do
		SettingsLeftGroup:AddButton({
			Text = "Load " .. theme[1],
			Func = function()
				Library:Notify("Theme loading not implemented in this version", 3)
			end,
		})
	end

	SettingsRightGroup:AddButton({
		Text = "Unload Script",
		Func = function()
			Library:Unload()
			CleanupEverything()
		end,
	})

	-- Set up OnChanged callbacks
	Toggles.AutoParryToggle:OnChanged(function()
		AutoParry.Settings.Enabled = Toggles.AutoParryToggle.Value
	end)

	Options.AutoParryDistance:OnChanged(function()
		AutoParry.Settings.MaxDistance = Options.AutoParryDistance.Value
	end)

	Options.AutoParryPercentage:OnChanged(function()
		AutoParry.Settings.AnimationPercentage = Options.AutoParryPercentage.Value
	end)

	Options.AutoParryPing:OnChanged(function()
		AutoParry.Settings.PingAdjustment = Options.AutoParryPing.Value
	end)

	Toggles.TrinketESP:OnChanged(function()
		TrinketESP.Settings.Enabled = Toggles.TrinketESP.Value
	end)

	Toggles.TrinketName:OnChanged(function()
		TrinketESP.Settings.ShowName = Toggles.TrinketName.Value
	end)

	Toggles.TrinketDistance:OnChanged(function()
		TrinketESP.Settings.ShowDistance = Toggles.TrinketDistance.Value
	end)

	Toggles.TrinketValue:OnChanged(function()
		TrinketESP.Settings.ShowValue = Toggles.TrinketValue.Value
	end)

	Toggles.TrinketHighlight:OnChanged(function()
		TrinketESP.Settings.ShowHighlight = Toggles.TrinketHighlight.Value
	end)

	Options.TrinketESPDistance:OnChanged(function()
		TrinketESP.Settings.MaxDistance = Options.TrinketESPDistance.Value
	end)

	Toggles.TrinketAutoGrab:OnChanged(function()
		TrinketAutograb.Settings.Enabled = Toggles.TrinketAutoGrab.Value
	end)

	Options.TrinketGrabDistance:OnChanged(function()
		TrinketAutograb.Settings.MaxDistance = Options.TrinketGrabDistance.Value
	end)

	Toggles.PerfectSlide:OnChanged(function()
		PerfectSlide.Settings.Enabled = Toggles.PerfectSlide.Value
	end)

	-- Color picker callbacks
	Options.TrinketNameColor:OnChanged(function()
		TrinketESP.Settings.NameColor = Options.TrinketNameColor.Value
		TrinketESP.Settings.NameAlpha = 1 - Options.TrinketNameColor.Transparency
		for _, drawings in pairs(TrinketESP.Drawings) do
			if drawings.Name then
				drawings.Name.Color = Options.TrinketNameColor.Value
				drawings.Name.Transparency = Options.TrinketNameColor.Transparency
			end
		end
	end)

	Options.TrinketDistanceColor:OnChanged(function()
		TrinketESP.Settings.DistanceColor = Options.TrinketDistanceColor.Value
		TrinketESP.Settings.DistanceAlpha = 1 - Options.TrinketDistanceColor.Transparency
		for _, drawings in pairs(TrinketESP.Drawings) do
			if drawings.Distance then
				drawings.Distance.Color = Options.TrinketDistanceColor.Value
				drawings.Distance.Transparency = Options.TrinketDistanceColor.Transparency
			end
		end
	end)

	Options.TrinketValueColor:OnChanged(function()
		TrinketESP.Settings.ValueColor = Options.TrinketValueColor.Value
		TrinketESP.Settings.ValueAlpha = 1 - Options.TrinketValueColor.Transparency
		for _, drawings in pairs(TrinketESP.Drawings) do
			if drawings.Value then
				drawings.Value.Color = Options.TrinketValueColor.Value
				drawings.Value.Transparency = Options.TrinketValueColor.Transparency
			end
		end
	end)

	Options.TrinketHighlightFill:OnChanged(function()
		TrinketESP.Settings.HighlightFillColor = Options.TrinketHighlightFill.Value
		TrinketESP.Settings.HighlightFillAlpha = 1 - Options.TrinketHighlightFill.Transparency
		for _, drawings in pairs(TrinketESP.Drawings) do
			if drawings.Highlight then
				drawings.Highlight.FillColor = Options.TrinketHighlightFill.Value
				drawings.Highlight.FillTransparency = Options.TrinketHighlightFill.Transparency
			end
		end
	end)

	Options.TrinketHighlightOutline:OnChanged(function()
		TrinketESP.Settings.HighlightOutlineColor = Options.TrinketHighlightOutline.Value
		TrinketESP.Settings.HighlightOutlineAlpha = 1 - Options.TrinketHighlightOutline.Transparency
		for _, drawings in pairs(TrinketESP.Drawings) do
			if drawings.Highlight then
				drawings.Highlight.OutlineColor = Options.TrinketHighlightOutline.Value
				drawings.Highlight.OutlineTransparency = Options.TrinketHighlightOutline.Transparency
			end
		end
	end)

	-- Keybind callbacks
	Options.AutoParryKey:OnClick(function()
		Toggles.AutoParryToggle:SetValue(not Toggles.AutoParryToggle.Value)
	end)

	Options.PerfectSlideKey:OnClick(function()
		Toggles.PerfectSlide:SetValue(not Toggles.PerfectSlide.Value)
	end)

	-- Set up menu keybind
	Library.ToggleKeybind = Options.MenuKeybind

	-- Watermark setup
	Library:SetWatermarkVisibility(true)
	local FrameTimer = tick()
	local FrameCounter = 0
	local FPS = 60

	local WatermarkConnection = RunService.RenderStepped:Connect(function()
		FrameCounter = FrameCounter + 1

		if (tick() - FrameTimer) >= 1 then
			FPS = FrameCounter
			FrameTimer = tick()
			FrameCounter = 0
		end

		Library:SetWatermark(("MEOW TUAH | %s fps | %s ms"):format(math.floor(FPS), math.floor(GetPing())))
	end)

	Library:OnUnload(function()
		WatermarkConnection:Disconnect()
		CleanupEverything()
		print("Unloaded!")
		Library.Unloaded = true
	end)

	-- The rest of your functions remain exactly the same...
	-- [All your existing AutoParry, PerfectSlide, TrinketESP, TrinketAutograb functions go here unchanged]

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

	-- Initialize everything
	GetAnimationAllowList()
	PerfectSlide:Initialise()
	TrinketShared:Initialise()
	TrinketESP:Initialise()
	TrinketAutograb:Initialise()

	getgenv().CG2_SCRIPT_LOADED = true
end
