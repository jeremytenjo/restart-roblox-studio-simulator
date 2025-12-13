import * as vscode from 'vscode'
import { WebSocketServer, WebSocket } from 'ws'

const pacakgeName = '[restart-roblox-studio-simulator]'

type RestartMessage = {
  type: 'restart'
  source: string
  timestamp: number
}

let wss: WebSocketServer | undefined

function broadcast(msg: RestartMessage) {
  if (!wss) {
    return
  }
  const payload = JSON.stringify(msg)

  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload)
    }
  }
}

export function activate(context: vscode.ExtensionContext) {
  const port = 3010

  wss = new WebSocketServer({ port }, () => {
    console.log(`${pacakgeName} WebSocket listening on ws://localhost:${port}`)
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

  const cmd = vscode.commands.registerCommand(
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

  context.subscriptions.push(cmd)

  // Create status bar button
  const statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Right,
    100,
  )
  statusBarItem.command = 'restartRobloxStudioSimulator.restart'
  statusBarItem.text = '$(refresh) Restart Roblox Simulator'
  statusBarItem.tooltip = 'Restart Roblox Studio Simulator'
  statusBarItem.show()
  context.subscriptions.push(statusBarItem)

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
      if (wss) {
        wss.close()
        wss = undefined
      }
    },
  })
}

export function deactivate() {}
