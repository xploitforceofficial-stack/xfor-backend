'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const { runProcess, probeCommand } = require('./proc');

const ENGINE_DIR = path.join(__dirname, 'luraph_v15', 'deobf');
const ENGINE_PY = path.join(ENGINE_DIR, 'deob.py');
const BIN_DIR = path.join(ENGINE_DIR, 'bin');
const LUAU_EXE = path.join(BIN_DIR, process.platform === 'win32' ? 'luau.exe' : 'luau');
const LUAU_AST_EXE = path.join(BIN_DIR, process.platform === 'win32' ? 'luau-ast.exe' : 'luau-ast');
const DEFAULT_TIMEOUT = 300;

const VERSION_BANNER = /Luraph\s+Obfuscator\s+v([\d.]+)/i;

const INLINE_VM = /^\s*(?:--[^\n]*\n)*\s*return\s*\(\s*\{\s*[A-Za-z_]\w*\s*=\s*function/;

const CLOSURE_TABLE = /return\s*\(\s*\{\s*[A-Za-z_]\w*\s*=\s*function/;

const STEP_WRAPPER = new RegExp(
    'repeat\\s+[A-Za-z_]\\w*\\s*,\\s*[A-Za-z_]\\w*\\s*,\\s*[A-Za-z_]\\w*\\s*,\\s*[A-Za-z_]\\w*'
    + '\\s*=\\s*[A-Za-z_]\\w*\\s*:\\s*[A-Za-z_]\\w*\\s*\\(');

const LPH_MARK = /LPH[_A-Z0-9*]/;

const PY_CANDIDATES = ['python3', 'python', 'py', '/usr/bin/python3', '/usr/local/bin/python3'];
const IS_PYTHON = /python/i;

let cachedPy;
function pythonCommand() {
    if (cachedPy !== undefined) return cachedPy;
    cachedPy = null;
    for (const candidate of PY_CANDIDATES) {
        try {
            const probe = spawnSync(candidate, ['-c', 'print(1)'], { timeout: 8000, windowsHide: true });
            if (probe.status === 0) return (cachedPy = candidate);
        } catch (_) {  }
    }
    return null;
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
            console.error('[LuraphV14] python probe failed:', err && err.message);
            return null;
        });
    }
    return primingPy;
}

function parseVersion(src) {
    const m = VERSION_BANNER.exec(src);
    if (!m) return null;
    const parts = m[1].split('.').map(Number);
    if (parts.some((n) => !Number.isFinite(n))) return null;
    return { raw: m[1], major: parts[0], minor: parts[1] };
}

const V14_MINORS = [6, 7, 8, 9];

function detect(content, want) {
    const src = String(content || '');
    const version = parseVersion(src);
    if (version && version.major !== 14) return { pass: false, score: 0, version };
    if (version && version.minor !== want) return { pass: false, score: 0, version };

    if (version) return { pass: true, score: 10, version };
    let score = 0;
    const table = INLINE_VM.test(src) || CLOSURE_TABLE.test(src);
    if (table) score += 6;
    if (table && STEP_WRAPPER.test(src)) score += 2;
    if (LPH_MARK.test(src)) score += 4;
    return { pass: score >= 8, score, version };
}

function detectorFor(want) {
    const key = 'isLuraphV14' + String(want).replace('.', '');
    return (c) => {
        const r = detect(c, want);
        return { [key]: r.pass, score: r.score, version: r.version };
    };
}

const detectLuraphV146 = detectorFor(6);
const detectLuraphV147 = detectorFor(7);
const detectLuraphV148 = detectorFor(8);
const detectLuraphV149 = detectorFor(9);

function engineStatus() {
    if (!fs.existsSync(ENGINE_PY)) {
        return { ok: false, reason: `the v14 engine is not installed on this host (${ENGINE_PY} missing)` };
    }
    if (!fs.existsSync(LUAU_EXE) || !fs.existsSync(LUAU_AST_EXE)) {
        return { ok: false, reason: 'the v14 engine is missing its Luau runtime (deobf/bin)' };
    }
    if (!pythonCommand()) {
        return { ok: false, reason: 'Python is needed on this host to run the v14 engine' };
    }
    return { ok: true, reason: null };
}

function readTraceSummary(stderr) {
    const m = /\[\*\]\s*v14 trace:\s*(\d+)\s+statement\(s\),\s*(\d+)\s+chain\(s\),\s*status:\s*(.+)/.exec(String(stderr || ''));
    if (!m) return {};
    return { statements: Number(m[1]), chains: Number(m[2]), runStatus: m[3].trim() };
}

function tidyEngineOutput(text) {

    return String(text || '').replace(/\r\n/g, '\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n';
}

async function deobfuscateLuraphV14(content, filename) {
    const started = Date.now();
    const status = engineStatus();
    if (!status.ok) {
        return { success: false, error: `The Luraph v14 engine is unavailable: ${status.reason}.` };
    }

    const stamp = Date.now() + '_' + Math.random().toString(36).slice(2, 8);
    const workDir = path.join(os.tmpdir(), `lv14_${stamp}`);
    const stem = (path.basename(String(filename || 'input.lua')) || 'input.lua').replace(/\.luau?$/i, '') || 'input';
    const inputPath = path.join(workDir, `${stem}.lua`);

    let stdout = '';
    let stderr = '';
    const python = pythonCommand();
    try {
        fs.mkdirSync(workDir, { recursive: true });
        fs.writeFileSync(inputPath, content, 'utf8');

        const res = await runProcess(python, [
            ENGINE_PY, inputPath,
            '--obfuscator', 'luraph_v14',
            '--no-devirt',
            '--debug',
            '--timeout', String(DEFAULT_TIMEOUT),
        ], { cwd: workDir, timeout: (DEFAULT_TIMEOUT + 180) * 1000 });
        stdout = (res && res.stdout) || '';
        stderr = (res && res.stderr) || '';
    } catch (err) {
        stdout = (err && err.stdout) || stdout;
        stderr = (err && err.stderr) || String((err && err.message) || '');
    } finally {

    }

    const tracePath = path.join(workDir, 'output', `${stem}.deobf.luau`);
    let output = '';
    try { if (fs.existsSync(tracePath)) output = fs.readFileSync(tracePath, 'utf8'); } catch (_) { output = ''; }

    try { fs.rmSync(workDir, { recursive: true, force: true }); } catch (_) {}

    if (!output.trim()) {
        const detail = String(stderr || '').trim().split('\n').filter((l) => /^\[!\]/.test(l)).join('\n');
        return {
            success: false,
            error: 'The Luraph v14 engine could not run this script to completion.'
                + (detail ? `\n\`\`\`\n${detail.slice(0, 800)}\n\`\`\`` : ''),
        };
    }

    const body = tidyEngineOutput(output);
    const info = readTraceSummary(stderr);

    const codeLines = body.split('\n').filter((l) => l.trim() && !l.trim().startsWith('--')).length;
    if (codeLines === 0) {
        return {
            success: false,
            error: 'This script decrypted its loader but nothing else ran: there is no '
                + 'behaviour to reconstruct.\n'
                + 'That normally means the payload is fetched at runtime (a webhook, a '
                + 'loadstring of remote code) and the host is not reachable, or the script '
                + 'only reacts to events this environment never raises.',
        };
    }

    return {
        success: true,
        output: body,
        stats: {
            inputSize: Buffer.byteLength(content, 'utf8'),
            outputSize: Buffer.byteLength(body, 'utf8'),
            decodedStrings: [],

            statements: info.statements,
            chains: info.chains,
            runStatus: info.runStatus,
        },
        detected: 'Luraph v14',
        elapsed: (Date.now() - started) / 1000,
    };
}

module.exports = {
    detectLuraphV146,
    detectLuraphV147,
    detectLuraphV148,
    detectLuraphV149,
    V14_MINORS,
    deobfuscateLuraphV14,
    engineStatus,
    primePython,
    readTraceSummary,
    DEFAULT_TIMEOUT,
};
