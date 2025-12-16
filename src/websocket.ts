import { WebSocketServer, WebSocket } from 'ws'
import * as vscode from 'vscode'

import { setupWebSocketSocketHandlers } from './handlers/websocket.js'
import { PACKAGE_NAME, vsCodePluginName } from './constants.js'
import assertWebsocketPortConfig from './utils/assertWebsocketPortConfig.js'

export function getWebSocketPort(): number | undefined {
  const config = vscode.workspace.getConfiguration(vsCodePluginName)
  return config.get<number>('websocketPort')
}

type RestartMessage = {
  type: 'restart'
  source: string
  timestamp: number
}

let wss: WebSocketServer | undefined
let wsStatusBarItem: vscode.StatusBarItem | undefined

export function getWss() {
  return wss
}

export function setWss(server: WebSocketServer | undefined) {
  wss = server
}

export function getWsStatusBarItem() {
  return wsStatusBarItem
}

export function setWsStatusBarItem(item: vscode.StatusBarItem | undefined) {
  wsStatusBarItem = item
}

export function broadcast(msg: RestartMessage) {
  console.log(`${PACKAGE_NAME}: Broadcasting`, {
    msg,
    wss,
    clientCount: wss?.clients.size ?? 0,
  })

  if (!wss) {
    console.log(
      `${PACKAGE_NAME}: WebSocket server is not running, cannot broadcast message`,
    )
    console.log(`${PACKAGE_NAME}: Make sure the Roblox plugin is running and connected`)
    return
  }

  if (wss.clients.size === 0) {
    console.warn(`${PACKAGE_NAME}: ⚠️  No clients connected, skipping broadcast`)
    const port = getWebSocketPort()
    const portStr = port ? `:${port}` : '(not configured)'
    console.warn(
      `${PACKAGE_NAME}: Expected a connection from Roblox Studio Plugin on ws://localhost${portStr}`,
    )
    console.warn(`${PACKAGE_NAME}: Debugging steps:`)
    console.warn(`  1. Check if Roblox Studio is running`)
    console.warn(`  2. Click the 'Connect' button in Roblox Studio toolbar`)
    console.warn(`  3. Check Roblox Studio Output panel for errors`)
    if (port) {
      console.warn(`  4. Verify port ${port} is not blocked by firewall`)
    }
    return
  }

  const payload = JSON.stringify(msg)
  console.log(`${PACKAGE_NAME}: Sending to ${wss.clients.size} client(s): ${payload}`)

  let sentCount = 0
  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      try {
        client.send(payload)
        sentCount++
      } catch (err) {
        console.error(`${PACKAGE_NAME}: Failed to send to client:`, err)
      }
    } else {
      console.warn(`${PACKAGE_NAME}: Client in state ${client.readyState}, skipping`)
    }
  }
  console.log(
    `${PACKAGE_NAME}: Successfully sent to ${sentCount}/${wss.clients.size} clients`,
  )
}

export function updateWebSocketStatusBar() {
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

export function startWebSocket(p: { dontShowInformationMessage?: boolean } = {}) {
  const port = getWebSocketPort()

  if (!port) {
    if (!p.dontShowInformationMessage) {
      assertWebsocketPortConfig()
    }
    return
  }

  console.log(`${PACKAGE_NAME}: Starting WebSocket server on port ${port}...`)

  wss = new WebSocketServer({ port }, () => {
    console.log(`${PACKAGE_NAME} ✓ WebSocket listening on ws://localhost:${port}`)
    console.log(`${PACKAGE_NAME} ℹ️  Waiting for Roblox Studio Plugin to connect...`)
    if (!p.dontShowInformationMessage) {
      vscode.window.showInformationMessage('Restart Roblox Studio Simuluator is active')
    }
    updateWebSocketStatusBar()
  })

  wss.on('error', (err) => {
    console.error(`${PACKAGE_NAME}: WebSocket server error:`, err)
    if ((err as any).code === 'EADDRINUSE') {
      console.error(`${PACKAGE_NAME}: ⚠️  Port ${port} is already in use!`)
      console.error(
        `${PACKAGE_NAME}: Try closing other applications or restarting VS Code`,
      )
    }
    vscode.window.showErrorMessage(`WebSocket error: ${(err as any).message}`)
  })

  wss.on('connection', (socket: WebSocket, req) => {
    const clientIp = req?.socket?.remoteAddress ?? 'unknown'
    console.log(`${PACKAGE_NAME}: ✓ Client connected from ${clientIp}`)
    console.log(`${PACKAGE_NAME}: Total clients: ${wss?.clients.size}`)

    setupWebSocketSocketHandlers(socket, clientIp)
  })
}

export function stopWebSocket() {
  if (!wss) {
    console.warn(`${PACKAGE_NAME}: WebSocket is not running`)
    vscode.window.showWarningMessage(
      'Restart Roblox Studio Simuluator: WebSocket is not running',
    )
    return
  }

  console.log(
    `${PACKAGE_NAME}: Stopping WebSocket server (${wss.clients.size} clients connected)`,
  )
  wss?.close(() => {
    console.log(`${PACKAGE_NAME}: ✓ WebSocket server closed`)
  })
  wss = undefined
  vscode.window.showInformationMessage('Restart Roblox Studio Simuluator stopped')
  updateWebSocketStatusBar()
}
