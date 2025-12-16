-- RestartRobloxStudioSimulatorBridgePlugin (runtime harness + WS connect/disconnect buttons)
-- Features:
--   * Toolbar buttons: Connect WS / Disconnect WS
--   * Studio PluginAction (bindable to F2) sends restart over WS
--   * Receives restart over WS (from VS Code) and starts the loop if needed
--   * Harness objects exist only while loop is running (created at start, destroyed at end)

local RunService = game:GetService("RunService")
if not RunService:IsStudio() or not RunService:IsEdit() then
	-- Prevent running in Play server/client DataModels.
	return
end

local StudioTestService = game:GetService("StudioTestService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local HttpService = game:GetService("HttpService")

local HARNESS_VERSION = "3"
local PLUGIN_CONFIG_KEY = "RestartRobloxStudioSimulatorPluginPort"
local PROJECT_CONFIG_KEY = "RestartRobloxStudioSimulatorProjectPort"

-- Load port from project attributes first (per-project), then from persistent plugin storage (global fallback)
local WS_PORT

-- Try to load from project attributes
local projectPort = game:GetAttribute(PROJECT_CONFIG_KEY)
if projectPort then
	WS_PORT = tonumber(projectPort)
else
	-- Fall back to plugin settings
	local success, port = pcall(function()
		return tonumber(plugin:GetSetting(PLUGIN_CONFIG_KEY))
	end)
	if success and port then
		WS_PORT = port
	end
end

local WS_URL = WS_PORT and ("ws://localhost:" .. tostring(WS_PORT)) or nil

----------------------------------------------------------------------
-- Harness installer (created during loop; destroyed after loop ends)
----------------------------------------------------------------------

local function ensureHarness()
	-- RemoteEvent in ReplicatedStorage
	local restartEvent = ReplicatedStorage:FindFirstChild("StudioRestartRequest")
	if not restartEvent then
		restartEvent = Instance.new("RemoteEvent")
		restartEvent.Name = "StudioRestartRequest"
		restartEvent.Parent = ReplicatedStorage
	end
	restartEvent:SetAttribute("CreatedByAutoRestartPlayPlugin", true)
	restartEvent:SetAttribute("HarnessVersion", HARNESS_VERSION)

	-- ServerScript in ServerScriptService (runs in Play server DataModel)
	local serverScript = ServerScriptService:FindFirstChild("StudioTestSessionManager_AutoTest")
	if not serverScript then
		serverScript = Instance.new("Script")
		serverScript.Name = "StudioTestSessionManager_AutoTest"
		serverScript.Parent = ServerScriptService
	end
	serverScript:SetAttribute("CreatedByAutoRestartPlayPlugin", true)
	serverScript:SetAttribute("HarnessVersion", HARNESS_VERSION)

	-- IMPORTANT: This script runs inside the Play session (server DataModel),
	-- so it is allowed to call StudioTestService:EndTest().
	serverScript.Source = string.format(
		[[
-- ServerScriptService/StudioTestSessionManager_AutoTest
-- Auto-installed by RestartRobloxStudioSimulatorBridgePlugin

local RunService = game:GetService("RunService")
local StudioTestService = game:GetService("StudioTestService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

if not RunService:IsStudio() then
	return
end

local restartEvent = ReplicatedStorage:FindFirstChild("StudioRestartRequest")
if not restartEvent or not restartEvent:IsA("RemoteEvent") then
	warn("[StudioTestSessionManager_AutoTest] RemoteEvent 'StudioRestartRequest' not found")
	return
end

local ended = false
local function safeEnd(result)
	if ended then
		return
	end
	ended = true
	StudioTestService:EndTest(result)
end

-- In-game restart via RemoteEvent
restartEvent.OnServerEvent:Connect(function()
	safeEnd("restart")
end)

-- Ensure test ends cleanly even if normal Stop is pressed
game:BindToClose(function()
	safeEnd("stopped")
end)

-- WebSocket client (server DataModel): restart => restart
local WS_URL = %q
local wsClient

local function connect()
	if wsClient then return end

	local ok, clientOrErr = pcall(function()
		return HttpService:CreateWebStreamClient(
			Enum.WebStreamClientType.WebSocket,
			{ Url = WS_URL }
		)
	end)

	if not ok then
		warn("[StudioTestSessionManager_AutoTest] WS create failed:", clientOrErr)
		return
	end

	local client = clientOrErr
	client.Opened:Connect(function()
		print("[StudioTestSessionManager_AutoTest] WS opened:", WS_URL)
	end)

	client.MessageReceived:Connect(function(message)
		print("[StudioTestSessionManager_AutoTest] WS message received:", message)
		local okDecode, decoded = pcall(function()
			return HttpService:JSONDecode(message)
		end)
		if not okDecode or typeof(decoded) ~= "table" then
			return
		end
		if decoded.type == "restart" then
			safeEnd("restart")
		end
	end)

	client.Error:Connect(function(err)
		warn("[StudioTestSessionManager_AutoTest] WS error:", err)
	end)

	wsClient = client
end

connect()
]],
		WS_URL
	)

	-- LocalScript in StarterPlayerScripts: optional in-game hotkey
	local starterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
	local localScript = starterPlayerScripts:FindFirstChild("StudioRestartHotkey_AutoTest")
	if not localScript then
		localScript = Instance.new("LocalScript")
		localScript.Name = "StudioRestartHotkey_AutoTest"
		localScript.Parent = starterPlayerScripts
	end
	localScript:SetAttribute("CreatedByAutoRestartPlayPlugin", true)
	localScript:SetAttribute("HarnessVersion", HARNESS_VERSION)

	localScript.Source = [[
-- StarterPlayerScripts/StudioRestartHotkey_AutoTest
-- Auto-installed by RestartRobloxStudioSimulatorBridgePlugin
-- Press F2 in Play mode to request restart

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local restartEvent = ReplicatedStorage:WaitForChild("StudioRestartRequest")

local RESTART_KEY = Enum.KeyCode.F2

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == RESTART_KEY then
		restartEvent:FireServer()
	end
end)
]]
end

local function cleanupHarness()
	local restartEvent = ReplicatedStorage:FindFirstChild("StudioRestartRequest")
	if restartEvent and restartEvent:GetAttribute("CreatedByAutoRestartPlayPlugin") then
		restartEvent:Destroy()
	end

	local serverScript = ServerScriptService:FindFirstChild("StudioTestSessionManager_AutoTest")
	if serverScript and serverScript:GetAttribute("CreatedByAutoRestartPlayPlugin") then
		serverScript:Destroy()
	end

	local starterPlayerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	if starterPlayerScripts then
		local localScript = starterPlayerScripts:FindFirstChild("StudioRestartHotkey_AutoTest")
		if localScript and localScript:GetAttribute("CreatedByAutoRestartPlayPlugin") then
			localScript:Destroy()
		end
	end
end

local function showNotification(message, duration)
	duration = duration or 2
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "NotificationGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = game:GetService("CoreGui")

	local notificationFrame = Instance.new("Frame")
	notificationFrame.Name = "NotificationFrame"
	notificationFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	notificationFrame.BorderSizePixel = 0
	notificationFrame.Size = UDim2.new(0.4, 0, 0.06, 0)
	notificationFrame.Position = UDim2.new(0.3, 0, 0.02, 0)
	notificationFrame.Parent = screenGui

	local iconLabel = Instance.new("ImageLabel")
	iconLabel.Name = "NotificationIcon"
	iconLabel.Image = "rbxassetid://125030218101854"
	iconLabel.BackgroundTransparency = 1
	iconLabel.Size = UDim2.new(0, 20, 0, 20)
	iconLabel.Position = UDim2.new(0, 10, 0.5, -10)
	iconLabel.Parent = notificationFrame

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "NotificationLabel"
	textLabel.Text = message
	textLabel.TextScaled = false
	textLabel.TextSize = 15
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.BorderSizePixel = 0
	textLabel.Size = UDim2.new(1, -50, 1, 0)
	textLabel.Position = UDim2.new(0, 38, 0, 0)
	textLabel.Parent = notificationFrame

	task.wait(duration)
	screenGui:Destroy()
end

----------------------------------------------------------------------
-- Test loop (edit DataModel only)
----------------------------------------------------------------------

local isLoopRunning = false

local function runLoop()
	if isLoopRunning then
		return
	end
	isLoopRunning = true

	local okHarness, errHarness = pcall(ensureHarness)
	if not okHarness then
		warn("[RestartRobloxStudioSimulatorBridgePlugin] ensureHarness failed:", errHarness)
		isLoopRunning = false
		return
	end

	while true do
		local result
		local okExec, errExec = pcall(function()
			result = StudioTestService:ExecutePlayModeAsync("AutoRestartPlay_Default")
		end)

		if not okExec then
			warn("[RestartRobloxStudioSimulatorBridgePlugin] ExecutePlayModeAsync failed:", errExec)
			break
		end

		if result ~= "restart" then
			break
		end
	end

	-- Remove runtime harness artifacts once we’re back in edit mode
	pcall(cleanupHarness)

	isLoopRunning = false
end

local function restartLocal()
	if not isLoopRunning then
		task.spawn(runLoop)
	else
		-- Restart is handled by the harness server script upon receiving WS message.
		print(
			"[RestartRobloxStudioSimulatorBridgePlugin] Test running; restart will be handled by harness when WS message arrives."
		)
	end
end

----------------------------------------------------------------------
-- WebSocket client in plugin (edit DataModel): connect/disconnect + receive
----------------------------------------------------------------------

local wsClient = nil

local function connectWS()
	print("[RestartRobloxStudioSimulatorBridgePlugin] wsClient", wsClient)
	if wsClient then
		print("[RestartRobloxStudioSimulatorBridgePlugin] WS already created (connected/connecting).")
		return true
	end

	if not WS_PORT then
		warn(
			"[RestartRobloxStudioSimulatorBridgePlugin] WebSocket port not configured. Please use the Settings button to configure it."
		)
		showNotification("Port not configured. Click Settings to set it.", 3)
		return false
	end

	local ok, clientOrErr = pcall(function()
		return HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, { Url = WS_URL })
	end)

	if not ok then
		warn("[RestartRobloxStudioSimulatorBridgePlugin] WS create failed:", clientOrErr)
		showNotification("Failed to connect to VS Code extension", 3)
		return false
	end

	local client = clientOrErr

	client.Opened:Connect(function()
		print("[RestartRobloxStudioSimulatorBridgePlugin] WS opened (plugin):", WS_URL)
	end)

	client.MessageReceived:Connect(function(message)
		print("[RestartRobloxStudioSimulatorBridgePlugin] WS message received (plugin):", message)
		local okDecode, decoded = pcall(function()
			return HttpService:JSONDecode(message)
		end)
		if not okDecode or typeof(decoded) ~= "table" then
			return
		end

		if decoded.type == "restart" then
			restartLocal()
		end
	end)

	client.Error:Connect(function(err)
		warn("[RestartRobloxStudioSimulatorBridgePlugin] WS error (plugin):", err)
		showNotification("WebSocket connection error", 3)
	end)

	wsClient = client
	return true
end

local function disconnectWS()
	if not wsClient then
		print("[RestartRobloxStudioSimulatorBridgePlugin] WS not connected.")
		return
	end
	wsClient:Close()
	wsClient = nil
	print("[RestartRobloxStudioSimulatorBridgePlugin] WS closed (plugin).")
end

local function sendRestart(source)
	-- Ensure we have a WS connection for restart signaling.
	if not wsClient then
		connectWS()
	end

	if wsClient then
		local payload = {
			type = "restart",
			source = source or "studio",
			timestamp = os.time(),
		}

		local okEncode, jsonOrErr = pcall(function()
			return HttpService:JSONEncode(payload)
		end)

		if okEncode then
			wsClient:Send(jsonOrErr)
		else
			warn("[RestartRobloxStudioSimulatorBridgePlugin] JSONEncode failed:", jsonOrErr)
		end
	else
		warn("[RestartRobloxStudioSimulatorBridgePlugin] WS not connected; restart signaling may not work.")
	end

	-- Always start the loop locally if it isn't running yet.
	restartLocal()
end

----------------------------------------------------------------------
-- Configuration UI
----------------------------------------------------------------------

local configWindow = nil

local function createConfigWindow()
	local window = Instance.new("ScreenGui")
	window.Name = "RestartRobloxStudioSimulatorConfig"
	window.ResetOnSpawn = false
	window.DisplayOrder = 999999

	-- Main frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	mainFrame.BorderSizePixel = 1
	mainFrame.BorderColor3 = Color3.fromRGB(60, 60, 60)
	mainFrame.Size = UDim2.new(0, 350, 0, 180)
	mainFrame.Position = UDim2.new(0.5, -175, 0.5, -90)
	mainFrame.Parent = window

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Text = "WebSocket Configuration"
	titleLabel.TextSize = 16
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
	titleLabel.BorderSizePixel = 0
	titleLabel.Size = UDim2.new(1, 0, 0, 30)
	titleLabel.Parent = mainFrame

	-- Port label
	local portLabel = Instance.new("TextLabel")
	portLabel.Name = "PortLabel"
	portLabel.Text = "WebSocket Port:"
	portLabel.TextSize = 13
	portLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	portLabel.BackgroundTransparency = 1
	portLabel.TextXAlignment = Enum.TextXAlignment.Left
	portLabel.Size = UDim2.new(0, 100, 0, 25)
	portLabel.Position = UDim2.new(0, 15, 0, 40)
	portLabel.Parent = mainFrame

	-- Port input
	local portInput = Instance.new("TextBox")
	portInput.Name = "PortInput"
	portInput.Text = WS_PORT and tostring(WS_PORT) or ""
	portInput.PlaceholderText = "e.g., 3010"
	portInput.TextSize = 13
	portInput.TextColor3 = Color3.fromRGB(255, 255, 255)
	portInput.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	portInput.BorderColor3 = Color3.fromRGB(80, 80, 80)
	portInput.BorderSizePixel = 1
	portInput.Size = UDim2.new(0, 150, 0, 25)
	portInput.Position = UDim2.new(0, 15, 0, 65)
	portInput.Parent = mainFrame

	-- Save button
	local saveButton = Instance.new("TextButton")
	saveButton.Name = "SaveButton"
	saveButton.Text = "Save"
	saveButton.TextSize = 12
	saveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	saveButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
	saveButton.BorderSizePixel = 0
	saveButton.Size = UDim2.new(0, 70, 0, 25)
	saveButton.Position = UDim2.new(0, 15, 0, 100)
	saveButton.Parent = mainFrame

	-- Cancel button
	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "CancelButton"
	cancelButton.Text = "Cancel"
	cancelButton.TextSize = 12
	cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	cancelButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
	cancelButton.BorderSizePixel = 0
	cancelButton.Size = UDim2.new(0, 70, 0, 25)
	cancelButton.Position = UDim2.new(0, 95, 0, 100)
	cancelButton.Parent = mainFrame

	-- Status label
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Text = WS_URL and "✓ Connected" or "Port not set"
	statusLabel.TextSize = 11
	statusLabel.TextColor3 = WS_URL and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(200, 100, 100)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, -30, 0, 20)
	statusLabel.Position = UDim2.new(0, 15, 0, 140)
	statusLabel.Parent = mainFrame

	-- Save functionality
	saveButton.MouseButton1Click:Connect(function()
		local input = portInput.Text:match("^%d+$")
		if not input then
			statusLabel.Text = "Invalid port (must be a number)"
			statusLabel.TextColor3 = Color3.fromRGB(200, 100, 100)
			return
		end

		local port = tonumber(input)
		if port < 1024 or port > 65535 then
			statusLabel.Text = "Port must be between 1024-65535"
			statusLabel.TextColor3 = Color3.fromRGB(200, 100, 100)
			return
		end

		-- Save to game attributes (project-specific)
		pcall(function()
			game:SetAttribute(PROJECT_CONFIG_KEY, tostring(port))
		end)

		WS_PORT = port
		WS_URL = "ws://localhost:" .. tostring(WS_PORT)

		statusLabel.Text = "✓ Saved! Port: " .. tostring(WS_PORT)
		statusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)

		-- Close after a brief delay
		task.wait(1)
		window:Destroy()
		configWindow = nil
	end)

	-- Cancel functionality
	cancelButton.MouseButton1Click:Connect(function()
		window:Destroy()
		configWindow = nil
	end)

	return window
end

local function showConfigWindow()
	if configWindow then
		configWindow:Destroy()
	end
	configWindow = createConfigWindow()
	configWindow.Parent = game:GetService("CoreGui")
end

----------------------------------------------------------------------
-- Plugin UI: ONLY connect/disconnect buttons + PluginAction for keybind
----------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("Restart Roblox Studio Simulator Bridge")

local connectButton = toolbar:CreateButton("Connect", "Connect to VS Code extension", "rbxassetid://126561959012757")

local configButton = toolbar:CreateButton("Settings", "Configure WebSocket port", "rbxassetid://102686640342516")

local disconnectButton =
	toolbar:CreateButton("Disconnect", "Disconnect from VS Code extension", "rbxassetid://123998024261090")

connectButton.Click:Connect(function()
	if not WS_PORT then
		showNotification("Port not configured. Click Settings to set it.", 3)
		return
	end
	showNotification("Restart Roblox Studio Simulator: Active", 2)
	connectWS()
end)

configButton.Click:Connect(function()
	showConfigWindow()
end)

disconnectButton.Click:Connect(function()
	if not wsClient then
		if not WS_PORT then
			showNotification("Port not configured. Click Settings to set it.", 3)
		else
			showNotification("Not connected", 2)
		end
		return
	end
	showNotification("Restart Roblox Studio Simulator: Stopped", 2)
	disconnectWS()
end)

-- Keybind entrypoint (bind this action to F2 in Studio)
local runAction = plugin:CreatePluginAction(
	"AutoRestartPlay_Restart",
	"Auto Restart Play - Run or Restart",
	"Start or restart the auto test run (sends WS restart)",
	"",
	true
)

runAction.Triggered:Connect(function()
	sendRestart("studio-action")
end)
