do
	if getgenv().CG2_SCRIPT_LOADED == true then
		printconsole("Failed to initialise script, please rejoin the game.", Color3.new(1, 0, 0))
		return
	end
	-- Services and Utility
	local Services = GetModuleFromRepo("Services.luau")
	local Utility = GetModuleFromRepo("Utility.luau")
	local UI = GetModuleFromRepo("UI.luau")

	if not Services or not Utility or not UI then
		printconsole("Failed to load meow-tuah", Color3.new(1, 0, 0))
		return
	end

	-- References
	local Workspace = Services.Workspace
	local RunService = Services.RunService
	local CoreGui = Services.CoreGui
	local VirtualInputManager = Services.VirtualInputManager
	local TextService = Utility.GetService("TextService")

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
	local Trinkets = FindFirstChild(Workspace, "Trinkets") or FindFirstChild(Workspace, "TrinketSpawns")

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
		Connections = {},
		_initialized = false,
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
		for _, trash in pairs(getgc(true)) do
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
		if not self.Settings.Enabled then
			for _, Drawings in pairs(self.Drawings) do
				for drawingType, drawingObject in pairs(Drawings) do
					if drawingType == "Highlight" then
						drawingObject.Adornee = nil
					else
						drawingObject.Visible = false
					end
				end
			end
			return
		end

		local Character = Utility.GetCharacter(Player)
		local Head = FindFirstChild(Character, "Head")

		for Trinket, Data in pairs(TrinketShared.Trinkets) do
			local Drawings = TrinketESP.Drawings[Data.ID]
			if not Drawings then
				continue
			end

			if not Data.IsActive then
				for DrawingType, DrawingObject in pairs(Drawings) do
					if DrawingType == "Highlight" then
						DrawingObject.Adornee = nil
					else
						DrawingObject.Visible = false
					end
				end
				continue
			end

			local Position, OnScreen = WorldToScreen(Trinket.Position)
			if not OnScreen then
				for DrawingType, DrawingObject in pairs(Drawings) do
					if DrawingType == "Highlight" then
						DrawingObject.Adornee = nil
					else
						DrawingObject.Visible = false
					end
				end
				continue
			end

			local Distance = (Trinket.Position - Head and Head.Position or Vector3.new(0, 0, 0)).Magnitude
			if Distance > TrinketESP.Settings.MaxDistance then
				for DrawingType, DrawingObject in pairs(Drawings) do
					if DrawingType == "Highlight" then
						DrawingObject.Adornee = nil
					else
						DrawingObject.Visible = false
					end
				end
				continue
			end

			local NameText = Data.Name or "Unknown"
			local DistanceText = string.format("[%dm]", math.floor(Distance))
			local ValueText = tostring(Data.Value) or "N/A"

			local ShowName = Drawings.Name ~= nil and TrinketESP.Settings.ShowName
			local ShowDistance = Drawings.Distance ~= nil and TrinketESP.Settings.ShowDistance
			local ShowValue = Drawings.Value ~= nil and TrinketESP.Settings.ShowValue
			local ShowHighlight = Drawings.Highlight ~= nil and TrinketESP.Settings.ShowHighlight

			local NameWidth, NameHeight = 0, 0
			if ShowName then
				NameWidth, NameHeight = GetTextSize(NameText, Drawings.Name.Size, Drawings.Name.Font)
			end

			local DistWidth, DistHeight = 0, 0
			if ShowDistance then
				DistWidth, DistHeight = GetTextSize(DistanceText, Drawings.Distance.Size, Drawings.Distance.Font)
			end

			local ValueWidth, ValueHeight = 0, 0
			if ShowValue then
				ValueWidth, ValueHeight = GetTextSize(ValueText, Drawings.Value.Size, Drawings.Value.Font)
			end

			local TotalNameWidth = NameWidth
			if ShowDistance then
				TotalNameWidth = TotalNameWidth + DistWidth
			end

			local MaxWidth = ShowValue and math.max(TotalNameWidth, ValueWidth) or TotalNameWidth
			local GroupCenterX = Position.X - (MaxWidth / 2)
			local NameX = GroupCenterX

			local DistanceX = NameX + NameWidth
			local ValueX = GroupCenterX + (MaxWidth - ValueWidth) / 2
			local CenterY = Position.Y - (NameHeight / 2)

			if ShowName then
				Drawings.Name.Text = NameText
				Drawings.Name.Position = Vector2.new(NameX, CenterY)
				Drawings.Name.Visible = true
			else
				if Drawings.Name then
					Drawings.Name.Visible = false
				end
			end

			if ShowDistance then
				Drawings.Distance.Text = DistanceText
				Drawings.Distance.Position = Vector2.new(DistanceX, CenterY)
				Drawings.Distance.Visible = true
			else
				if Drawings.Distance then
					Drawings.Distance.Visible = false
				end
			end

			if ShowValue then
				Drawings.Value.Text = `${ValueText}`
				Drawings.Value.Position = Vector2.new(ValueX, CenterY + NameHeight)
				Drawings.Value.Visible = true
			else
				if Drawings.Value then
					Drawings.Value.Visible = false
				end
			end

			if ShowHighlight then
				Drawings.Highlight.Adornee = Data.Model
			else
				if Drawings.Highlight then
					Drawings.Highlight.Adornee = nil
				end
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

	PerfectSlide:Initialise()
	TrinketShared:Initialise()
	TrinketESP:Initialise()
	TrinketAutograb:Initialise()
	UI:KeybindList()
	getgenv().CG2_SCRIPT_LOADED = true
end
