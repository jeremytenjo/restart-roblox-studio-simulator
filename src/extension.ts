import * as vscode from 'vscode';
import { WebSocketServer, WebSocket } from 'ws';

type RunOrRestartMessage = {
  type: 'runOrRestart';
  source: string;
  timestamp: number;
};

let wss: WebSocketServer | undefined;

function broadcast(msg: RunOrRestartMessage) {
  if (!wss) {
    return;
  }
  const payload = JSON.stringify(msg);

  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload);
    }
  }
}

export function activate(context: vscode.ExtensionContext) {
  const port = 3010;

  wss = new WebSocketServer({ port }, () => {
    console.log(
      `[roblox-autotest-ws] WebSocket listening on ws://localhost:${port}`
    );
  });

  wss.on('connection', (socket: WebSocket) => {
    console.log('[roblox-autotest-ws] client connected');

    socket.on('close', () => {
      console.log('[roblox-autotest-ws] client disconnected');
    });

    socket.on('message', (data) => {
      try {
        const parsed = JSON.parse(data.toString());
        if (parsed && parsed.type === 'runOrRestart') {
          const msg: RunOrRestartMessage = {
            type: 'runOrRestart',
            source: parsed.source ?? 'roblox',
            timestamp: Date.now(),
          };
          broadcast(msg);
        }
      } catch {
        // ignore malformed messages
      }
    });
  });

  const cmd = vscode.commands.registerCommand(
    'robloxAutoTest.runOrRestart',
    () => {
      const msg: RunOrRestartMessage = {
        type: 'runOrRestart',
        source: 'vscode',
        timestamp: Date.now(),
      };
      broadcast(msg);
      vscode.window.showInformationMessage('Roblox: run/restart requested.');
    }
  );

  context.subscriptions.push(cmd);

  // NEW: Trigger on file save
  const onSaveDisposable = vscode.workspace.onDidSaveTextDocument((doc) => {
    console.log(`[roblox-autotest-ws] file saved: ${doc.fileName}`);

    // Optional: filter by file pattern (e.g., only TypeScript/Lua files)
    if (doc.fileName.match(/\.(ts|tsx|js|jsx|lua|luau)$/)) {
      const msg: RunOrRestartMessage = {
        type: 'runOrRestart',
        source: 'vscode-autosave',
        timestamp: Date.now(),
      };
      broadcast(msg);
      console.log(
        `[roblox-autotest-ws] triggered by file save: ${doc.fileName}`
      );
    }
  });

  context.subscriptions.push(onSaveDisposable);

  context.subscriptions.push({
    dispose() {
      if (wss) {
        wss.close();
        wss = undefined;
      }
    },
  });
}

export function deactivate() {}
