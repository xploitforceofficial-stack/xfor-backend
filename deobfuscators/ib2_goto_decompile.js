'use strict';

const { decodeInstr, OP_NAMES } = require('./luac_parser');

function isRK(val) { return (val & 0x100) !== 0; }
function rkIndex(val) { return val & 0xFF; }
function rkToString(proto, rkVal) {
    if (isRK(rkVal)) {
        const idx = rkIndex(rkVal);
        const k = proto.k[idx];
        if (k === null) return 'nil';
        if (typeof k === 'string') return JSON.stringify(k);
        if (typeof k === 'number') return String(k);
        if (typeof k === 'boolean') return String(k);
        return `K${idx}`;
    } else {
        return `r${rkVal}`;
    }
}
function constToString(proto, idx) {
    const k = proto.k[idx];
    if (k === null) return 'nil';
    if (typeof k === 'string') return JSON.stringify(k);
    return String(k);
}

function decompileProto(proto, name = 'main', depth = 0) {
    const indent = '  '.repeat(depth);
    const lines = [];

    const targets = new Set();
    for (let pc = 0; pc < proto.code.length; pc++) {
        const { op, sBx } = decodeInstr(proto.code[pc]);
        const opName = OP_NAMES[op];
        if (opName === 'JMP' || opName === 'FORLOOP' || opName === 'FORPREP') {
            const dest = pc + 1 + sBx;
            if (dest >= 0 && dest < proto.code.length) targets.add(dest);
            if (dest === proto.code.length) targets.add(dest);
        }

    }

    function emitLabel(pc) {
        if (targets.has(pc)) {
            lines.push(`${indent}::L${pc}::`);
        }
    }

    if (proto.p.length > 0) {
        for (let i = 0; i < proto.p.length; i++) {
            lines.push('');
            lines.push(decompileProto(proto.p[i], `proto_${i}`, depth));
        }
        lines.push('');
    }

    const skip = new Set();

    for (let pc = 0; pc < proto.code.length; pc++) {
        if (skip.has(pc)) continue;
        emitLabel(pc);
        const instr = proto.code[pc];
        const d = decodeInstr(instr);
        const opName = d.opName;
        const A = d.A, B = d.B, C = d.C, Bx = d.Bx, sBx = d.sBx;

        switch (opName) {
            case 'MOVE': {
                lines.push(`${indent}r${A} = r${B}`);
                break;
            }
            case 'LOADK': {
                const k = proto.k[Bx];
                lines.push(`${indent}r${A} = ${JSON.stringify(k)}`);
                break;
            }
            case 'LOADBOOL': {
                lines.push(`${indent}r${A} = ${B ? 'true' : 'false'}`);
                if (C !== 0) {

                    const dest = pc + 2;
                    lines.push(`${indent}goto L${dest}`);
                }
                break;
            }
            case 'LOADNIL': {
                if (A === B) {
                    lines.push(`${indent}r${A} = nil`);
                } else {
                    const regs = [];
                    for (let r = A; r <= B; r++) regs.push(`r${r}`);
                    lines.push(`${indent}${regs.join(', ')} = nil`);
                }
                break;
            }
            case 'GETUPVAL': {
                lines.push(`${indent}r${A} = upvalue[${B}]`);
                break;
            }
            case 'GETGLOBAL': {
                const k = proto.k[Bx];
                const name = typeof k === 'string' ? k : `K${Bx}`;

                if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
                    lines.push(`${indent}r${A} = ${name}`);
                } else {
                    lines.push(`${indent}r${A} = _G[${JSON.stringify(k)}]`);
                }
                break;
            }
            case 'GETTABLE': {
                const bStr = `r${B}`;
                const cStr = rkToString(proto, C);
                lines.push(`${indent}r${A} = ${bStr}[${cStr}]`);
                break;
            }
            case 'SETGLOBAL': {
                const k = proto.k[Bx];
                const name = typeof k === 'string' ? k : `K${Bx}`;
                if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
                    lines.push(`${indent}${name} = r${A}`);
                } else {
                    lines.push(`${indent}_G[${JSON.stringify(k)}] = r${A}`);
                }
                break;
            }
            case 'SETUPVAL': {
                lines.push(`${indent}upvalue[${B}] = r${A}`);
                break;
            }
            case 'SETTABLE': {
                const bStr = rkToString(proto, B);
                const cStr = rkToString(proto, C);
                lines.push(`${indent}r${A}[${bStr}] = ${cStr}`);
                break;
            }
            case 'NEWTABLE': {

                lines.push(`${indent}r${A} = {}`);
                break;
            }
            case 'SELF': {
                const bStr = `r${B}`;
                const cStr = rkToString(proto, C);
                lines.push(`${indent}r${A+1} = ${bStr}`);
                lines.push(`${indent}r${A} = ${bStr}[${cStr}]`);
                break;
            }
            case 'ADD': case 'SUB': case 'MUL': case 'DIV': case 'MOD': case 'POW': {
                const opMap = { ADD: '+', SUB: '-', MUL: '*', DIV: '/', MOD: '%', POW: '^' };
                const bStr = rkToString(proto, B);
                const cStr = rkToString(proto, C);
                lines.push(`${indent}r${A} = ${bStr} ${opMap[opName]} ${cStr}`);
                break;
            }
            case 'UNM': {
                lines.push(`${indent}r${A} = -r${B}`);
                break;
            }
            case 'NOT': {
                lines.push(`${indent}r${A} = not r${B}`);
                break;
            }
            case 'LEN': {
                lines.push(`${indent}r${A} = #r${B}`);
                break;
            }
            case 'CONCAT': {
                const parts = [];
                for (let r = B; r <= C; r++) parts.push(`r${r}`);
                lines.push(`${indent}r${A} = ${parts.join(' .. ')}`);
                break;
            }
            case 'JMP': {
                const dest = pc + 1 + sBx;
                if (dest >= 0 && dest <= proto.code.length) {
                    lines.push(`${indent}goto L${dest}`);
                }
                break;
            }
            case 'EQ': case 'LT': case 'LE': {
                const opMap = { EQ: '==', LT: '<', LE: '<=' };
                const bStr = rkToString(proto, B);
                const cStr = rkToString(proto, C);
                const cond = `${bStr} ${opMap[opName]} ${cStr}`;
                const nextPc = pc + 1;
                let dest = nextPc + 1;
                if (nextPc < proto.code.length) {
                    const nxt = decodeInstr(proto.code[nextPc]);
                    if (OP_NAMES[nxt.op] === 'JMP') {
                        dest = nextPc + 1 + nxt.sBx;
                        skip.add(nextPc);
                    }
                }
                if (A === 1) {
                    lines.push(`${indent}if ${cond} then goto L${dest}`);
                    lines.push(`${indent}else goto L${pc+2}`);
                } else {
                    lines.push(`${indent}if not (${cond}) then goto L${dest}`);
                    lines.push(`${indent}else goto L${pc+2}`);
                }
                break;
            }
            case 'TEST': {
                const val = `r${A}`;
                const cond = C === 1 ? val : `not ${val}`;
                const nextPc = pc + 1;
                let dest = pc + 2;
                if (nextPc < proto.code.length) {
                    const nxt = decodeInstr(proto.code[nextPc]);
                    if (OP_NAMES[nxt.op] === 'JMP') { dest = nextPc + 1 + nxt.sBx; skip.add(nextPc); }
                }
                lines.push(`${indent}if ${cond} then goto L${dest}`);
                lines.push(`${indent}else goto L${pc+2}`);
                break;
            }
            case 'TESTSET': {
                const bStr = `r${B}`;
                const cond = C === 1 ? bStr : `not ${bStr}`;
                const nextPc = pc + 1;
                let dest = pc + 2;
                if (nextPc < proto.code.length) {
                    const nxt = decodeInstr(proto.code[nextPc]);
                    if (OP_NAMES[nxt.op] === 'JMP') { dest = nextPc + 1 + nxt.sBx; skip.add(nextPc); }
                }
                lines.push(`${indent}if ${cond} then r${A} = ${bStr}; goto L${dest}`);
                lines.push(`${indent}else goto L${pc+2}`);
                break;
            }
            case 'CALL': case 'TAILCALL': {
                const isTail = opName === 'TAILCALL';
                const nArgs = B === 0 ? '...' : B - 1;
                const nRets = C === 0 ? '...' : C - 1;

                let args = '';
                if (B === 0) {

                    args = `r${A+1}, ...`;
                } else if (B > 1) {
                    const argRegs = [];
                    for (let r = A + 1; r < A + B; r++) argRegs.push(`r${r}`);
                    args = argRegs.join(', ');
                }
                if (isTail) {
                    lines.push(`${indent}return r${A}(${args})`);
                } else {
                    if (C === 1) {

                        lines.push(`${indent}r${A}(${args})`);
                    } else if (C === 2) {
                        lines.push(`${indent}r${A} = r${A}(${args})`);
                    } else if (C === 0) {
                        lines.push(`${indent}r${A}, ... = r${A}(${args})`);
                    } else {
                        const retRegs = [];
                        for (let r = A; r < A + C - 1; r++) retRegs.push(`r${r}`);
                        lines.push(`${indent}${retRegs.join(', ')} = r${A}(${args})`);
                    }
                }
                break;
            }
            case 'RETURN': {
                if (B === 1) {
                    lines.push(`${indent}return`);
                } else if (B === 2) {
                    lines.push(`${indent}return r${A}`);
                } else if (B === 0) {
                    lines.push(`${indent}return r${A}, ...`);
                } else {
                    const retRegs = [];
                    for (let r = A; r < A + B - 1; r++) retRegs.push(`r${r}`);
                    lines.push(`${indent}return ${retRegs.join(', ')}`);
                }
                break;
            }
            case 'FORLOOP': {
                const dest = pc + 1 + sBx;

                lines.push(`${indent}r${A} = r${A} + r${A+2}`);
                lines.push(`${indent}if r${A} <= r${A+1} then goto L${dest} else goto L${pc+1}`);
                lines.push(`${indent}r${A+3} = r${A}`);
                break;
            }
            case 'FORPREP': {
                const dest = pc + 1 + sBx;
                lines.push(`${indent}r${A} = r${A} - r${A+2}`);
                lines.push(`${indent}goto L${dest}`);
                break;
            }
            case 'TFORLOOP': {

                const nextPc = pc + 1;
                let dest = pc + 2;

                const rets = [];
                for (let r = A + 3; r < A + 3 + C; r++) rets.push(`r${r}`);
                lines.push(`${indent}${rets.join(', ')} = r${A}(r${A+1}, r${A+2})`);
                lines.push(`${indent}if r${A+3} ~= nil then r${A+2} = r${A+3} else goto L${pc+2}`);
                break;
            }
            case 'SETLIST': {
                let cVal = C;
                if (C === 0) {
                     if (pc + 1 < proto.code.length) {
                         cVal = proto.code[pc + 1];
                         skip.add(pc + 1);
                         for (let i = 1; i <= B && B !== 0; i++) {
                             lines.push(`${indent}r${A}[${(cVal-1)*50 + i}] = r${A+i}`);
                         }
                     }
                 } else {
                     if (B !== 0) {
                         for (let i = 1; i <= B; i++) {
                             lines.push(`${indent}r${A}[${(cVal-1)*50 + i}] = r${A+i}`);
                         }
                     }
                 }
                 break;
             }
            case 'CLOSE': {
                lines.push(`${indent}close r${A}`);
                break;
            }
            case 'CLOSURE': {
                const protoIdx = Bx;
                lines.push(`${indent}r${A} = closure(proto_${protoIdx})`);

                break;
            }
            case 'VARARG': {
                if (B === 0) {
                    lines.push(`${indent}r${A}, ... = ...`);
                } else if (B !== 1) {
                    const regs = [];
                    for (let r = A; r < A + B - 1; r++) regs.push(`r${r}`);
                    lines.push(`${indent}${regs.join(', ')} = ...`);
                }
                break;
            }
            default: {
                break;
            }
        }
    }

    if (targets.has(proto.code.length)) {
        lines.push(`${indent}::L${proto.code.length}::`);
    }

    if (proto.code.length > 0) {
        const last = decodeInstr(proto.code[proto.code.length - 1]);
        if (OP_NAMES[last.op] !== 'RETURN') {

        }
    }
    return lines.join('\n');
}

function decompileBuffer(buffer) {
    const { parseLuac } = require('./luac_parser');
    const proto = parseLuac(buffer);
    return decompileProto(proto);
}

module.exports = { decompileProto, decompileBuffer };
