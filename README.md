# Restart Roblox Studio Simulator

![Logo](assets/images/logo.png)

A VS Code extension that enables hot-reload functionality for Roblox game development, allowing you to quickly test and restart your Roblox simulator without manual intervention.

[Demo](https://firebasestorage.googleapis.com/v0/b/portfolio-83749.appspot.com/o/videos%2FCleanShot_2025-12-15_at_18.57.47.mp4?alt=media&token=cdbf3ce5-8a7d-4ef7-9398-6ae3a885a87a)

## Features

- **Auto Reload on Save**: Automatically triggers simulation restart when you save TypeScript, JavaScript, or Lua files
- **Manual Trigger**: Press `F2` to trigger a "run or restart" command for your Roblox simulation -**File Type Filtering**: Intelligently filters supported file types (`.ts`, `.tsx`, `.js`, `.jsx`, `.lua`, `.luau`)
- **Restart Roblox Studio Simulator Management**: Start and stop the WebSocket server on demand via VS Code commands

## Installation

### VS Code Extension

The extension is available on the VS Code Marketplace. Install it like any other extension through the Extensions panel in VS Code.

### Roblox Studio Plugin

You must also install the **Restart Roblox Studio Simulator Bridge Plugin** in Roblox Studio:

1. Open Roblox Studio
2. Go to **Plugins** → **Manage Plugins**
3. Search for "Restart Roblox Simulator Bridge Plugin" or use this direct link:
   - [Install Plugin](https://create.roblox.com/store/asset/136865535235685/Restart-Roblox-Simulator-Bridge-Plugin)
4. Click **Install**

The plugin adds toolbar buttons to connect/disconnect from the VS Code extension and enables the restart functionality.

## Usage

### Manual Trigger

- Press `F2` to send a "run or restart" message to all connected Roblox clients

### Auto Reload

- Simply save a supported file (TypeScript, JavaScript, or Lua) to automatically trigger a restart

### Restart Roblox Studio Simulator Management

You can manage the WebSocket server using VS Code commands (accessible via `Cmd+Shift+P` / `Ctrl+Shift+P`):

- **Restart Roblox Studio Simulator: Start** - Start Restart Roblox Studio Simulator
- **Restart Roblox Studio Simulator: Stop** - Stop Restart Roblox Studio Simulator
- A status bar indicator shows the current Restart Roblox Studio Simulator state (Running/Stopped)

Restart Roblox Studio Simulator starts automatically when the extension is activated.

## Configuration

### Required: Set WebSocket Port

The extension requires an explicit port configuration. Each VS Code instance should use a unique port to support multiple simultaneous Roblox Studio instances. Make sure to assign and use different WebSocket ports for each Roblox project to avoid connection conflicts and ensure proper functionality.

#### In VS Code

Add the WebSocket port to your workspace settings (Keep USER settings at 0) (`.vscode/settings.json`):

```json
{
  "restartRobloxStudioSimulator.websocketPort": 3010
}
```

For multiple workspaces, use different ports:

- Workspace A: "restartRobloxStudioSimulator.websocketPort": 3010
- Workspace B: "restartRobloxStudioSimulator.websocketPort": 3011
- Workspace C: "restartRobloxStudioSimulator.websocketPort": 3012

#### In Roblox Studio Plugin

1. Click the **Plugin's Icon** in the Roblox Studio toolbar
2. Enter the WebSocket port number (must match the port configured in VS Code)
3. Click **Connect** to establish the connection

### Optional: Disable Auto Reload

To disable automatic reloading when files are saved, add the following to your VS Code settings (`.vscode/settings.json`):

```json
{
  "restartRobloxStudioSimulator.disableAutoReload": true
}
```

When enabled, automatic reloading on file save is disabled. You can still use the `F2` keyboard shortcut to manually trigger a reload.

## Development Setup

1. Clone or download this repository
2. Install dependencies:
   ```bash
   npm install
   ```
3. Open the project in VS Code
4. Press `F5` to run the extension with a new Extension Development Host window

## Special Thanks

Special thanks to **zephyras** and **oryaelia** for contributions and feedback!

## License

MIT License - Copyright (c) 2025 Jeremy Tenjo. See [LICENSE](LICENSE) file for details.
