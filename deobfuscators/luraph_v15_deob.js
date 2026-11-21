'use strict';

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { runProcess, probeCommand } = require('./proc');

const ENGINE_DIR = path.join(__dirname, 'luraph_v15', 'deobf');
const ENGINE_PY = path.join(ENGINE_DIR, 'deob.py');
const ENGINE_BIN = path.join(ENGINE_DIR, 'bin');
const LUAU_EXE = path.join(ENGINE_BIN, process.platform === 'win32' ? 'luau.exe' : 'luau');
const LUAU_AST_EXE = path.join(ENGINE_BIN, process.platform === 'win32' ? 'luau-ast.exe' : 'luau-ast');

const PY_CANDIDATES = ['python3', 'python', '/usr/bin/python3', '/usr/local/bin/python3'];
const IS_PYTHON = /python/i;

const HEADER_V15 = /This file was protected using Luraph Obfuscator v15(?:\.\d+)?/i;
const HEADER_ANY_LURAPH = /This file was protected using Luraph Obfuscator v[\d.]+/i;

const V15_SHELL = /return\s+setmetatable\s*\(\s*\{[\s\S]{0,4000}?\[\d+\]\s*=\s*(?:bit32|buffer|string|table|math|os|coroutine|task|utf8)\.\w/;

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
            console.error('[LuraphV15] python probe failed:', err && err.message);
            return null;
        });
    }
    return primingPy;
}

function engineStatus() {
    if (!fs.existsSync(ENGINE_PY)) {
        return { ok: false, error: 'The Luraph v15 engine is not installed on this host (deob.py missing). This is a deployment problem, not a problem with your file.' };
    }
    if (!fs.existsSync(LUAU_EXE) || !fs.existsSync(LUAU_AST_EXE)) {
        return { ok: false, error: 'The Luraph v15 engine is missing its Luau runtime (bin/luau). This is a deployment problem, not a problem with your file.' };
    }
    if (!getPythonCmd()) {
        return { ok: false, error: 'Python 3 is not available on this host, so the Luraph v15 engine cannot run. This is a deployment problem, not a problem with your file.' };
    }
    return { ok: true };
}

function detectLuraphV15(content) {
    const src = String(content || '');
    let score = 0;
    if (HEADER_V15.test(src.slice(0, 500))) score += 10;
    if (V15_SHELL.test(src.slice(0, 20000))) score += 8;
    if (/\bLPH\b/.test(src.slice(0, 200000))) score += 2;
    return { isLuraphV15: score >= 8, score };
}

function pickResultFile(outDir, stem) {
    if (!fs.existsSync(outDir)) return null;
    const files = fs.readdirSync(outDir)
        .filter(f => f.endsWith('.lua'))
        .map(f => ({ f, m: fs.statSync(path.join(outDir, f)).mtimeMs }))
        .sort((a, b) => b.m - a.m);
    if (!files.length) return null;
    return path.join(outDir, files[0].f);
}

function tidyEngineOutput(raw) {
    const text = String(raw || '');

    const lines = text.split('\n').filter(l => !/^\s*--\s*(?:Deobfuscated|Decompiled) by .* on Discord\s*$/.test(l));
    return lines.join('\n').replace(/^\n{3,}/g, '\n\n').trim();
}

async function runEngine(python, inputPath, extra) {
    const args = [ENGINE_PY, inputPath].concat(extra || []);
    return runProcess(python, args, {
        cwd: ENGINE_DIR,
        timeout: 240000,
        maxBuffer: 50 * 1024 * 1024,
    });
}

async function deobfuscateLuraphV15(content, filename) {
    const status = engineStatus();
    if (!status.ok) {
        console.error(`[LuraphV15] ${status.error}`);
        return { success: false, error: status.error };
    }

    const stamp = Date.now() + '_' + Math.random().toString(36).slice(2, 8);
    const workDir = path.join(os.tmpdir(), `lv15_${stamp}`);
    const outDir = path.join(workDir, 'output');
    const stem = (path.basename(String(filename || 'input.lua')) || 'input.lua').replace(/\.luau?$/i, '') || 'input';
    const inputPath = path.join(workDir, `${stem}.lua`);

    let stdout = '';
    let stderr = '';
    const python = getPythonCmd();
    try {
        fs.mkdirSync(outDir, { recursive: true });
        fs.writeFileSync(inputPath, content, 'utf8');

        const res = await runEngine(python, inputPath);
        stdout = (res && res.stdout) || '';
        stderr = (res && res.stderr) || '';
    } catch (err) {
        stdout = (err && err.stdout) || '';
        stderr = (err && err.stderr) || '';
        if (!/Luraph v15 \(detected/.test(String(stderr))) {
            console.error('[LuraphV15] engine failed:', err && err.message);
            return {
                success: false,
                error: 'The Luraph v15 engine failed to run on this script.'
                    + (String(stderr).trim() ? `\n\`\`\`\n${String(stderr).trim().slice(0, 800)}\n\`\`\`` : ''),
            };
        }
    }

    const readResult = () => {
        const p = pickResultFile(outDir, stem);
        if (!p) return '';
        try { return fs.readFileSync(p, 'utf8'); } catch (_) { return ''; }
    };

    const stats = (body, type) => ({
        type,
        inputSize: Buffer.byteLength(content, 'utf8'),
        outputSize: Buffer.byteLength(body, 'utf8'),
        decodedStrings: [],
    });

    let output = readResult();
    const gaveUp = () => /odbf:\s|filled VM table is being held/.test(output);
    const usable = (text) => text && tidyEngineOutput(text).length > 20
        && !/^\s*error\(\s*"odbf/m.test(text);

    if (gaveUp() || !usable(output)) {
        console.error('[LuraphV15] devirtualization incomplete, falling back to the behaviour trace');
        try { fs.rmSync(outDir, { recursive: true, force: true }); } catch (_) {}
        try {
            fs.mkdirSync(outDir, { recursive: true });
            const res2 = await runEngine(python, inputPath, ['--no-devirt']);
            stdout = (res2 && res2.stdout) || stdout;
            stderr = (res2 && res2.stderr) || stderr;
        } catch (err2) {
            stderr += '\n' + String((err2 && err2.stderr) || (err2 && err2.message) || '');
        }
        const traceOut = readResult();
        if (usable(traceOut)) {
            const body = tidyEngineOutput(traceOut);
            return {
                success: true,
                output: body,
                partial: true,
                stats: stats(body, 'Luraph v15 (behaviour trace)'),
            };
        }
        if (!output) output = traceOut;
    }

    try { fs.rmSync(workDir, { recursive: true, force: true }); } catch (_) {}

    const body = usable(output) ? tidyEngineOutput(output) : '';
    if (body) {
        return {
            success: true,
            output: body,
            stats: stats(body, 'Luraph v15'),
        };
    }

    const reason = (output.match(/odbf:[^"')]+/) || [])[0] || '';
    const traceErr = (stderr.match(/run status:\s*([^\n]+)/) || [])[1] || '';
    return {
        success: false,
        error: 'The Luraph v15 engine could not fully devirtualize this script.'
            + (reason ? `\nIt stopped at: \`${reason.trim()}\`` : '')
            + (traceErr ? `\nThe script itself also reported: \`${traceErr.trim().slice(0, 200)}\`` : ''),
    };
}

module.exports = { detectLuraphV15, deobfuscateLuraphV15, primePython, engineStatus };
