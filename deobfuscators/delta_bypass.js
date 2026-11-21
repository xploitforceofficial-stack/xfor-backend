'use strict';

const path = require('path');
const { runProcess, probeCommand } = require('./proc');

const DELTA_DIR = path.join(__dirname, 'DeltaBypass');
const DELTA_MAIN = path.join(DELTA_DIR, 'main.py');

const PY_CANDIDATES = ['python3', 'python', '/usr/bin/python3', '/usr/local/bin/python3'];
const IS_PYTHON = /python/i;
let cachedPy;

function getPythonCmd() {
    if (cachedPy !== undefined) return cachedPy;
    cachedPy = null;
    const { execFileSync } = require('child_process');
    for (const c of PY_CANDIDATES) {
        try {
            const out = execFileSync(c, ['--version'], {
                timeout: 5000, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true,
            });
            if (IS_PYTHON.test(out || '')) { cachedPy = c; break; }
        } catch (e) {
            if (e && IS_PYTHON.test(String(e.stdout || '') + String(e.stderr || ''))) { cachedPy = c; break; }
        }
    }
    return cachedPy;
}

let primingPy = null;
function primePython() {
    if (cachedPy !== undefined) return Promise.resolve(cachedPy);
    if (!primingPy) {
        primingPy = (async () => {
            for (const c of PY_CANDIDATES) {
                if (await probeCommand(c, ['--version'], IS_PYTHON, 5000)) return c;
            }
            return null;
        })().then((found) => { cachedPy = found; primingPy = null; return cachedPy; },
                 () => { cachedPy = null; primingPy = null; return null; });
    }
    return primingPy;
}

function engineStatus() {
    const fs = require('fs');
    if (!fs.existsSync(DELTA_MAIN)) {
        return { ok: false, error: 'The Delta bypass engine is not installed on this host (main.py missing). This is a deployment problem.' };
    }
    if (!getPythonCmd()) {
        return { ok: false, error: 'Python 3 is not available on this host, so the Delta bypass engine cannot run. This is a deployment problem.' };
    }
    return { ok: true };
}

function extractTicket(url) {
    try {
        const u = new URL(url);
        const d = u.searchParams.get('d');
        if (d) return d;
    } catch (_) {}
    return url.trim();
}

function isPlatoUrl(url) {
    try {
        const u = new URL(url);
        return u.hostname === 'auth.platorelay.com' && u.pathname === '/a' && u.searchParams.has('d');
    } catch (_) {
        return false;
    }
}

async function solvePlatoKey(url, opts = {}) {
    const status = engineStatus();
    if (!status.ok) return { success: false, key: null, elapsed: 0, error: status.error, rounds: null };

    const maxRounds = Math.max(1, Math.min(Number(opts.maxRounds) || 3, 12));
    const timeout = Math.max(30000, Number(opts.timeout) || 120000);
    const py = getPythonCmd();

    const t0 = Date.now();
    try {
        const { stdout, stderr } = await runProcess(py, [
            DELTA_MAIN,
            '--quiet',
            '--max-rounds', String(maxRounds),
            url,
        ], { timeout, maxBuffer: 10 * 1024 * 1024 });

        const elapsed = (Date.now() - t0) / 1000;
        const output = `${stdout}\n${stderr}`;

        const keyMatch = output.match(/\[\+\]\s*DELTA KEY #\d+:\s*(\S+)/i);
        if (keyMatch) {
            return { success: true, key: keyMatch[1], elapsed, error: null, rounds: null };
        }

        const roundMatch = output.match(/(\d+)\/(\d+)\s*(?:round|轮)/);
        const rounds = roundMatch ? parseInt(roundMatch[1], 10) : null;

        let reason = 'The solver could not extract a key from this link.';
        if (/captcha\s*fail|验证码.*失败/i.test(output)) {
            reason = 'Captcha solving failed - the image could not be solved automatically.';
        } else if (/无效链接|invalid.*link|expired/i.test(output)) {
            reason = 'This link is invalid or has expired.';
        } else if (/step.*fail|all services failed/i.test(output)) {
            reason = 'All checkpoint steps failed - the server may be rate-limiting or the link is stale.';
        } else if (/未获取到 key|no.*key/i.test(output)) {
            reason = 'The solver ran through all rounds but did not obtain a key.';
        } else if (/ticket.*长度不足/i.test(output)) {
            reason = 'The URL does not contain a valid ticket.';
        }

        return { success: false, key: null, elapsed, error: reason, rounds };
    } catch (err) {
        const elapsed = (Date.now() - t0) / 1000;
        const all = [err.message, err.stdout, err.stderr].filter(Boolean).join('\n');

        if (err.code === 'ENOENT') {
            return { success: false, key: null, elapsed, error: 'Could not launch Python for the Delta bypass engine. This is a deployment problem.', rounds: null };
        }
        if (err.signal === 'SIGTERM' || err.signal === 'SIGKILL' || err.code === 'ETIMEDOUT') {
            return { success: false, key: null, elapsed, error: `The solver timed out after ${(timeout / 1000).toFixed(0)}s. The link may require too many rounds or the server is slow.`, rounds: null };
        }
        if (/ModuleNotFoundError|ImportError|No module named/.test(all)) {
            return { success: false, key: null, elapsed, error: 'The Delta bypass engine is missing a Python dependency on this host. This is a deployment problem.', rounds: null };
        }

        return { success: false, key: null, elapsed, error: 'The solver encountered an unexpected error.', rounds: null };
    }
}

module.exports = { solvePlatoKey, isPlatoUrl, extractTicket, engineStatus, primePython, DELTA_MAIN };
