-- Utility Module

local INV_PHI = (math.sqrt(5) - 1) / 2
local MAX_COLOR_ATTEMPTS = 100
local MAX_USED_HUES = 20

LPH_NO_VIRTUALIZE = function(f)
	return f
end

local animator = Instance.new("Animator")
local ghostanim = Instance.new("Animation")
ghostanim.AnimationId = "rbxassetid://0"
local ghosttrack = animator:LoadAnimation(ghostanim)

local utility = {}
local toggledFunctions = {}
local usedHues = {}
local colorCache = {}

local rawDatamodel = getrawmetatable and getrawmetatable(game)
	or {
		__index = LPH_NO_VIRTUALIZE(function(self, Index)
			return self[Index]
		end),
		__newindex = LPH_NO_VIRTUALIZE(function(self, Index, Value)
			self[Index] = Value
		end),
	}

-- Cached game methods
utility.index = rawDatamodel.__index
utility.newindex = rawDatamodel.__newindex
utility._GetService = utility.index(game, "GetService")
utility.GetChildren = utility.index(game, "GetChildren")
utility.FindFirstChild = utility.index(game, "FindFirstChild")
utility.FindFirstChildOfClass = utility.index(game, "FindFirstChildOfClass")
utility.FindFirstChildWhichIsA = utility.index(game, "FindFirstChildWhichIsA")
utility.WaitForChild = utility.index(game, "WaitForChild")
utility.GetMarkerReachedSignal = utility.index(ghosttrack, "GetMarkerReachedSignal")

function utility.GetService(service: string): Instance
	local result = utility._GetService(game, service)
	return cloneref and cloneref(result) or result
end

function utility.generateUniqueColor(filterName: string?): Color3
	if filterName and colorCache[filterName] then
		return colorCache[filterName]
	end

	local hue = (math.random() + INV_PHI) % 1

	for attempt = 1, MAX_COLOR_ATTEMPTS do
		local unique = true

		for _, usedHue in ipairs(usedHues) do
			if math.abs(hue - usedHue) < 0.1 then
				unique = false
				break
			end
		end

		if unique then
			break
		end

		hue = (hue + INV_PHI) % 1

		if attempt == MAX_COLOR_ATTEMPTS then
			table.clear(usedHues)
		end
	end

	table.insert(usedHues, hue)

	if #usedHues > MAX_USED_HUES then
		table.remove(usedHues, 1)
	end

	local saturation, value = 0.8, 0.9
	local i, f = math.floor(hue * 6), hue * 6 % 1
	local p, q, t = value * (1 - saturation), value * (1 - f * saturation), value * (1 - (1 - f) * saturation)

	local r, g, b =
		(i % 6 == 0 and value or i % 6 == 1 and q or i % 6 == 2 and p or i % 6 == 3 and p or i % 6 == 4 and t or value),
		(i % 6 == 0 and t or i % 6 == 1 and value or i % 6 == 2 and value or i % 6 == 3 and q or i % 6 == 4 and p or p),
		(i % 6 == 0 and p or i % 6 == 1 and p or i % 6 == 2 and t or i % 6 == 3 and value or i % 6 == 4 and value or q)

	local color = Color3.new(r, g, b)

	if filterName then
		colorCache[filterName] = color
	end

	return color
end

-- Player utilities
function utility.GetPlayer(): Player?
	local success, result = pcall(function()
		return utility.GetService("Players")
	end)

	return success and utility.index(result, "LocalPlayer")
end

function utility.GetCharacter(player: Player?): Model?
	local success, result = pcall(function()
		return player and utility.index(player, "Character")
	end)

	return success and result
end

function utility.GetHumanoid(player: Player?): Humanoid?
	local success, result = pcall(function()
		local character = utility.GetCharacter(player)
		return character and utility.FindFirstChildOfClass(character, "Humanoid")
	end)

	return success and result
end

-- Function management
function utility.BlankFunction(tbl: { [any]: any }, method: string, override: (...any) -> any, value: boolean)
	assert(typeof(tbl) == "table", "First argument must be a table")
	assert(typeof(method) == "string", "Second argument must be the method name")

	if value == false then
		if not toggledFunctions[tbl] then
			toggledFunctions[tbl] = {}
		end

		if not toggledFunctions[tbl][method] then
			toggledFunctions[tbl][method] = tbl[method]
		end

		tbl[method] = override
	else
		if toggledFunctions[tbl] and toggledFunctions[tbl][method] then
			tbl[method] = toggledFunctions[tbl][method]
			toggledFunctions[tbl][method] = nil
		end
	end
end

return utility
