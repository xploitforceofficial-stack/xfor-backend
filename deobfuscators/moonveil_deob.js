'use strict';

const envlogger = require('../envlogger');

const BANNER = /generated using MoonVeil\s+(\d+\.\d+\.\d+)/i;
const HOSTED_URL = /https?:\/\/api\.getpolsec\.com\/scripts\/hosted\/([0-9a-f]{64})\.lua/i;
const BOOT_TAIL = /\)\s*:\s*g\(\s*\{([^}]*)\}\s*,\s*"([^"]+)"/;

function unescapeLua(lit) {
    return String(lit)
        .replace(/\\n/g, '\n')
        .replace(/\\r/g, '\r')
        .replace(/\\t/g, '\t')
        .replace(/\\a/g, '\x07')
        .replace(/\\b/g, '\b')
        .replace(/\\f/g, '\f')
        .replace(/\\v/g, '\v')
        .replace(/\\"/g, '"')
        .replace(/\\\\/g, '\\')
        .replace(/\\(\d{1,3})/g, (_, d) => String.fromCharCode(parseInt(d, 10) & 0xff));
}

function detectMoonVeil(content) {
    const src = String(content || '');
    let score = 0;
    const version = (src.match(BANNER) || [])[1] || null;
    const hosted = (src.match(HOSTED_URL) || [])[1] || null;

    if (/moonveil\.cc/i.test(src)) score += 10;
    if (BANNER.test(src)) score += 8;
    else if (/MoonVeil/i.test(src)) score += 5;
    if (/getpolsec\.com/i.test(src)) score += 6;
    if (hosted) score += 6;
    if (/\bscript_key\s*=/.test(src)) score += 3;
    if (/PolSec/i.test(src)) score += 4;

    const binKeys = (src.match(/\[0b(?:10|11)\]\s*=/g) || []).length;
    if (binKeys >= 8) score += 6;
    else if (binKeys >= 2) score += 3;
    if (/repeat[\s\S]{0,600}?until false/.test(src)) score += 3;
    if (/return\(\s*\{\s*function\s*\(/.test(src)) score += 3;
    if (BOOT_TAIL.test(src)) score += 3;

    const hasPayload = /return\(\s*\{\s*function\s*\(/.test(src);
    const mode = hosted ? (hasPayload ? 'hosted-full' : 'hosted-stub')
        : hasPayload ? 'envelope'
        : /\bscript_key\s*=/.test(src) ? 'key-stub'
        : 'unknown';

    return {
        isMoonVeil: score >= 8,
        score,
        version,
        hosted,
        mode,
        hasEnvelope: hasPayload,
    };
}

function peelEnvelope(content) {
    const src = String(content || '');
    const out = { names: [], entry: null, strings: [], version: null };

    out.version = (src.match(BANNER) || [])[1] || null;

    const boot = src.match(BOOT_TAIL);
    if (boot) {
        out.names = boot[1]
            .split(',')
            .map((s) => s.trim().replace(/^["']|["']$/g, ''))
            .filter(Boolean);
        out.entry = boot[2];
    }

    const lit = /\bl\s*"((?:[^"\\]|\\.)*)"/g;
    let m;
    while ((m = lit.exec(src)) !== null) {
        if (out.strings.length >= 64) break;
        out.strings.push(unescapeLua(m[1]));
    }

    return out;
}

const HEADER_LINE = /^--\s*(fuhed at OmniDBF|Deobfuscated by|deobf by|https:\/\/chat\.whatsapp\.com|run id\s+[0-9a-f]+)\s*$/i;
const TRACE_LINE = /^--\s*(vm trace:|opcodes executed:|execution profile:|op\s+\S+\s+a=)/i;
const UI_HIERARCHY = /^--\s*UI HIERARCHY\s*$/i;
const NOTE_LINE = /^--\s*(damn,|runtime error:|the nil did not|truncated|killed at)/i;
const PROBE_CALL = /^(getfenv|getgenv)\(\)\s*;?\s*$/;
const READS_NOTE = /^--\[\[\s*(getfenv|getgenv)\(\)\s+reads:\s*(.*?)\s*\]\]\s*$/;

function extractReconstruction(dump) {
    const lines = String(dump || '').split(/\r?\n/);
    const code = [];

    for (const raw of lines) {
        let line = raw.replace(/\s+$/, '');

        if (TRACE_LINE.test(line.trim())) break;

        if (UI_HIERARCHY.test(line.trim())) break;

        if (HEADER_LINE.test(line.trim())) continue;

        if (NOTE_LINE.test(line.trim())) continue;

        if (READS_NOTE.test(line.trim())) continue;

        if (PROBE_CALL.test(line.trim())) continue;

        if (/^\s*--/.test(line)) continue;

        line = line.replace(/\s*--\s*did(n't)? ran\s*$/g, '');

        code.push(line);
    }

    while (code.length && !code[0].trim()) code.shift();
    while (code.length && !code[code.length - 1].trim()) code.pop();

    const body = code.join('\n').replace(/\n{3,}/g, '\n\n');
    return { body, notes: [], reads: [] };
}

function looksLikePayload(body) {
    if (!body || !body.trim()) return false;

    return /[^\s-]/.test(body.replace(/--[^\n]*/g, ''));
}

async function deobfuscateMoonVeil(content, filename, options = {}) {
    const src = String(content || '');
    const det = detectMoonVeil(src);
    const staticPeel = peelEnvelope(src);

    if (det.mode === 'hosted-stub' || det.mode === 'key-stub') {
        return {
            success: false,
            error: 'This file is only a loader stub - it fetches the real payload from its server at runtime, '
                + 'so there is no inline MoonVeil payload to deobfuscate. Upload the payload file itself.',
        };
    }

    if (!envlogger.isAvailable || !envlogger.isAvailable().ok) {
        return {
            success: false,
            error: 'The MoonVeil engine needs the dump runtime, which is not available on this host. '
                + 'This is a deployment problem, not a problem with your file.',
        };
    }

    let result;
    try {
        result = await envlogger.runDump(src, {
            timeout: 300,
            maxTimeout: 300,
            maxNest: 3,
        });
    } catch (err) {
        return { success: false, error: `The MoonVeil engine failed: ${String((err && err.message) || err).slice(0, 400)}` };
    }

    const dump = result && result.dump ? result.dump : null;
    let raw = dump || result && result.error || '';

    const { body } = extractReconstruction(raw);

    const hadRuntimeError = /^--\s*runtime error:\s*(.+)$/mi.test(raw);
    if (hadRuntimeError) {
        const crash = (raw.match(/^--\s*runtime error:\s*(.+)$/mi) || [])[1] || 'the build stopped mid-run';
        return {
            success: false,
            error: `The MoonVeil VM stopped before the payload could be reconstructed: ${crash.trim().slice(0, 250)} `
                + 'This build uses a VM pattern the engine does not cover yet.',
        };
    }

    if (!looksLikePayload(body)) {
        const why = (result && result.error) ? String(result.error).split('\n')[0].slice(0, 300) : null;

        return {
            success: false,
            error: why
                ? `MoonVeil payload could not be reconstructed: ${why}`
                : 'MoonVeil payload could not be reconstructed. The build may use a runtime-composed environment or hit the execution budget.',
        };
    }

    const output = body;
    const decodedStrings = [];
    const strPattern = /"([^"\n]{2,60})"/g;
    let m;
    while ((m = strPattern.exec(body)) !== null) {
        if (!decodedStrings.includes(m[1]) && decodedStrings.length < 20) decodedStrings.push(m[1]);
    }

    return {
        success: true,
        output,
        stats: {
            type: `MoonVeil${det.version ? ' ' + det.version : ' 2.x'}`,
            inputSize: src.length,
            outputSize: output.length,
            decodedStrings,
            killed: Boolean(result && result.killed),
            envelopeSlots: staticPeel.names.length,
        },
    };
}

module.exports = { detectMoonVeil, deobfuscateMoonVeil, peelEnvelope, extractReconstruction };
