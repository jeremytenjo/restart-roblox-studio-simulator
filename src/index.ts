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
  })

  if (!wss) {
    console.log(
      `${pacakgeName}: WebSocket server is not running, cannot broadcast message`,
    )

    return
  }

  if (wss.clients.size === 0) {
    console.log(`${pacakgeName}: No clients connected, skipping broadcast`)
    return
  }

  const payload = JSON.stringify(msg)

  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload)
    }
  }
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
    vscode.window.showWarningMessage(
      'Restart Roblox Studio Simuluator: WebSocket is already running',
    )
    return
  }

  wss = new WebSocketServer({ port }, () => {
    console.log(`${pacakgeName} WebSocket listening on ws://localhost:${port}`)
    if (!p.dontShowInformationMessage) {
      vscode.window.showInformationMessage('Restart Roblox Studio Simuluator is active')
    }
    updateWebSocketStatusBar()
  })

  wss.on('connection', (socket: WebSocket) => {
    console.log(`${pacakgeName} client connected`)

    socket.on('close', () => {
      console.log(`${pacakgeName} client disconnected`)
    })

    socket.on('message', (data) => {
      try {
        const parsed = JSON.parse(data.toString())
        if (parsed && parsed.type === 'restart') {
          const msg: RestartMessage = {
            type: 'restart',
            source: parsed.source ?? 'roblox',
            timestamp: Date.now(),
          }
          broadcast(msg)
        }
      } catch {
        // ignore malformed messages
      }
    })
  })
}

function stopWebSocket() {
  if (!wss) {
    vscode.window.showWarningMessage(
      'Restart Roblox Studio Simuluator: WebSocket is not running',
    )
    return
  }

  wss.close()
  wss = undefined
  vscode.window.showInformationMessage('Restart Roblox Studio Simuluator stopped')
  updateWebSocketStatusBar()
}

export function activate(context: vscode.ExtensionContext) {
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
    if (doc.fileName.match(/\.(ts|tsx|js|jsx|lua|luau)$/)) {
      const msg: RestartMessage = {
        type: 'restart',
        source: 'vscode-autosave',
        timestamp: Date.now(),
      }
      broadcast(msg)
      console.log(`${pacakgeName} triggered by file save: ${doc.fileName}`)
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
