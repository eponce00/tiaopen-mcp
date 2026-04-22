// ps-runner.js — execute a PowerShell script, return parsed JSON stdout
import { spawn } from 'child_process';

/**
 * Run a PowerShell script with the given arguments array.
 * Resolves with the parsed JSON object from stdout.
 * Rejects with an Error containing stderr if exit code != 0.
 */
export function runPs(scriptPath, args = []) {
  return new Promise((resolve, reject) => {
    const psArgs = [
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', scriptPath,
      ...args,
    ];

    const proc = spawn('powershell.exe', psArgs, { stdio: ['ignore', 'pipe', 'pipe'] });

    let stdout = '';
    let stderr = '';
    proc.stdout.on('data', (d) => { stdout += d.toString(); });
    proc.stderr.on('data', (d) => { stderr += d.toString(); });

    proc.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(`PS script failed (exit ${code}): ${stderr.trim() || stdout.trim()}`));
        return;
      }
      try {
        resolve(JSON.parse(stdout.trim()));
      } catch {
        resolve({ raw: stdout.trim() });
      }
    });

    proc.on('error', (err) => reject(new Error(`Failed to start PowerShell: ${err.message}`)));
  });
}
