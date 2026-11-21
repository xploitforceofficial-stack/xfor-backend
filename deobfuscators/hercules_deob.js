'use strict';

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { runProcess, probeCommand } = require('./proc');
const { rp } = require('./sanitize');

const HERCULES_DIR = path.join(__dirname, 'HerculesDeobf', 'hercules', 'deobfhercules_fixed');
const HERCULES_PY = path.join(HERCULES_DIR, 'deobfhercules.py');

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

let primingPy = null;
function primePython() {
    if (cachedPy !== undefined) return Promise.resolve(cachedPy);
    if (!primingPy) {
        primingPy = (async () => {
            for (const c of PY_CANDIDATES) {
                if (await probeCommand(c, ['--version'], IS_PYTHON, 5000)) return c;
            }
            return null;
        })().then((found) => {
            cachedPy = found;
            primingPy = null;
            return cachedPy;
        }, (err) => {
            cachedPy = null;
            primingPy = null;
            console.error('[Hercules] python probe failed:', err && err.message);
            return null;
        });
    }
    return primingPy;
}

function engineStatus() {
    if (!fs.existsSync(HERCULES_PY)) {
        return { ok: false, error: 'The Hercules engine is not installed on this host (deobfhercules.py missing). This is a deployment problem, not a problem with your file.' };
    }
    if (!getPythonCmd()) {
        return { ok: false, error: 'Python 3 is not available on this host, so the Hercules engine cannot run. This is a deployment problem, not a problem with your file.' };
    }
    return { ok: true };
}

function detectHercules(content) {
    let score = 0;
    if (/\[Obfuscated by Hercules v/.test(content)) score += 10;
    if (/hercules-obfuscator\.xyz/.test(content)) score += 5;
    if (/Protected By Hercules/.test(content)) score += 5;
    if (/WrapState\s*\(\s*BcToState\s*\(/.test(content)) score += 5;
    if (/hercules,v1,alpha/.test(content)) score += 3;
    return { isHercules: score >= 5, score };
}

async function deobfuscateHercules(content) {

    const stamp = Date.now() + '_' + Math.random().toString(36).slice(2, 8);
    const tmpInput = path.join(os.tmpdir(), `herc_${stamp}_input.lua`);
    const tmpOutput = path.join(os.tmpdir(), `herc_${stamp}_output.lua`);

    const status = engineStatus();
    if (!status.ok) {
        console.error(`[Hercules] ${status.error} (looked for ${HERCULES_PY})`);
        return { success: false, error: status.error };
    }

    try {
        fs.writeFileSync(tmpInput, content, 'utf8');

        await runProcess(getPythonCmd(), [HERCULES_PY, tmpInput, tmpOutput], {
            timeout: 120000,
            maxBuffer: 50 * 1024 * 1024,
        });

        try { fs.unlinkSync(tmpInput); } catch (_) {}

        if (!fs.existsSync(tmpOutput)) {
            return { success: false, error: 'The Hercules engine produced no output. The script is probably not Hercules VM output.' };
        }

        const rawOutput = fs.readFileSync(tmpOutput, 'utf8');
        try { fs.unlinkSync(tmpOutput); } catch (_) {}

        let lines = rawOutput.split('\n');

        lines = lines.filter(line => !line.match(/^-- (Decompiled by|Top-level:|Raw bytecode:|Recovered constants|Recovery method|Note:|WARNING:|Outer Bytecode|Embedded VM|Inner VM|bytecode chunk:|Embedded source:|-- {2,})/));
        lines = lines.filter(line => !line.match(/^-- {2,}(top-level|sub-proto)/));
        lines = lines.filter(line => !line.match(/^--\s*K\d+/));

        let skipAntitamper = false;
        const cleaned = [];
        for (const line of lines) {
            if (line.includes('fn_main_P0 = function(...)')) {
                skipAntitamper = true;
                continue;
            }
            if (skipAntitamper) {
                if (line.trim() === 'end') {
                    skipAntitamper = false;
                    continue;
                }
                continue;
            }

            if (line.match(/^local v0 = fn_main_P0$/) ||
                line.match(/^fn_main_P0/) ||
                line.match(/Tamper Detected/) ||
                line.match(/^local v1 = "Tamper Detected/)) {
                continue;
            }
            cleaned.push(line);
        }

        const output = cleaned
            .join('\n')
            .replace(/^\n{3,}/, '\n\n')
            .trim();

        if (output.length <= 20) {
            return { success: false, error: 'The Hercules engine recovered nothing usable from this script. It is probably a Hercules mode that does not use the VM this engine can undo (light / VRSECF), or not Hercules output at all.' };
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
                type: 'Hercules',
                inputSize: content.length,
                outputSize: output.length,
                decodedStrings,
            },
        };
    } catch (err) {
        try { fs.unlinkSync(tmpInput); } catch (_) {}
        try { fs.unlinkSync(tmpOutput); } catch (_) {}

        const all = [err.message, err.stdout, err.stderr].filter(Boolean).join('\n');
        if (err.code === 'ENOENT') {
            return { success: false, error: 'Could not launch Python for the Hercules engine. This is a deployment problem, not a problem with your file.' };
        }
        if (err.signal === 'SIGTERM' || err.signal === 'SIGKILL' || err.code === 'ETIMEDOUT' || /ETIMEDOUT/.test(String(err.code))) {
            return { success: false, error: 'The Hercules engine timed out (over 2 minutes) on this script.' };
        }
        if (/ModuleNotFoundError|ImportError|No module named/.test(all)) {
            return { success: false, error: 'The Hercules engine is missing a Python dependency on this host. This is a deployment problem, not a problem with your file.' };
        }
        return { success: false, error: 'Hercules deobfuscation failed. The script may not be Hercules VM output, or it uses a mode the engine does not recognise.' };
    }
}

module.exports = { detectHercules, deobfuscateHercules, engineStatus, primePython, HERCULES_PY };
