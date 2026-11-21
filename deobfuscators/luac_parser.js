'use strict';

const LUA_SIGNATURE = '\x1bLua';
const LUAC_VERSION = 0x51;
const LUAC_FORMAT = 0;

const OP_NAMES = [
    'MOVE','LOADK','LOADBOOL','LOADNIL','GETUPVAL','GETGLOBAL','GETTABLE','SETGLOBAL',
    'SETUPVAL','SETTABLE','NEWTABLE','SELF','ADD','SUB','MUL','DIV','MOD','POW','UNM','NOT','LEN',
    'CONCAT','JMP','EQ','LT','LE','TEST','TESTSET','CALL','TAILCALL','RETURN','FORLOOP','FORPREP','TFORLOOP','SETLIST','CLOSE','CLOSURE','VARARG'
];

function constantToString(k) {
    if (k === null) return 'nil';
    if (typeof k === 'boolean') return k ? 'true' : 'false';
    if (typeof k === 'number') return String(k);
    if (typeof k === 'string') return `"${k.replace(/"/g, '\\"')}"`;
    return String(k);
}

function parseLuac(buffer) {
    let pos = 0;
    function readBytes(n) {
        const slice = buffer.slice(pos, pos + n);
        pos += n;
        return slice;
    }
    function readByte() { return buffer[pos++]; }
    function readInt() {
        const v = buffer.readInt32LE(pos);
        pos += 4;
        return v;
    }
    function readInt32() { return readInt(); }
    function readNumber() {
        const v = buffer.readDoubleLE(pos);
        pos += 8;
        return v;
    }
    let sizeTSizeVal = 4;
    function readSizeT() {
        if (sizeTSizeVal === 8) {
            const low = buffer.readUInt32LE(pos);
            const high = buffer.readUInt32LE(pos + 4);
            pos += 8;

            return low + high * 0x100000000;
        } else {
            return readInt();
        }
    }
    function readString() {
        const size = readSizeT();
        if (size === 0) return null;
        const strBuf = readBytes(size);
        return strBuf.slice(0, size - 1).toString('utf8');
    }

    if (pos + 12 > buffer.length) throw new Error('File too short for header');
    const sig = buffer.slice(pos, pos + 4).toString('binary');
    pos += 4;
    if (sig !== LUA_SIGNATURE) throw new Error(`Bad header: ${buffer.slice(0,4).toString('hex')}`);
    const version = readByte();
    if (version !== LUAC_VERSION) throw new Error(`Unsupported version ${version.toString(16)}, expected 51`);
    const format = readByte();
    const endianness = readByte();
    const intSize = readByte();
    sizeTSizeVal = readByte();
    const instrSize = readByte();
    const numSize = readByte();
    const integral = readByte();

    function parseProto(source) {
        const proto = {};
        proto.source = readString();
        if (proto.source === null) proto.source = source;
        proto.linedefined = readInt();
        proto.lastlinedefined = readInt();
        proto.nups = readByte();
        proto.numparams = readByte();
        proto.is_vararg = readByte();
        proto.maxstacksize = readByte();

        proto.sizecode = readInt();
        proto.code = [];
        for (let i = 0; i < proto.sizecode; i++) {
            if (pos + 4 > buffer.length) throw new Error(`Unexpected EOF at code ${i}/${proto.sizecode}`);
            const instr = buffer.readUInt32LE(pos);
            pos += 4;
            proto.code.push(instr);
        }

        proto.sizek = readInt();
        proto.k = [];
        for (let i = 0; i < proto.sizek; i++) {
            const t = readByte();
            switch (t) {
                case 0: proto.k.push(null); break;
                case 1: proto.k.push(readByte() !== 0); break;
                case 3: proto.k.push(readNumber()); break;
                case 4: proto.k.push(readString()); break;
                default: throw new Error(`Unknown constant type ${t} at index ${i}`);
            }
        }

        proto.sizep = readInt();
        proto.p = [];
        for (let i = 0; i < proto.sizep; i++) {
            proto.p.push(parseProto(proto.source));
        }

        proto.sizelineinfo = readInt();
        proto.lineinfo = [];
        for (let i = 0; i < proto.sizelineinfo; i++) {
            proto.lineinfo.push(readInt());
        }

        proto.sizelocvars = readInt();
        proto.locvars = [];
        for (let i = 0; i < proto.sizelocvars; i++) {
            const varname = readString();
            const startpc = readInt();
            const endpc = readInt();
            proto.locvars.push({ varname, startpc, endpc });
        }

        proto.sizeupvalues = readInt();
        proto.upvalues = [];
        for (let i = 0; i < proto.sizeupvalues; i++) {
            proto.upvalues.push(readString());
        }

        return proto;
    }

    const main = parseProto(null);
    return main;
}

function decodeInstr(instr) {
    const op = instr & 0x3F;
    const A = (instr >> 6) & 0xFF;
    const C = (instr >> 14) & 0x1FF;
    const B = (instr >> 23) & 0x1FF;
    const Bx = (instr >> 14) & 0x3FFFF;
    const sBx = Bx - 131071;
    return { op, A, B, C, Bx, sBx, opName: OP_NAMES[op] || `OP_${op}` };
}

function disassemble(buffer) {
    const proto = parseLuac(buffer);
    return disassembleProto(proto);
}

function disassembleProto(proto, name = 'main', depth = 0) {
    const lines = [];
    const indent = '  '.repeat(depth);
    lines.push(`${indent}function <${proto.source || '?'}:${proto.linedefined},${proto.lastlinedefined}> (${proto.code.length} instructions)`);
    lines.push(`${indent}${proto.numparams} params, ${proto.maxstacksize} slots, ${proto.nups} upvalues, ${proto.k.length} constants, ${proto.p.length} protos`);

    if (proto.k.length > 0) {
        lines.push(`${indent}Constants:`);
        proto.k.forEach((k, i) => {
            let repr;
            if (k === null) repr = 'nil';
            else if (typeof k === 'string') repr = `"${k.slice(0, 60).replace(/\n/g, '\\n')}${k.length > 60 ? '...' : ''}"`;
            else repr = String(k);
            lines.push(`${indent}  ${i}: ${repr}`);
        });
    }

    lines.push(`${indent}Code:`);
    for (let pc = 0; pc < proto.code.length; pc++) {
        const instr = proto.code[pc];
        const d = decodeInstr(instr);
        let comment = '';

        try {
            if (d.opName === 'GETGLOBAL' || d.opName === 'SETGLOBAL') {
                if (d.Bx < proto.k.length && typeof proto.k[d.Bx] === 'string') comment = `; ${proto.k[d.Bx]}`;
            } else if (d.opName === 'LOADK') {
                if (d.Bx < proto.k.length) comment = `; ${constantToString(proto.k[d.Bx])}`;
            } else if (d.opName === 'SELF' || d.opName === 'GETTABLE' || d.opName === 'SETTABLE') {
                const rk = d.C;
                if (rk & 0x100) {
                    const idx = rk & 0xFF;
                    if (idx < proto.k.length) comment = `; "${proto.k[idx]}"`;
                }
                const rk2 = d.B;
                if (comment === '' && (rk2 & 0x100)) {
                    const idx = rk2 & 0xFF;
                    if (idx < proto.k.length) comment = `; "${proto.k[idx]}"`;
                }
            }
        } catch (_) {}

        const opStr = d.opName.padEnd(10);
        let args = '';

        const mode = getOpMode(d.op);
        if (mode === 'ABx' || mode === 'AsBx') {
            if (mode === 'AsBx') args = `${d.A} ${d.sBx}`;
            else args = `${d.A} ${d.Bx}`;
        } else {
            args = `${d.A} ${d.B} ${d.C}`;

        }
        lines.push(`${indent}  ${String(pc + 1).padStart(4)}  ${opStr} ${args}${comment}`);
    }

    for (let i = 0; i < proto.p.length; i++) {
        lines.push('');
        lines.push(disassembleProto(proto.p[i], `proto_${i}`, depth + 1));
    }
    return lines.join('\n');
}

function getOpMode(op) {
    if (op === 1 || op === 5 || op === 7 || op === 36) return 'ABx';
    if (op === 22 || op === 31 || op === 32) return 'AsBx';
    return 'ABC';
}

function toLuacListing(buffer) {
    const proto = parseLuac(buffer);
    const lines = [];
    function emitProto(p, depth) {
        const header = `function <${p.source || '?:0,0'}> (${p.code.length} instructions at ${'0'.padStart(8,'0')})`;
        const sub = `${p.numparams} params, ${p.maxstacksize} slots, ${p.nups} upvalues, ${p.k.length} constants, ${p.p.length} functions`;
        lines.push(header);
        lines.push(sub);
        for (let pc = 0; pc < p.code.length; pc++) {
            const d = decodeInstr(p.code[pc]);
            const opName = d.opName;
            let argStr = '';
            let cmt = '';
            if (opName === 'GETGLOBAL' || opName === 'SETGLOBAL' || opName === 'LOADK' || opName === 'CLOSURE') {
                argStr = `${d.A} ${d.Bx}`;
                if (d.Bx < p.k.length && p.k[d.Bx] !== null) cmt = `; ${constantToString(p.k[d.Bx])}`;
            } else if (opName === 'JMP' || opName === 'FORLOOP' || opName === 'FORPREP') {
                argStr = `${d.A} ${d.sBx}`;

                const dest = pc + 1 + d.sBx + 1;
                cmt = `; to ${dest}`;
            } else {
                argStr = `${d.A} ${d.B} ${d.C}`;

                if (d.B & 0x100) {
                    const idx = d.B & 0xFF;
                    if (idx < p.k.length) cmt = `; ${constantToString(p.k[idx])}`;
                }
                if ((d.C & 0x100) && !cmt) {
                    const idx = d.C & 0xFF;
                    if (idx < p.k.length) cmt = `; ${constantToString(p.k[idx])}`;
                }
            }

            const line = p.lineinfo[pc] || '-';
            lines.push(`\t${pc + 1}\t[${line}]\t${opName.padEnd(10)}\t${argStr}${cmt ? '\t' + cmt : ''}`);
        }
        for (const sub of p.p) {
            lines.push('');
            emitProto(sub, depth + 1);
        }
    }
    emitProto(proto, 0);
    return lines.join('\n');
}

module.exports = { parseLuac, decodeInstr, disassemble, toLuacListing, disassembleProto, OP_NAMES };
