-- Services and Utility
local Services = GetModuleFromRepo("Services.luau")
local Utility = GetModuleFromRepo("Utility.luau")
local UI = GetModuleFromRepo("UI.luau")

-- References
local Workspace = Services.Workspace
local RunService = Services.RunService
local CoreGui = Services.CoreGui
local TextService = Utility.GetService("TextService")
local VirtualInputManager = Services.VirtualInputManager

local Player = Utility.GetPlayer()
local IndexedGetTextSize = Utility.index(TextService, "GetTextSize")
local Camera = Utility.index(Workspace, "CurrentCamera")
local ViewportSize = Utility.index(Camera, "ViewportSize")
local Heartbeat = Utility.index(RunService, "Heartbeat")
local RenderStepped = Utility.index(RunService, "RenderStepped")
local WorldToViewportPoint = Utility.index(Camera, "WorldToViewportPoint")
local SendKeyEvent = Utility.index(VirtualInputManager, "SendKeyEvent")
local FindFirstChild = Utility.FindFirstChild
local FindFirstChildOfClass = Utility.FindFirstChildOfClass
local FindFirstChildWhichIsA = Utility.FindFirstChildWhichIsA
local GetChildren = Utility.GetChildren
local Trinkets = FindFirstChild(Workspace, "Trinkets")

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
		DistanceColor = Color3.new(1, 1, 1),
		ValueColor = Color3.new(1, 1, 1),
		HighlightFillColor = Color3.new(1, 0, 0),
		HighlightOutlineColor = Color3.new(1, 1, 1),
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

local AutoParry = {
	Settings = {
		Enabled = false,
		MaxDistance = 5,
		FillColor = Color3.fromRGB(255, 0, 0),
		OutlineColor = Color3.fromRGB(255, 255, 255),
	},
	State = {
		Connections = {},
		EntityData = {},
	},
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
	table.clear(TrinketShared.Trinkets)
	UI:Notify({
		Title = "Script Unloaded",
		Content = "Script Successfully Unloaded!",
		Duration = 3,
		Icon = "check",
	})
end

function AutoParry:SimulateKeyFromKeyEvents(KeyCode)
	SendKeyEvent(VirtualInputManager, true, KeyCode, false, nil)
	local KeyPressDelay = math.random(0.045, 0.087)
	task.wait(KeyPressDelay)
	SendKeyEvent(VirtualInputManager, false, KeyCode, false, nil)
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

	self.State.Connections.PlayerRemoving = Utility.index(Services.Players, "PlayerRemoving"):Connect(function(player)
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

		self.State.Connections[connectionKey] = Utility.index(animator, "AnimationPlayed"):Connect(function(track)
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

	local humanoidRootPart = FindFirstChild(character, "HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	local markerSignal = Utility.GetMarkerReachedSignal(track, "Pause")
	if markerSignal then
		local markerKey = player.Name .. "_" .. tostring(track) .. "_Marker"
		if self.State.Connections[markerKey] then
			self.State.Connections[markerKey]:Disconnect()
		end

		self.State.Connections[markerKey] = markerSignal:Connect(function()
			self:OnAttackDetected(player, character, track)
		end)

		local stoppedKey = player.Name .. "_" .. tostring(track) .. "_Stopped"
		if self.State.Connections[stoppedKey] then
			self.State.Connections[stoppedKey]:Disconnect()
		end

		self.State.Connections[stoppedKey] = Utility.index(track, "Stopped"):Connect(function()
			if self.State.Connections[markerKey] then
				self.State.Connections[markerKey]:Disconnect()
				self.State.Connections[markerKey] = nil
			end
			if self.State.Connections[stoppedKey] then
				self.State.Connections[stoppedKey]:Disconnect()
				self.State.Connections[stoppedKey] = nil
			end
		end)
	end
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
	print("execd")
end

function AutoParry:ExecuteParry()
	AutoParry:SimulateKeyFromKeyEvents(Enum.KeyCode.F)
end

function AutoParry:Toggle()
	self.Settings.Enabled = not self.Settings.Enabled
	if not self.Settings.Enabled then
		self:ClearTarget()
	end
	print(self.Settings.Enabled)
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

		local Distance = (Trinket.Position - Head.Position).Magnitude
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
		warn("Trinkets folder not found!")
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

UI:Popup({
	Title = "meow tuah (cg2)",
	Icon = "cat",
	Content = "Heiiii :3",
	Buttons = {
		{
			Title = "Meow meow",
			Icon = "bird",
		},
	},
})

local Window = UI:CreateWindow({
	Title = "meow tuah",
	Icon = "cat",
	Author = "grat",
	Folder = "CG2",

	User = {
		Enabled = true,
		Anonymous = false,
		Callback = function() end,
	},
})

Window:EditOpenButton({
	Title = "Open Cult Game 2 UI",
	Icon = "monitor",
	CornerRadius = UDim.new(0, 16),
	StrokeThickness = 2,
	Color = ColorSequence.new(Color3.fromHex("#000000"), Color3.fromHex("#9b9b9b")),
	OnlyMobile = false,
	Enabled = true,
	Draggable = true,
})

Window:OnDestroy(function()
	CleanupEverything()
end)

local function AutoParryTab()
	local AutoParryTab = Window:Tab({
		Title = "Auto Parry",
		Icon = "sword",
		Locked = false,
	})

	AutoParryTab:Keybind({
		Title = "Toggle Auto Parry",
		Desc = "Auto Parry Hotkey",
		Value = "E",
		Flag = "AutoParryKeybind",
		Callback = function(v)
			AutoParry:Toggle()
		end,
	})

	AutoParryTab:Slider({
		Title = "Auto Parry Max Distance",
		Desc = "Max Distance for auto parry to scan for players",
		Step = 0.1,
		Value = { Min = 1, Max = 10, Default = 5 },
		Flag = "AutoParryDistance",
		Callback = function(value)
			AutoParry:SetMaxDistance(tonumber(value))
		end,
	})

	AutoParryTab:Select()
end

local function TrinketTab()
	local TrinketTab = Window:Tab({
		Title = "Trinkets",
		Icon = "crown",
		Locked = false,
	})

	TrinketTab:Section({
		Title = "Trinket ESP Settings",
		TextXAlignment = "Left",
		TextSize = 17,
	})

	TrinketTab:Toggle({
		Title = "Trinket ESP",
		Desc = "Draw ESP to the trinkets.",
		Default = TrinketESP.Settings.Enabled,
		Flag = "TrinketESPEnabled",
		Callback = function(State)
			TrinketESP.Settings.Enabled = State
		end,
	})

	TrinketTab:Toggle({
		Title = "Trinket Name ESP",
		Desc = "Displays the trinkets name.",
		Default = TrinketESP.Settings.ShowName,
		Flag = "TrinketNameESPEnabled",
		Callback = function(State)
			TrinketESP.Settings.ShowName = State
		end,
	})

	TrinketTab:Colorpicker({
		Title = "Name ESP Color",
		Desc = "Trinket Name ESP Color",
		Flag = "TrinketNameESPColor",
		Default = TrinketESP.Settings.NameColor,
		Transparency = 0,
		Locked = false,
		Callback = function(color, transparency)
			TrinketESP.Settings.NameColor = color
			for _, drawings in pairs(TrinketESP.Drawings) do
				if drawings.Name then
					drawings.Name.Color = color
				end
			end
		end,
	})

	TrinketTab:Toggle({
		Title = "Trinket Distance ESP",
		Desc = "Displays the trinkets distance from your character.",
		Flag = "TrinketDistanceESPEnabled",
		Default = TrinketESP.Settings.ShowDistance,
		Callback = function(State)
			TrinketESP.Settings.ShowDistance = State
		end,
	})

	TrinketTab:Colorpicker({
		Title = "Distance ESP Color",
		Desc = "Trinket Distance ESP Color",
		Flag = "TrinketDistanceESPColor",
		Default = TrinketESP.Settings.DistanceColor,
		Transparency = 0,
		Locked = false,
		Callback = function(color)
			TrinketESP.Settings.DistanceColor = color
			for _, drawings in pairs(TrinketESP.Drawings) do
				if drawings.Distance then
					drawings.Distance.Color = color
				end
			end
		end,
	})

	TrinketTab:Toggle({
		Title = "Trinket Value ESP",
		Desc = "Displays the trinkets value.",
		Flag = "TrinketValueESPEnabled",
		Default = TrinketESP.Settings.ShowValue,
		Callback = function(State)
			TrinketESP.Settings.ShowValue = State
		end,
	})

	TrinketTab:Colorpicker({
		Title = "Value ESP Color",
		Desc = "Trinket Value ESP Color",
		Flag = "TrinketValueESPColor",
		Default = TrinketESP.Settings.ValueColor,
		Transparency = 0,
		Locked = false,
		Callback = function(color)
			TrinketESP.Settings.ValueColor = color
			for _, drawings in pairs(TrinketESP.Drawings) do
				if drawings.Value then
					drawings.Value.Color = color
				end
			end
		end,
	})

	TrinketTab:Toggle({
		Title = "Highlight Trinkets",
		Desc = "Adds a highlight instance to the trinkets.",
		Flag = "TrinketHighlightESPEnabled",
		Default = TrinketESP.Settings.ShowHighlight,
		Callback = function(State)
			TrinketESP.Settings.ShowHighlight = State
		end,
	})

	TrinketTab:Colorpicker({
		Title = "Trinket Highlight Fill Color",
		Desc = "The Trinket Highlights Fill Color",
		Flag = "TrinketHighlightESPFillColor",
		Default = TrinketESP.Settings.HighlightFillColor,
		Transparency = 0.5,
		Locked = false,
		Callback = function(color, transparency)
			TrinketESP.Settings.HighlightFillColor = color
			for _, drawings in pairs(TrinketESP.Drawings) do
				if drawings.Highlight then
					drawings.Highlight.FillColor = color
					drawings.Highlight.FillTransparency = transparency
				end
			end
		end,
	})

	TrinketTab:Colorpicker({
		Title = "Trinket Highlight Outline Color",
		Desc = "The Trinket Highlights Outline Color",
		Default = TrinketESP.Settings.HighlightOutlineColor,
		Flag = "TrinketHighlightESPOutlineColor",
		Transparency = 0,
		Locked = false,
		Callback = function(color, transparency)
			TrinketESP.Settings.HighlightOutlineColor = color
			for _, drawings in pairs(TrinketESP.Drawings) do
				if drawings.Highlight then
					drawings.Highlight.OutlineColor = color
					drawings.Highlight.OutlineTransparency = transparency
				end
			end
		end,
	})

	TrinketTab:Slider({
		Title = "Trinket ESP Max Distance",
		Step = 1,
		Value = {
			Min = 1,
			Max = 1500,
			Default = TrinketESP.Settings.MaxDistance,
		},
		Flag = "TrinketESPMaxDistance",
		Callback = function(Value)
			TrinketESP.Settings.MaxDistance = tonumber(Value)
		end,
	})

	TrinketTab:Section({
		Title = "Trinket Auto Pickup",
		TextXAlignment = "Left",
		TextSize = 17,
	})

	TrinketTab:Toggle({
		Title = "Trinket Auto Pick Up",
		Desc = "Auto Pick Up Nearby Trinkets",
		Flag = "TrinketAutoPickUpEnabled",
		Default = TrinketAutograb.Settings.Enabled,
		Callback = function(State)
			TrinketAutograb.Settings.Enabled = State
		end,
	})

	TrinketTab:Slider({
		Title = "Trinket Auto Grab Max Distance",
		Step = 1,
		Value = {
			Min = 1,
			Max = 1500,
			Default = TrinketAutograb.Settings.MaxDistance,
		},
		Flag = "TrinketAutoPickUpMaxDistance",
		Callback = function(Value)
			TrinketAutograb.Settings.MaxDistance = tonumber(Value)
		end,
	})
end

local function SettingsTab()
	local SettingsTab = Window:Tab({
		Title = "Settings",
		Icon = "cog",
		Locked = false,
	})

	SettingsTab:Dropdown({
		Title = "Font Selection",
		Desc = "Choose your font that the esp renders in.",
		Values = { "Monospace", "Plex", "System" },
		Value = "System",
		Flag = "ScriptDrawingFont",
		AllowNone = false,
		Callback = function(option)
			print(option)
			MainScript.Font = option
			TrinketESP:UpdateFontSettings()
		end,
	})

	SettingsTab:Slider({
		Title = "Font Size",
		Step = 0.1,
		Value = { Min = 1, Max = 100, Default = MainScript.TextSize },
		Flag = "ScriptDrawingFontSize",
		Callback = function(Value)
			MainScript.TextSize = tonumber(Value)
			TrinketESP:UpdateFontSettings()
		end,
	})

	SettingsTab:Section({
		Title = "Configurations",
	})

	local ConfigManager = Window.ConfigManager
	local ConfigName = "default"

	local ConfigNameInput = SettingsTab:Input({
		Title = "Config Name",
		Icon = "file-cog",
		Callback = function(value)
			ConfigName = value
		end,
	})

	local AllConfigs = ConfigManager:AllConfigs()
	local DefaultValue = table.find(AllConfigs, ConfigName) and ConfigName or nil

	SettingsTab:Dropdown({
		Title = "All Configs",
		Desc = "Select existing configs",
		Values = AllConfigs,
		Value = DefaultValue,
		Callback = function(value)
			ConfigName = value
			ConfigNameInput:Set(value)
		end,
	})

	SettingsTab:Space()

	SettingsTab:Button({
		Title = "Save Config",
		Icon = "",
		Justify = "Center",
		Callback = function()
			Window.CurrentConfig = ConfigManager:CreateConfig(ConfigName)
			if Window.CurrentConfig:Save() then
				Window:Notify({
					Title = "Config Saved",
					Desc = "Config '" .. ConfigName .. "' saved",
					Icon = "check",
				})
			end
		end,
	})

	SettingsTab:Space()

	SettingsTab:Button({
		Title = "Load Config",
		Icon = "",
		Justify = "Center",
		Callback = function()
			Window.CurrentConfig = ConfigManager:CreateConfig(ConfigName)
			if Window.CurrentConfig:Load() then
				Window:Notify({
					Title = "Config Loaded",
					Desc = "Config '" .. ConfigName .. "' loaded",
					Icon = "refresh-cw",
				})
			end
		end,
	})
end

AutoParryTab()
TrinketTab()
SettingsTab()
TrinketShared:Initialise()
TrinketESP:Initialise()
TrinketAutograb:Initialise()
AutoParry:Initialise()
UI:Notify({
	Title = "Script Loaded",
	Content = "Script Successfully Loaded!",
	Duration = 3,
	Icon = "check",
})
