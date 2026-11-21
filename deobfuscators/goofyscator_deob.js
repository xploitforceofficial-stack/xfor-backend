'use strict';

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { runProcess, probeCommand } = require('./proc');
const { rp } = require('./sanitize');

const GOOFY_DIR = path.join(__dirname, 'goofyscator');
const GOOFY_PY = path.join(GOOFY_DIR, 'decompiler.py');

const PY_CANDIDATES = ['python3', 'python', '/usr/bin/python3', '/usr/local/bin/python3'];
const IS_PYTHON = /python/i;
let cachedPy;

function getPythonCmd() {
    if (cachedPy !== undefined) return cachedPy;
    cachedPy = null;
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

function findLune() {
    const fromEnv = process.env.GOOFYSCATOR_LUNE;
    if (fromEnv && fs.existsSync(fromEnv)) return fromEnv;
    for (const c of ['/usr/local/bin/lune', '/usr/bin/lune']) {
        try { if (fs.existsSync(c)) return c; } catch (_) {}
    }
    try {
        const probe = require('child_process').spawnSync('lune', ['--version'], {
            timeout: 5000, encoding: 'utf8', windowsHide: true,
        });
        if (probe.status === 0) return 'lune';
    } catch (_) {}
    return null;
}

function engineStatus() {
    if (!fs.existsSync(GOOFY_PY)) {
        return { ok: false, error: 'The Goofyscator engine is not installed on this host (decompiler.py missing). This is a deployment problem, not a problem with your file.' };
    }
    if (!getPythonCmd()) {
        return { ok: false, error: 'Python 3 is not available on this host, so the Goofyscator engine cannot run. This is a deployment problem, not a problem with your file.' };
    }
    if (!findLune()) {
        return { ok: false, error: 'The Lune runtime is not available on this host, so the Goofyscator engine cannot run. This is a deployment problem, not a problem with your file.' };
    }
    return { ok: true };
}

function detectGoofyscator(content) {
    const src = String(content || '');
    let score = 0;
    const reasons = [];
    const hit = (n, what) => { score += n; reasons.push(what); };
    if (/if\s+type\s*\(\s*([A-Za-z_]\w*)\s*\)\s*~=\s*"table"\s+or\s+\1\s*\[\s*1\s*\]\s*~=\s*1\s+or\s+\1\s*\[\s*2\s*\]\s*~=\s*[A-Za-z_]\w*\s+then\s+error\s*\(\s*"runtime error"\s*,\s*0\s*\)/.test(src)) {
        hit(5, 'viT env-consistency check');
    }
    if (/goofyscator/i.test(src)) hit(5, 'goofyscator watermark');
    if (/error\s*\(\s*"runtime error"\s*,\s*0\s*\)/.test(src)) hit(2, 'bare runtime-error guard');
    return { isGoofyscator: score >= 6, score, reasons };
}

async function deobfuscateGoofyscator(content) {
    const stamp = Date.now() + '_' + Math.random().toString(36).slice(2, 8);
    const tmpInput = path.join(os.tmpdir(), `goofy_${stamp}_input.lua`);
    const tmpOutput = path.join(os.tmpdir(), `goofy_${stamp}_output.lua`);
    const tmpTrace = tmpOutput + '.trace.txt';

    const status = engineStatus();
    if (!status.ok) {
        return { success: false, error: status.error };
    }
    const cleanup = (...files) => {
        for (const f of files.length ? files : [tmpInput, tmpOutput, tmpTrace]) {
            try { fs.unlinkSync(f); } catch (_) {}
        }
    };

    try {
        fs.writeFileSync(tmpInput, content, 'utf8');

        const childEnv = { ...process.env, GOOFYSCATOR_LUNE: findLune() };
        for (const k of Object.keys(childEnv)) {
            if (/token|secret|password|webhook|private/i.test(k)) delete childEnv[k];
        }
        await runProcess(getPythonCmd(), [GOOFY_PY, tmpInput, tmpOutput, '60'], {
            timeout: 120000,
            maxBuffer: 50 * 1024 * 1024,
            cwd: GOOFY_DIR,
            env: childEnv,
        });

        cleanup(tmpInput);

        if (!fs.existsSync(tmpOutput)) {
            cleanup(tmpOutput, tmpTrace);
            return { success: false, error: 'The Goofyscator engine produced no output. The script is probably not Goofyscator output.' };
        }
        const rawOutput = fs.readFileSync(tmpOutput, 'utf8');
        cleanup(tmpOutput, tmpTrace);

        const lines = rawOutput.split('\n').filter(l => {
            const t = l.trim();
            if (!t) return false;
            if (/^-- (Source file|Decompiled by|Program output|Captured program output|No print output|VM may have|Recovered \d+ strings)/.test(t)) return false;
            return true;
        });
        const output = lines.join('\n').replace(/\n{3,}/g, '\n\n').trim();
        const codeLines = lines.filter(l => {
            const t = l.trim();
            return t.length > 0 && !t.startsWith('--');
        });
        if (codeLines.length === 0 || output.length <= 20) {
            return { success: false, error: 'The Goofyscator engine recovered nothing usable from this script. It is probably not Goofyscator output.' };
        }

        const decodedStrings = [];
        const strPattern = /"([^"]{3,60})"/g;
        let match;
        while ((match = strPattern.exec(output)) !== null) {
            if (!decodedStrings.includes(match[1]) && decodedStrings.length < 20) {
                decodedStrings.push(match[1]);
            }
        }

        return {
            success: true,
            output,
            stats: {
                type: 'Goofyscator',
                inputSize: content.length,
                outputSize: output.length,
                decodedStrings,
            },
        };
    } catch (err) {
        cleanup();
        const all = [err.message, err.stdout, err.stderr].filter(Boolean).join('\n');
        if (err.code === 'ENOENT') {
            return { success: false, error: 'Could not launch Python for the Goofyscator engine. This is a deployment problem, not a problem with your file.' };
        }
        if (err.signal === 'SIGTERM' || err.signal === 'SIGKILL' || err.code === 'ETIMEDOUT' || /ETIMEDOUT/.test(String(err.code))) {
            return { success: false, error: 'The Goofyscator engine timed out (over 2 minutes) on this script.' };
        }
        if (/ModuleNotFoundError|ImportError|No module named/.test(all)) {
            return { success: false, error: 'The Goofyscator engine is missing a Python dependency on this host. This is a deployment problem, not a problem with your file.' };
        }
        return { success: false, error: 'Goofyscator deobfuscation failed. The script may not be Goofyscator output.' };
    }
}

module.exports = { detectGoofyscator, deobfuscateGoofyscator, engineStatus, GOOFY_PY };
