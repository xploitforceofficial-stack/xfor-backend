'use strict';

const { execSync } = require('child_process');

function decompileLuac(luacPath) {
    const disasm = execSync(`luac -l "${luacPath}"`, { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 });
    return decompileFromDisassembly(disasm);
}

function decompileFromDisassembly(disasm) {
    const lines = disasm.split(/\r?\n/);
    const out = [];
    let indent = 0;
    const regs = {};
    const tableConsts = {};

    function get(r) {
        if (r === undefined || r === null || r === '') return 'nil';
        const n = parseInt(r);
        if (isNaN(n)) return r;
        return regs[n] !== undefined ? regs[n] : `r${n}`;
    }
    function set(r, expr) { const n = parseInt(r); if (!isNaN(n)) regs[n] = expr; }
    function line(s) { out.push('  '.repeat(indent) + s); }

    function isIdent(s) { return /^[A-Za-z_][A-Za-z0-9_]*$/.test(s); }
    function parseCmt(cmt) {
        if (!cmt) return null;
        cmt = cmt.replace(/^-\s*/, '');
        if (cmt.startsWith('"') && cmt.endsWith('"')) {
            const inner = cmt.slice(1, -1);

            return `"${inner}"`;
        }
        const n = Number(cmt);
        if (!isNaN(n) && cmt !== '' && String(n) === cmt.trim()) return String(n);
        if (cmt.startsWith('`') && cmt.endsWith('`')) return cmt.slice(1,-1);
        return cmt;
    }
    function formatAccess(obj, key) {

        if (key.startsWith('"') && key.endsWith('"')) {
            const inner = key.slice(1,-1);
            if (isIdent(inner)) return `${obj}.${inner}`;
            return `${obj}[${key}]`;
        }
        if (key.startsWith('K')) return `${obj}[${key}]`;

        if (/^\d+$/.test(key)) return `${obj}[${key}]`;

        return `${obj}[${key}]`;
    }
    function constExpr(argVal, cmt) {
        if (cmt) { const v = parseCmt(cmt); if (v !== null) return v; }
        if (argVal < 0) return `K${-argVal - 1}`;
        if (argVal !== undefined && (argVal & 0x100)) {
            const idx = argVal & 0xFF;
            return `K${idx}`;
        }
        return get(argVal);
    }

    const instrs = [];
    for (const raw of lines) {
        const t = raw.replace(/\r/g, '');
        if (!t.startsWith('\t')) continue;
        const m = t.match(/^\t(\d+)\s+\[[^\]]*\]\s+(\w+)\s+(.*?)(?:\s*;\s*(.*))?$/);
        if (!m) continue;
        const parts = m[3].trim().split(/\s+/).filter(Boolean);
        instrs.push({
            pc: parseInt(m[1]),
            op: m[2],
            A: parts[0] !== undefined ? parseInt(parts[0]) : undefined,
            B: parts[1] !== undefined ? parseInt(parts[1]) : undefined,
            C: parts[2] !== undefined ? parseInt(parts[2]) : undefined,
            comment: m[4] ? m[4].trim() : '',
        });
    }

    const reachable = new Set([0]);
    const queue = [0];
    const jumpTargets = new Set();
    for (const ins of instrs) {
        if (ins.op === 'JMP') {
            const target = ins.pc + 1 + (ins.C !== undefined ? ins.C : 0);
        }
    }

    const jmpTargets = new Set();
    for (let k = 0; k < instrs.length; k++) {
        if (instrs[k].op === 'JMP') {
            const sBx = instrs[k].C;

            const dest = instrs[k].pc + 1 + (instrs[k].B || 0);
            if (dest >= 0) jmpTargets.add(dest);
        }
    }
    let dead = false;
    for (let i = 0; i < instrs.length; i++) {
        const ins = instrs[i];
        const { op, A, B, C, comment } = ins;

        if (dead) {
            if (!jmpTargets.has(ins.pc)) continue;
            dead = false;
        }
        if (op === 'RETURN') dead = true;
        const isBConst = B !== undefined && (B < 0 || (B & 0x100) !== 0);
        const isCConst = C !== undefined && (C < 0 || (C & 0x100) !== 0);

        switch (op) {
            case 'MOVE': set(A, get(B)); break;
            case 'GETGLOBAL': {
                const raw = parseCmt(comment);
                const key = raw ? raw.slice(1,-1) : `K${B < 0 ? -B-1 : B}`;
                set(A, isIdent(key) ? key : `_G[${JSON.stringify(key)}]`);
                break;
            }
            case 'SETGLOBAL': {
                const raw = parseCmt(comment);
                const key = raw ? raw.slice(1,-1) : `K${B < 0 ? -B-1 : B}`;
                const name = isIdent(key) ? key : `_G[${JSON.stringify(key)}]`;
                line(`${name} = ${get(A)};`);
                break;
            }
            case 'GETTABLE': {
                const obj = get(B);

                if (!isCConst && tableConsts[B] !== undefined) {
                    const idx = parseInt(get(C).replace(/"/g,'').replace('r','')) || parseInt(C);

                    let keyVal;
                    if (isCConst) {
                        const k = parseCmt(comment);
                        if (k && k.startsWith('"')) keyVal = k;
                        else if (C & 0x100) keyVal = `${C & 0xFF}`;
                        else keyVal = get(C);
                    } else {
                        keyVal = get(C);
                    }

                    const numKey = parseInt(String(keyVal).replace(/"/g,''));
                    if (!isNaN(numKey) && tableConsts[B][numKey] !== undefined) {
                        set(A, tableConsts[B][numKey]);
                        break;
                    }
                }
                let key;
                if (isCConst) {
                    const kc = parseCmt(comment);
                    key = kc !== null ? kc : `K${C & 0xFF}`;
                } else {
                    key = get(C);
                }
                let expr;
                if (key.startsWith('"') && isIdent(key.slice(1,-1))) expr = `${obj}.${key.slice(1,-1)}`;
                else if (key.startsWith('"')) expr = `${obj}[${key}]`;
                else expr = `${obj}[${key}]`;

                if (tableConsts[B] && !isCConst) {
                    const kNum = parseInt(key.replace(/"/g,''));
                    if (!isNaN(kNum) && tableConsts[B][kNum] !== undefined) {
                        set(A, tableConsts[B][kNum]);
                        break;
                    }
                }
                if (tableConsts[B] && isCConst) {
                    const ck = parseCmt(comment);
                    let kStr = ck ? ck.replace(/"/g,'') : '';
                    const kNum2 = parseInt(kStr);
                    if (!isNaN(kNum2) && tableConsts[B][kNum2] !== undefined) {
                        set(A, tableConsts[B][kNum2]);
                        break;
                    }
                }
                set(A, expr);
                break;
            }
            case 'SETTABLE': {
                const obj = get(A);
                const key = isBConst ? (parseCmt(comment) || `K${B & 0xFF}`) : get(B);
                const val = isCConst ? (parseCmt(comment) || get(C)) : get(C);

                let kStr = key;
                let vStr = val;
                if (isBConst && comment) {
                    const ck = parseCmt(comment);
                    if (ck) kStr = ck;
                }
                if (isCConst && comment && !isBConst) {
                    const cv = parseCmt(comment);
                    if (cv) vStr = cv;
                }
                let left;
                if (kStr.startsWith('"') && isIdent(kStr.slice(1,-1))) left = `${obj}.${kStr.slice(1,-1)}`;
                else left = `${obj}[${kStr}]`;
                line(`${left} = ${vStr};`);
                break;
            }
            case 'NEWTABLE': set(A, '{}'); tableConsts[A] = {}; break;
            case 'SETLIST': {

                if (tableConsts[A]) {
                    const start = (C - 1) * 50 + 1;
                    for (let i = 1; i <= B; i++) {
                        const val = regs[A + i];
                        if (val !== undefined) tableConsts[A][start + i - 1] = val;
                    }
                }
                break;
            }
            case 'LOADK': {
                const v = parseCmt(comment);
                set(A, v !== null ? v : `K${B}`);
                break;
            }
            case 'LOADBOOL': set(A, B ? 'true' : 'false'); if (C !== 0) {  } break;
            case 'LOADNIL': {
                const count = B || 0;
                for (let j = 0; j <= count; j++) set(A + j, 'nil');
                break;
            }
            case 'SELF': {
                const obj = get(B);
                let method;
                if (isCConst) {
                    const m = parseCmt(comment);
                    method = m ? m.slice(1,-1) : `K${C & 0xFF}`;
                } else {
                    method = get(C);
                    if (method.startsWith('"')) method = method.slice(1,-1);
                }

                set(A, `${obj}:${method}`);
                set(A + 1, obj);
                break;
            }
            case 'CALL': {
                const fn = get(A);
                const isMethod = fn.includes(':');
                let args = [];
                if (B === 0) {
                    args.push('...');
                } else if (B > 1) {
                    let start = A + 1;
                    if (isMethod) start = A + 2;
                    for (let r = start; r < A + B; r++) args.push(get(r));
                }
                const argStr = args.join(', ');
                const callExpr = isMethod ? `${fn}(${argStr})` : `${fn}(${argStr})`;

                if (C === 1) {
                    line(`${callExpr};`);
                } else if (C === 2) {
                    set(A, callExpr);
                } else if (C === 0) {
                    line(`${callExpr};`);
                } else {
                    line(`${callExpr};`);
                }
                break;
            }
            case 'RETURN': {
                if (B <= 1) { line('return;'); break; }
                if (B === 2) { line(`return ${get(A)};`); break; }
                line(`return ${Array.from({ length: B - 1 }, (_, j) => get(A + j)).join(', ')};`);
                break;
            }
            case 'EQ': case 'LT': case 'LE': {
                const lhs = isBConst ? (parseCmt(comment) || `K${B & 0xFF}`) : get(B);
                const rhs = isCConst ? (parseCmt(comment) || `K${C & 0xFF}`) : get(C);

                let l = lhs, r = rhs;

                if (!isBConst && isCConst && comment) {
                    const cv = parseCmt(comment);
                    if (cv) r = cv;
                } else if (isBConst && !isCConst && comment) {
                    const bv = parseCmt(comment);
                    if (bv) l = bv;
                }
                const sym = { EQ: '==', LT: '<', LE: '<=' }[op];
                const cond = A === 0 ? `not (${l} ${sym} ${r})` : `${l} ${sym} ${r}`;
                const nextIsJmp = i+1 < instrs.length && instrs[i+1].op === 'JMP';
                const next2IsJmp = i+2 < instrs.length && instrs[i+2].op === 'JMP';
                if (nextIsJmp && next2IsJmp) {
                    line(`if ${cond} then`);
                    indent++;
                } else if (nextIsJmp) {
                    line(`if ${cond} then`);
                    indent++;
                } else {
                    line(`if ${cond} then`);
                    indent++;
                }
                break;
            }
            case 'TEST': {
                const val = get(A);
                const cond = C === 1 ? val : `not ${val}`;
                line(`if ${cond} then`);
                indent++;
                break;
            }
            case 'TESTSET': {
                const val = get(B);
                set(A, val);
                const cond = C === 1 ? val : `not ${val}`;
                line(`if ${cond} then`);
                indent++;
                break;
            }
            case 'JMP': {
                const prev = i>0 ? instrs[i-1] : null;
                const isAfterTest = prev && ['EQ','LT','LE','TEST','TESTSET'].includes(prev.op);
                const prev2 = i>1 ? instrs[i-2] : null;
                const isSecondJmp = prev && prev.op === 'JMP';
                if (isAfterTest) {

                } else if (isSecondJmp) {
                    indent = Math.max(0, indent - 1);
                    line('end');
                } else {
                    if (indent > 0) {

                    }
                }
                break;
            }
            case 'FORPREP': break;
            case 'FORLOOP': { indent = Math.max(0, indent - 1); line('end'); break; }
            case 'TFORLOOP': { indent = Math.max(0, indent - 1); line('end'); break; }
            case 'CLOSURE': set(A, 'function() end'); break;
            case 'GETUPVAL': set(A, `upvalue${B}`); break;
            case 'SETUPVAL': line(`upvalue${B} = ${get(A)};`); break;
            case 'VARARG': set(A, '...'); break;
            case 'ADD': { const l = isBConst ? (parseCmt(comment) || get(B)) : get(B); const r = isCConst ? (parseCmt(comment) || get(C)) : get(C); set(A, `(${l} + ${r})`); break; }
            case 'SUB': { const l = isBConst ? (parseCmt(comment) || get(B)) : get(B); const r = isCConst ? (parseCmt(comment) || get(C)) : get(C); set(A, `(${l} - ${r})`); break; }
            case 'MUL': { const l = isBConst ? (parseCmt(comment) || get(B)) : get(B); const r = isCConst ? (parseCmt(comment) || get(C)) : get(C); set(A, `(${l} * ${r})`); break; }
            case 'DIV': { const l = isBConst ? (parseCmt(comment) || get(B)) : get(B); const r = isCConst ? (parseCmt(comment) || get(C)) : get(C); set(A, `(${l} / ${r})`); break; }
            case 'MOD': { const l = isBConst ? (parseCmt(comment) || get(B)) : get(B); const r = isCConst ? (parseCmt(comment) || get(C)) : get(C); set(A, `(${l} % ${r})`); break; }
            case 'POW': { const l = isBConst ? (parseCmt(comment) || get(B)) : get(B); const r = isCConst ? (parseCmt(comment) || get(C)) : get(C); set(A, `(${l} ^ ${r})`); break; }
            case 'UNM': set(A, `(-${get(B)})`); break;
            case 'NOT': set(A, `(not ${get(B)})`); break;
            case 'LEN': set(A, `(#${get(B)})`); break;
            case 'CONCAT': { const p = []; for (let j = B; j <= C; j++) p.push(get(j)); set(A, `(${p.join(' .. ')})`); break; }
        }
    }

    while (indent > 0) { indent--; line('end'); }

    let result = out.join('\n');

    result = result.replace(/\(\s*([A-Za-z0-9_.:"]+)\s*\)/g, (m, inner) => {
        if (/^[A-Za-z0-9_.:"]+$/.test(inner) && !inner.includes(' ')) return inner;
        return m;
    });
    return result;
}

module.exports = { decompileLuac, decompileFromDisassembly };

if (require.main === module) {
    const fs = require('fs');
    const args = process.argv.slice(2);
    if (!args.length) { console.error('Usage: node luac_decompile.js <disassembly.txt>'); process.exit(1); }
    console.log(decompileFromDisassembly(fs.readFileSync(args[0], 'utf8')));
}
