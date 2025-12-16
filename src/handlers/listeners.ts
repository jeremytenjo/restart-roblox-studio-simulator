import * as vscode from 'vscode'

import { broadcast, stopWebSocket } from '../websocket.js'
import { PACKAGE_NAME, vsCodePluginName } from '../constants.js'

type RestartMessage = {
  type: 'restart'
  source: string
  timestamp: number
}

export function setupFileSaveListener(context: vscode.ExtensionContext) {
  const onSaveDisposable = vscode.workspace.onDidSaveTextDocument((doc) => {
    const disableAutoReload = vscode.workspace
      .getConfiguration(vsCodePluginName)
      .get('disableAutoReload', false)

    if (disableAutoReload) {
      return
    }

    // Optional: filter by file pattern (e.g., only TypeScript/Lua files)
    if (doc.fileName.match(/\.(ts|tsx|js|jsx|lua|luau|json)$/)) {
      console.log(`${PACKAGE_NAME}: File saved: ${doc.fileName}`)
      const msg: RestartMessage = {
        type: 'restart',
        source: 'vscode-autosave',
        timestamp: Date.now(),
      }
      broadcast(msg)
    }
  })

  context.subscriptions.push(onSaveDisposable)
}

export function setupCleanupOnDeactivate(context: vscode.ExtensionContext) {
  context.subscriptions.push({
    dispose() {
      stopWebSocket()
    },
  })
}
