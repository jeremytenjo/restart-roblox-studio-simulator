# Roblox Studio Simulation Hot Reload

A VS Code extension that enables hot-reload functionality for Roblox game development, allowing you to quickly test and restart your Roblox simulations without manual intervention.

## Features

- **WebSocket Server Integration**: Runs a WebSocket server (port 3010) for real-time communication with Roblox clients
- **Manual Trigger**: Press `F2` to trigger a "run or restart" command for your Roblox simulation
- **Auto Reload on Save**: Automatically triggers simulation restart when you save TypeScript, JavaScript, or Lua files
- **File Type Filtering**: Intelligently filters supported file types (`.ts`, `.tsx`, `.js`, `.jsx`, `.lua`, `.luau`)

## Installation

1. Clone or download this repository
2. Install dependencies:
   ```bash
   npm install
   ```
3. Open the project in VS Code
4. Press `F5` to run the extension in a new VS Code window

## Usage

### Manual Trigger

- Press `F2` to send a "run or restart" message to all connected Roblox clients

### Auto Reload

- Simply save a supported file (TypeScript, JavaScript, or Lua) to automatically trigger a restart

### WebSocket Connection

Connect your Roblox client to the WebSocket server at `ws://localhost:3010` to receive hot-reload messages.

## Development

### Build Commands

- **Watch TypeScript**: `npm run watch:tsc`
- **Watch esbuild**: `npm run watch:esbuild`
- **Full watch**: `npm run watch`
- **Compile**: `npm run compile`

### Project Structure

```
├── src/
│   └── extension.ts       # Main extension entry point
├── package.json           # Project manifest
├── tsconfig.json          # TypeScript configuration
├── esbuild.js            # Build configuration
└── README.md             # This file
```

## Configuration

- **WebSocket Port**: 3010 (configured in `src/extension.ts`)
- **Activation Event**: Activates on VS Code startup (`onStartupFinished`)

## Message Protocol

The extension broadcasts messages with the following structure:

```typescript
{
  type: 'runOrRestart',
  source: 'vscode' | 'vscode-autosave' | 'roblox',
  timestamp: number
}
```

## Dependencies

- `ws` (8.18.3) - WebSocket library for Node.js
- VS Code 1.107.0 or later

## Special Thanks

Special thanks to **zephyras** for contributions and feedback!

## License

Unlicensed - This project is provided as-is.
