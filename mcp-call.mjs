// mcp-call.mjs — invoke a single MCP tool and print the result
// Usage: node mcp-call.mjs <toolName> <argsJsonFile>
import { spawn } from 'child_process';
import { readFileSync } from 'fs';

const [,, toolName, argsFile] = process.argv;
const toolArgs = argsFile ? JSON.parse(readFileSync(argsFile, 'utf8')) : {};

const proc = spawn('node', ['src/index.js'], {
  cwd: 'C:\\Github\\tiaopen-mcp',
  stdio: ['pipe', 'pipe', 'inherit'],
});

let buf = '';
proc.stdout.on('data', (d) => { buf += d.toString(); });

const messages = [
  { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'cli', version: '1.0' } } },
  { jsonrpc: '2.0', method: 'notifications/initialized', params: {} },
  { jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: toolName, arguments: toolArgs } },
];

let i = 0;
function send() {
  if (i < messages.length) {
    proc.stdin.write(JSON.stringify(messages[i++]) + '\n');
    setTimeout(send, 100);
  } else {
    // wait for response
    setTimeout(() => {
      const lines = buf.split('\n').filter(l => l.trim());
      for (const line of lines) {
        try {
          const obj = JSON.parse(line);
          if (obj.id === 2) {
            if (obj.error) {
              console.error('Error:', JSON.stringify(obj.error, null, 2));
            } else {
              const content = obj.result?.content ?? [];
              for (const c of content) console.log(c.text);
            }
            proc.kill();
            process.exit(obj.error ? 1 : 0);
          }
        } catch {}
      }
      console.error('No response received. Raw output:\n' + buf);
      proc.kill();
      process.exit(1);
    }, 30000);
  }
}
send();

setTimeout(() => { console.error('timeout'); proc.kill(); process.exit(1); }, 60000);
