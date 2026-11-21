'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDotnetCmd } = require('./dotnet');
const { runProcess } = require('./proc');
const { rp } = require('./sanitize');

const IB2_DIR = path.join(__dirname, 'IronBrew2Deobf', 'ib2bot-main', 'ib2deobf');
const IB2_DLL = path.join(IB2_DIR, 'LuaAnalysis.Ironbrew2.dll');

function detectIronBrew2(content) {
    let score = 0;
    if (/local\s+\w+\s*=\s*string\.byte/.test(content)) score += 1;
    if (/local\s+\w+\s*=\s*string\.char/.test(content)) score += 1;
    if (/local\s+\w+\s*=\s*string\.sub/.test(content)) score += 1;
    if (/local\s+\w+\s*=\s*table\.concat/.test(content)) score += 1;
    if (/local\s+\w+\s*=\s*math\.ldexp/.test(content)) score += 3;
    if (/local\s+\w+\s*=\s*getfenv/.test(content)) score += 2;
    if (/local\s+\w+\s*=\s*setmetatable/.test(content)) score += 1;
    if (/function\s*\(\w+\)\s*local\s+\w+,\s*\w+,\s*\w+\s*=\s*"",""/.test(content)) score += 3;
    if (/local\s+\w+\s*=\s*bit\s+and\s+bit\.bxor/.test(content)) score += 2;
    if (content.includes('while true do') && content.includes('return function')) score += 2;
    if (/ironbrew/i.test(content)) score += 5;
    if (/BytecodeEncoder/.test(content)) score += 3;

    if (/string\.byte/.test(content) && /string\.char/.test(content) && /math\.ldexp/.test(content) && /getfenv/.test(content)) score += 3;
    return { isIronBrew2: score >= 5, score };
}

async function deobfuscateIronBrew2(content) {
    const tmpInput = path.join(os.tmpdir(), `ib2_${Date.now()}_${Math.random().toString(36).slice(2)}_input.lua`);
    const tmpOutput = path.join(os.tmpdir(), `ib2_${Date.now()}_${Math.random().toString(36).slice(2)}_output.luac`);

    if (!fs.existsSync(IB2_DLL)) {
        console.error(`[IB2] engine missing: ${IB2_DLL}`);
        return { success: false, error: 'The IronBrew 2 engine is not installed on this host (LuaAnalysis.Ironbrew2.dll missing). This is a deployment problem, not a problem with your file.' };
    }

    try {
        fs.writeFileSync(tmpInput, content, 'utf8');

        const dotnet = getDotnetCmd();
        if (!dotnet) {
            try { fs.unlinkSync(tmpInput); } catch (_) {}
            return { success: false, error: 'dotnet runtime not found on this host (Linux Railway needs Dockerfile with .NET 8+9). See Dockerfile in repo.' };
        }
        try {
            await runProcess(dotnet, [IB2_DLL, tmpInput, tmpOutput], {
                timeout: 180000,
                maxBuffer: 50 * 1024 * 1024,
            });
        } catch (e) {
            try { fs.unlinkSync(tmpInput); } catch (_) {}
            const msg = (e.stderr && e.stderr.toString()) || e.message || '';

            if (e.code === 'ETIMEDOUT' || e.signal === 'SIGTERM' || e.signal === 'SIGKILL') {
                return { success: false, error: 'The IronBrew 2 engine timed out (over 3 minutes) on this script. It is too large or too deeply nested for this host.' };
            }
            if (msg.toLowerCase().includes('dotnet') || msg.includes('Could not find') || msg.includes('Failed to')) {
                return { success: false, error: 'IB2 engine failed (dotnet missing or .NET 9 not installed). Use Dockerfile.' };
            }
            return { success: false, error: 'Deobfuscation failed. The file may not be obfuscated with IronBrew 2 (vm error).' };
        }

        try { fs.unlinkSync(tmpInput); } catch (_) {}

        if (!fs.existsSync(tmpOutput)) {
            return { success: false, error: 'Deobfuscation failed. The file may not be obfuscated with IronBrew 2.' };
        }

        let luacBuffer;
        try { luacBuffer = fs.readFileSync(tmpOutput); } catch (_) {
            return { success: false, error: 'Failed to read deobfuscator output.' };
        }
        try { fs.unlinkSync(tmpOutput); } catch (_) {}

        if (luacBuffer.length < 12 || luacBuffer.slice(0, 4).toString('binary') !== '\x1bLua') {
            return { success: false, error: 'Deobfuscator produced invalid bytecode (not Lua 5.1).' };
        }

        let proto;
        let rawDisasm = '';

        try {
            const { parseLuac, toLuacListing } = require('./luac_parser');
            proto = parseLuac(luacBuffer);
            rawDisasm = toLuacListing(luacBuffer);
        } catch (parseErr) {
            return { success: false, error: `Bytecode parsing failed: ${parseErr.message}` };
        }

        const totalInstrs = countInstrs(proto);

        let structuredLua = null;
        if (totalInstrs < 5000) {
            try {
                const { decompileFromDisassembly } = require('./luac_decompile');
                structuredLua = decompileFromDisassembly(rawDisasm);
                if (structuredLua && structuredLua.trim().length < 100) structuredLua = null;

                if (structuredLua && (structuredLua.match(/R\d+/g) || []).length > 50) {

                }
            } catch (_) {
                structuredLua = null;
            }
        }

        let gotoLua = null;
        try {
            const { decompileBuffer } = require('./ib2_goto_decompile');
            gotoLua = decompileBuffer(luacBuffer);
            if (gotoLua && gotoLua.trim().length < 100) gotoLua = null;
        } catch (_) {
            gotoLua = null;
        }

        let prettyDisasm = '';
        try {
            const { parseLuac: p2 } = require('./luac_parser');
            const root = parseLuac(luacBuffer);
            prettyDisasm = buildPrettyOutput(root);
        } catch (_) {
            prettyDisasm = rawDisasm;
        }

        let output;
        let isDecompiled = false;
        if (structuredLua && (structuredLua.includes('return') || structuredLua.split('\n').length > 5)) {
            output = structuredLua;
            isDecompiled = true;
            if (gotoLua && structuredLua.length < 500 && gotoLua.length > structuredLua.length * 2) {
                output += '\n' + gotoLua.slice(0, 100000);
            }
        } else if (gotoLua) {
            output = gotoLua;
            isDecompiled = true;
        } else {
            output = prettyDisasm;
        }

        const decodedStrings = [];
        const strPattern = /"([^"\n]{3,60})"/g;
        let match;

        try {
            collectConstants(proto, decodedStrings);
        } catch (_) {}

        if (decodedStrings.length < 3) {
            let m;
            while ((m = strPattern.exec(output)) !== null) {
                const s = m[1];
                if (!decodedStrings.includes(s) && decodedStrings.length < 20 && /^[A-Za-z0-9_ \/\.\-:]+$/.test(s) === false || s.length > 4) {

                    if (/^[\x20-\x7E]{3,}$/.test(s) && !decodedStrings.includes(s)) {
                        decodedStrings.push(s);
                        if (decodedStrings.length >= 20) break;
                    }
                }
            }
        }

        const cleanStrings = decodedStrings.filter(s => s.length >= 3 && s.length <= 60 && /^[\x20-\x7E]+$/.test(s)).slice(0, 20);

        const MAX_OUTPUT = 7 * 1024 * 1024;
        if (output.length > MAX_OUTPUT) {
            output = output.slice(0, MAX_OUTPUT);
        }
        output = output.split('\n').filter(l => !l.trim().startsWith('--')).join('\n').trim();

        return {
            success: true,
            output,
            stats: {
                type: 'IronBrew 2',
                inputSize: content.length,
                outputSize: output.length,
                decodedStrings: cleanStrings,
                isDecompiled,
                protoCount: countProtos(proto),
                instrCount: countInstrs(proto),
            },
        };
    } catch (err) {
        try { fs.unlinkSync(tmpInput); } catch (_) {}
        try { fs.unlinkSync(tmpOutput); } catch (_) {}
        const safeMsg = err.message && err.message.includes('Command failed:')
            ? 'Deobfuscation failed. The file may not be obfuscated with IronBrew 2.'
            : rp(err.message || 'An unexpected error occurred.');
        return { success: false, error: safeMsg };
    }
}

function countProtos(proto) {
    let c = 1;
    for (const p of proto.p) c += countProtos(p);
    return c;
}
function countInstrs(proto) {
    let c = proto.code.length;
    for (const p of proto.p) c += countInstrs(p);
    return c;
}
function collectConstants(proto, out) {
    for (const k of proto.k) {
        if (typeof k === 'string' && k.length >= 3 && k.length <= 60 && /^[\x20-\x7E]+$/.test(k)) {
            if (!out.includes(k) && out.length < 20) out.push(k);
        }
    }
    for (const p of proto.p) collectConstants(p, out);
}

function buildPrettyOutput(root) {
    let out = '';
    function emit(proto, depth) {
        const indent = '  '.repeat(depth);
        out += `\n`;

        const { decodeInstr, OP_NAMES } = require('./luac_parser');
        const getOpMode = (op) => (op === 1 || op === 5 || op === 7 || op === 36) ? 'ABx' : (op === 22 || op === 31 || op === 32) ? 'AsBx' : 'ABC';
        for (let pc = 0; pc < Math.min(proto.code.length, 3000); pc++) {
            const instr = proto.code[pc];
            const op = instr & 0x3F;
            const A = (instr >> 6) & 0xFF;
            const C = (instr >> 14) & 0x1FF;
            const B = (instr >> 23) & 0x1FF;
            const Bx = (instr >> 14) & 0x3FFFF;
            const sBx = Bx - 131071;
            const opName = OP_NAMES[op] || `OP_${op}`;
            let args, cmt = '';
            if (opName === 'GETGLOBAL' || opName === 'SETGLOBAL' || opName === 'LOADK' || opName === 'CLOSURE') {
                args = `${A} ${Bx}`;
                if (Bx < proto.k.length && proto.k[Bx] != null) {
                    const kv = proto.k[Bx];
                    cmt = typeof kv === 'string' ? `; "${kv.slice(0, 40).replace(/"/g, '\\"')}"` : `; ${kv}`;
                }
            } else if (opName === 'JMP' || opName === 'FORLOOP' || opName === 'FORPREP') {
                args = `${A} ${sBx}`;
                cmt = `; to ${pc + 2 + sBx}`;
            } else {
                args = `${A} ${B} ${C}`;

                if (B & 0x100) {
                    const idx = B & 0xFF;
                    if (idx < proto.k.length && typeof proto.k[idx] === 'string') cmt = `; "${proto.k[idx].slice(0, 30)}"`;
                }
                if (!cmt && (C & 0x100)) {
                    const idx = C & 0xFF;
                    if (idx < proto.k.length && typeof proto.k[idx] === 'string') cmt = `; "${proto.k[idx].slice(0, 30)}"`;
                }
            }
            out += `${String(pc + 1).padStart(4)}  ${opName.padEnd(10)} ${args.padEnd(12)} ${cmt}\n`;
        }
        if (proto.code.length > 3000) out += `\n`;
        out += `\n`;
        for (let i = 0; i < proto.p.length; i++) {
            emit(proto.p[i], depth + 1);
        }
    }
    emit(root, 0);
    return out;
}

module.exports = { detectIronBrew2, deobfuscateIronBrew2 };
