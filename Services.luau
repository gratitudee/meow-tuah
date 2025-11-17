-- Service Module
--local utility = require("./Utility.luau")
local utility = loadfile("ESPShit/src/modules/Utility.luau")()
local serviceCache = {}

local function getService(serviceName: string): Instance
	if not serviceCache[serviceName] then
		serviceCache[serviceName] = utility.GetService(serviceName)
	end
	return serviceCache[serviceName]
end

return {
	Players = getService("Players") :: Players,
	Workspace = getService("Workspace") :: Workspace,
	UserInputService = getService("UserInputService") :: UserInputService,
	ReplicatedStorage = getService("ReplicatedStorage") :: ReplicatedStorage,
	Lighting = getService("Lighting") :: Lighting,
	RunService = getService("RunService") :: RunService,
	HttpService = getService("HttpService") :: HttpService,
	CoreGui = getService("CoreGui") :: CoreGui,
	TweenService = getService("TweenService") :: TweenService,
	VirtualInputManager = getService("VirtualInputManager") :: VirtualInputManager,
}
