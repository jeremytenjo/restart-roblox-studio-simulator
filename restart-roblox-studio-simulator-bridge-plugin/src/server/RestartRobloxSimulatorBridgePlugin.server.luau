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
local PROJECT_CONFIG_KEY = "RestartRobloxStudioSimulatorProjectPort"

-- Load port from project attributes (per-project only)
local WS_PORT
local projectPort = game:GetAttribute(PROJECT_CONFIG_KEY)
if projectPort then
	WS_PORT = tonumber(projectPort)
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
-- Configuration Widget (Studio theme-aware)
----------------------------------------------------------------------

local configWidget = nil
local themeChangedConnection = nil

-- Helper: Set mouse cursor for interactive elements
local function setCursor(cursorAsset)
	plugin:GetMouse().Icon = cursorAsset
end

-- Helper: Sync GUI colors with Studio theme
local function syncGuiColors(objects, textLabels, textBoxes, buttons)
	local function setColors()
		local theme = settings().Studio.Theme

		-- Sync main background elements
		for _, guiObject in objects do
			guiObject.BackgroundColor3 = theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
		end

		-- Sync text labels
		for _, label in textLabels do
			label.TextColor3 = theme:GetColor(Enum.StudioStyleGuideColor.MainText)
		end

		-- Sync text boxes with input field styling
		for _, textBox in textBoxes do
			textBox.BackgroundColor3 = theme:GetColor(Enum.StudioStyleGuideColor.InputFieldBackground)
			textBox.BorderColor3 = theme:GetColor(Enum.StudioStyleGuideColor.InputFieldBorder)
			textBox.TextColor3 = theme:GetColor(Enum.StudioStyleGuideColor.MainText)
			textBox.PlaceholderColor3 = theme:GetColor(Enum.StudioStyleGuideColor.DimmedText)
		end

		-- Sync buttons with button styling
		for _, button in buttons do
			if button:GetAttribute("ButtonType") == "Primary" then
				button.BackgroundColor3 = theme:GetColor(Enum.StudioStyleGuideColor.DialogMainButton)
				button.TextColor3 = theme:GetColor(Enum.StudioStyleGuideColor.DialogMainButtonText)
			else
				button.BackgroundColor3 = theme:GetColor(Enum.StudioStyleGuideColor.DialogButton)
				button.TextColor3 = theme:GetColor(Enum.StudioStyleGuideColor.DialogButtonText)
			end
		end
	end

	-- Run initially
	setColors()

	-- Connect to theme changes
	return settings().Studio.ThemeChanged:Connect(setColors)
end

-- Helper: Add hover cursor to interactive element
local function addHoverCursor(guiObject, cursorType)
	cursorType = cursorType or "rbxasset://SystemCursors/PointingHand"

	guiObject.MouseEnter:Connect(function()
		setCursor(cursorType)
	end)

	guiObject.MouseLeave:Connect(function()
		setCursor("")
	end)
end

local function createConfigWidget()
	-- Widget info: don't override previous enabled state (false for InitialEnabledShouldOverrideRestore)
	local widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float, -- Floating panel
		true, -- Initially enabled
		false, -- Don't override previous enabled state
		350, -- Default width
		220, -- Default height
		300, -- Minimum width
		200 -- Minimum height
	)

	local widget = plugin:CreateDockWidgetPluginGui("RestartRobloxStudioSimulatorSettings", widgetInfo)
	widget.Title = "Simulator Settings"

	-- Collections for theme syncing
	local backgroundObjects = {}
	local textLabels = {}
	local textBoxes = {}
	local buttons = {}

	-- Main frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.BorderSizePixel = 0
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.Parent = widget
	table.insert(backgroundObjects, mainFrame)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 15)
	padding.PaddingRight = UDim.new(0, 15)
	padding.PaddingTop = UDim.new(0, 15)
	padding.PaddingBottom = UDim.new(0, 15)
	padding.Parent = mainFrame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = mainFrame

	-- Port label
	local portLabel = Instance.new("TextLabel")
	portLabel.Name = "PortLabel"
	portLabel.Text = "WebSocket Port:"
	portLabel.TextSize = 13
	portLabel.BackgroundTransparency = 1
	portLabel.TextXAlignment = Enum.TextXAlignment.Left
	portLabel.Size = UDim2.new(1, 0, 0, 20)
	portLabel.LayoutOrder = 1
	portLabel.Parent = mainFrame
	table.insert(textLabels, portLabel)

	-- Port input
	local connectdPort = game:GetAttribute(PROJECT_CONFIG_KEY) or ""
	local portInput = Instance.new("TextBox")
	portInput.Name = "PortInput"
	portInput.Text = connectdPort
	portInput.PlaceholderText = "e.g., 3010"
	portInput.TextSize = 13
	portInput.BorderSizePixel = 1
	portInput.Size = UDim2.new(1, 0, 0, 25)
	portInput.LayoutOrder = 2
	portInput.ClearTextOnFocus = false
	portInput.Parent = mainFrame
	table.insert(textBoxes, portInput)

	-- Add I-beam cursor for text input
	addHoverCursor(portInput, "rbxasset://SystemCursors/IBeam")

	-- Button container
	local buttonContainer = Instance.new("Frame")
	buttonContainer.Name = "ButtonContainer"
	buttonContainer.BackgroundTransparency = 1
	buttonContainer.Size = UDim2.new(1, 0, 0, 30)
	buttonContainer.LayoutOrder = 3
	buttonContainer.Parent = mainFrame

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.Padding = UDim.new(0, 10)
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Parent = buttonContainer

	-- Connect button (Primary)
	local connectButton = Instance.new("TextButton")
	connectButton.Name = "ConnectButton"
	connectButton.Text = "Connect"
	connectButton.TextSize = 12
	connectButton.BorderSizePixel = 0
	connectButton.Size = UDim2.new(0.5, -5, 1, 0)
	connectButton.LayoutOrder = 1
	connectButton.AutoButtonColor = true
	connectButton:SetAttribute("ButtonType", "Primary")
	connectButton.Parent = buttonContainer
	table.insert(buttons, connectButton)
	addHoverCursor(connectButton)

	-- Disconnect button (Secondary)
	local disconnectButton = Instance.new("TextButton")
	disconnectButton.Name = "DisconnectButton"
	disconnectButton.Text = "Disconnect"
	disconnectButton.TextSize = 12
	disconnectButton.BorderSizePixel = 0
	disconnectButton.Size = UDim2.new(0.5, -5, 1, 0)
	disconnectButton.LayoutOrder = 2
	disconnectButton.AutoButtonColor = true
	disconnectButton:SetAttribute("ButtonType", "Secondary")
	disconnectButton.Parent = buttonContainer
	table.insert(buttons, disconnectButton)
	addHoverCursor(disconnectButton)

	-- Status label
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.TextSize = 11
	statusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Size = UDim2.new(1, 0, 0, 20)
	statusLabel.LayoutOrder = 4
	statusLabel.Visible = false -- Hidden by default, only show when connected
	statusLabel.Parent = mainFrame
	-- Note: statusLabel not added to textLabels as it has custom coloring

	-- Sync colors with Studio theme
	themeChangedConnection = syncGuiColors(backgroundObjects, textLabels, textBoxes, buttons)

	-- Save functionality
	connectButton.MouseButton1Click:Connect(function()
		local input = portInput.Text:match("^%d+$")
		if not input then
			statusLabel.Text = "Invalid port (must be a number)"
			statusLabel.TextColor3 = Color3.fromRGB(200, 100, 100)
			statusLabel.Visible = true
			return
		end

		local port = tonumber(input)
		if port < 1024 or port > 65535 then
			statusLabel.Text = "Port must be between 1024-65535"
			statusLabel.TextColor3 = Color3.fromRGB(200, 100, 100)
			statusLabel.Visible = true
			return
		end

		-- Save to game attributes (project-specific)
		pcall(function()
			game:SetAttribute(PROJECT_CONFIG_KEY, tostring(port))
		end)

		WS_PORT = port
		WS_URL = "ws://localhost:" .. tostring(WS_PORT)

		-- Try to connect with the new port
		task.wait(0.5)
		local connected = connectWS()

		-- Only show success message if actually connected
		if connected then
			statusLabel.Text = "✓ Connected to Port: " .. tostring(WS_PORT)
			statusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
			statusLabel.Visible = true
			disconnectButton.Enabled = true

			task.wait(1)
			widget.Enabled = false
		end
		-- If connection failed, error notification is already shown by connectWS()
	end)

	-- Disconnect functionality
	disconnectButton.MouseButton1Click:Connect(function()
		disconnectWS()
		statusLabel.Visible = false
		widget.Enabled = false
	end)

	return widget
end

local function showConfigWidget()
	if configWidget then
		configWidget.Enabled = not configWidget.Enabled
	else
		configWidget = createConfigWidget()
	end
end

----------------------------------------------------------------------
-- Plugin UI: ONLY connect/disconnect buttons + PluginAction for keybind
----------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("Restart Roblox Studio Simulator Bridge")

local configButton = toolbar:CreateButton("RRSB", "Configure WebSocket port", "rbxassetid://119133411556984")

configButton.Click:Connect(function()
	showConfigWidget()
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
