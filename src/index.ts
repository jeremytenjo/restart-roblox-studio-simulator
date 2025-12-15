import * as vscode from 'vscode'
import { WebSocketServer, WebSocket } from 'ws'

const pacakgeName = '[restart-roblox-studio-simulator]'

type RestartMessage = {
  type: 'restart'
  source: string
  timestamp: number
}

let wss: WebSocketServer | undefined
let wsStatusBarItem: vscode.StatusBarItem | undefined
const port = 3010

function broadcast(msg: RestartMessage) {
  console.log(`${pacakgeName}: Broadcasting`, {
    msg,
    wss,
    clientCount: wss?.clients.size ?? 0,
  })

  if (!wss) {
    console.log(
      `${pacakgeName}: WebSocket server is not running, cannot broadcast message`,
    )
    console.log(`${pacakgeName}: Make sure the Roblox plugin is running and connected`)
    return
  }

  if (wss.clients.size === 0) {
    console.warn(`${pacakgeName}: ⚠️  No clients connected, skipping broadcast`)
    console.warn(
      `${pacakgeName}: Expected a connection from Roblox Studio Plugin on ws://localhost:${port}`,
    )
    console.warn(`${pacakgeName}: Debugging steps:`)
    console.warn(`  1. Check if Roblox Studio is running`)
    console.warn(`  2. Click the 'Connect' button in Roblox Studio toolbar`)
    console.warn(`  3. Check Roblox Studio Output panel for errors`)
    console.warn(`  4. Verify port ${port} is not blocked by firewall`)
    return
  }

  const payload = JSON.stringify(msg)
  console.log(`${pacakgeName}: Sending to ${wss.clients.size} client(s): ${payload}`)

  let sentCount = 0
  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      try {
        client.send(payload)
        sentCount++
      } catch (err) {
        console.error(`${pacakgeName}: Failed to send to client:`, err)
      }
    } else {
      console.warn(`${pacakgeName}: Client in state ${client.readyState}, skipping`)
    }
  }
  console.log(
    `${pacakgeName}: Successfully sent to ${sentCount}/${wss.clients.size} clients`,
  )
}

function updateWebSocketStatusBar() {
  if (!wsStatusBarItem) return

  if (wss) {
    wsStatusBarItem.text = '$(debug-disconnect) WebSocket Running'
    wsStatusBarItem.backgroundColor = new vscode.ThemeColor(
      'statusBarItem.successBackground',
    )
  } else {
    wsStatusBarItem.text = '$(debug-disconnect) WebSocket Stopped'
    wsStatusBarItem.backgroundColor = undefined
  }
}

function startWebSocket(p: { dontShowInformationMessage?: boolean } = {}) {
  if (wss) {
    console.warn(`${pacakgeName}: WebSocket already running on ws://localhost:${port}`)
    vscode.window.showWarningMessage(
      'Restart Roblox Studio Simuluator: WebSocket is already running',
    )
    return
  }

  console.log(`${pacakgeName}: Starting WebSocket server on port ${port}...`)

  wss = new WebSocketServer({ port }, () => {
    console.log(`${pacakgeName} ✓ WebSocket listening on ws://localhost:${port}`)
    console.log(`${pacakgeName} ℹ️  Waiting for Roblox Studio Plugin to connect...`)
    if (!p.dontShowInformationMessage) {
      vscode.window.showInformationMessage('Restart Roblox Studio Simuluator is active')
    }
    updateWebSocketStatusBar()
  })

  wss.on('error', (err) => {
    console.error(`${pacakgeName}: WebSocket server error:`, err)
    if ((err as any).code === 'EADDRINUSE') {
      console.error(`${pacakgeName}: ⚠️  Port ${port} is already in use!`)
      console.error(
        `${pacakgeName}: Try closing other applications or restarting VS Code`,
      )
    }
    vscode.window.showErrorMessage(`WebSocket error: ${(err as any).message}`)
  })

  wss.on('connection', (socket: WebSocket, req) => {
    const clientIp = req?.socket?.remoteAddress ?? 'unknown'
    console.log(`${pacakgeName}: ✓ Client connected from ${clientIp}`)
    console.log(`${pacakgeName}: Total clients: ${wss?.clients.size}`)

    socket.on('close', (code, reason) => {
      console.log(
        `${pacakgeName}: Client disconnected (code: ${code}, reason: ${reason})`,
      )
      console.log(`${pacakgeName}: Remaining clients: ${wss?.clients.size}`)
    })

    socket.on('error', (err) => {
      console.error(`${pacakgeName}: Socket error:`, err)
    })

    socket.on('message', (data) => {
      try {
        const message = data.toString()
        console.log(`${pacakgeName}: Received message from ${clientIp}: ${message}`)

        const parsed = JSON.parse(message)
        console.log(`${pacakgeName}: Parsed message:`, parsed)

        if (parsed && parsed.type === 'restart') {
          console.log(`${pacakgeName}: ✓ Valid restart message from ${parsed.source}`)
          const msg: RestartMessage = {
            type: 'restart',
            source: parsed.source ?? 'roblox',
            timestamp: Date.now(),
          }
          broadcast(msg)
        } else {
          console.warn(`${pacakgeName}: Unknown message type: ${parsed?.type}`)
        }
      } catch (err) {
        console.error(`${pacakgeName}: Failed to parse message:`, err)
        console.error(`${pacakgeName}: Raw data: ${data.toString()}`)
      }
    })
  })
}

function stopWebSocket() {
  if (!wss) {
    console.warn(`${pacakgeName}: WebSocket is not running`)
    vscode.window.showWarningMessage(
      'Restart Roblox Studio Simuluator: WebSocket is not running',
    )
    return
  }

  console.log(
    `${pacakgeName}: Stopping WebSocket server (${wss.clients.size} clients connected)`,
  )
  wss.close(() => {
    console.log(`${pacakgeName}: ✓ WebSocket server closed`)
  })
  wss = undefined
  vscode.window.showInformationMessage('Restart Roblox Studio Simuluator stopped')
  updateWebSocketStatusBar()
}

export function activate(context: vscode.ExtensionContext) {
  console.log(`${pacakgeName}: Extension activated`)

  // Start WebSocket on activation
  startWebSocket({
    dontShowInformationMessage: true,
  })

  // Register start command
  const startCmd = vscode.commands.registerCommand(
    'restartRobloxStudioSimulator.startWebSocket',
    () => {
      startWebSocket()
    },
  )
  context.subscriptions.push(startCmd)

  // Register stop command
  const stopCmd = vscode.commands.registerCommand(
    'restartRobloxStudioSimulator.stopWebSocket',
    () => {
      stopWebSocket()
    },
  )
  context.subscriptions.push(stopCmd)

  // Register restart command
  const restartCmd = vscode.commands.registerCommand(
    'restartRobloxStudioSimulator.restart',
    () => {
      console.log(`${pacakgeName}: Restart command triggered from VS Code`)
      const msg: RestartMessage = {
        type: 'restart',
        source: 'vscode',
        timestamp: Date.now(),
      }
      broadcast(msg)
      vscode.window.showInformationMessage('Requested Roblox Studio Simulator Restart')
    },
  )
  context.subscriptions.push(restartCmd)

  // Create status bar button for restart
  const restartStatusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Right,
    100,
  )
  restartStatusBarItem.command = 'restartRobloxStudioSimulator.restart'
  restartStatusBarItem.text = '$(refresh) Restart Roblox Studio Simulator'
  restartStatusBarItem.tooltip = 'Restart Roblox Studio Simulator'
  restartStatusBarItem.show()
  context.subscriptions.push(restartStatusBarItem)

  // Create status bar button for WebSocket status
  wsStatusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 99)
  wsStatusBarItem.text = '$(debug-disconnect) WebSocket Running'
  wsStatusBarItem.tooltip = 'Click to stop WebSocket'
  wsStatusBarItem.command = 'restartRobloxStudioSimulator.stopWebSocket'
  wsStatusBarItem.show()
  context.subscriptions.push(wsStatusBarItem)
  updateWebSocketStatusBar()

  // Trigger on file save
  const onSaveDisposable = vscode.workspace.onDidSaveTextDocument((doc) => {
    const disableAutoReload = vscode.workspace
      .getConfiguration('restartRobloxStudioSimulator')
      .get('disableAutoReload', false)

    if (disableAutoReload) {
      return
    }

    // Optional: filter by file pattern (e.g., only TypeScript/Lua files)
    if (doc.fileName.match(/\.(ts|tsx|js|jsx|lua|luau|json)$/)) {
      console.log(`${pacakgeName}: File saved: ${doc.fileName}`)
      const msg: RestartMessage = {
        type: 'restart',
        source: 'vscode-autosave',
        timestamp: Date.now(),
      }
      broadcast(msg)
    }
  })

  context.subscriptions.push(onSaveDisposable)

  context.subscriptions.push({
    dispose() {
      stopWebSocket()
    },
  })
}

export function deactivate() {}
