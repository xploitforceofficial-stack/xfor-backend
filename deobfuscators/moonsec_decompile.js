'use strict';

function parseDisassembly(text) {
    const functions = [];
    let cur = null;
    for (const raw of text.split(/\r?\n/)) {
        const line = raw.replace(/\r/g, '');
        if (line.match(/^function\s+(\w+)\(\.\.\.\)/)) {
            cur = { name: RegExp.$1, instrs: [] };
            functions.push(cur);
            continue;
        }
        if (!cur) continue;
        const m = line.match(/^\t\[\s*(\d+)\]\s+(\w+)\s*\|\s*(-?\d+)\s*\|\s*(-?\d+)\s*\|\s*(-?\d+)\s*\|\s*(.*)$/);
        if (m) {
            cur.instrs.push({ pc: +m[1], op: m[2], a: +m[3], b: +m[4], c: +m[5], comment: m[6].trim() });
            continue;
        }
        if (line.trim() === 'end') cur = null;
    }
    return functions;
}

function decompileFunction(func) {
    const regs = {};
    const regMethod = {};
    const tableFields = {};
    const out = [];
    let indent = 0;
    const blocks = [];

    function get(r) { return regs[r] !== undefined ? regs[r] : `R${r}`; }
    function set(r, expr) { regs[r] = expr; }
    function clear(r) { delete regs[r]; delete regMethod[r]; delete tableFields[r]; }
    function line(s) { out.push('  '.repeat(indent) + s); }
    function resolve(s) { return s.replace(/R(\d+)/g, (_, rn) => get(+rn)); }

    function splitArgs(s) {
        if (!s || !s.trim()) return [];
        const result = []; let depth = 0, cur = '';
        for (const ch of s) {
            if (ch === '(') depth++;
            else if (ch === ')') depth--;
            if (ch === ',' && depth === 0) { result.push(cur.trim()); cur = ''; continue; }
            cur += ch;
        }
        if (cur.trim()) result.push(cur.trim());
        return result;
    }

    function emitTableConstructor(reg) {
        const fields = tableFields[reg];
        if (!fields || !fields.length) return '{}';
        const lines = fields.map(f => `${f.key} = ${f.value}`);
        delete tableFields[reg];
        if (lines.join(', ').length < 60) {
            return `{ ${lines.join(', ')} }`;
        }
        const ind = '  '.repeat(indent + 1);
        return `{\n${ind}${lines.join(',\n' + ind)},\n${'  '.repeat(indent)}}`;
    }

    for (let i = 0; i < func.instrs.length; i++) {
        const ins = func.instrs[i];
        const { op, a, b, c, comment } = ins;

        switch (op) {

            case 'GetGlobal': {
                const m = comment.match(/^R(\d+)\s*=\s*(.+)$/);
                if (m) set(+m[1], m[2].trim());
                break;
            }

            case 'SetGlobal': {
                const m = comment.match(/^(\w+)\s*=\s*R(\d+)$/);
                if (m) line(`${m[1]} = ${get(+m[2])};`);
                break;
            }

            case 'LoadK': {
                const m = comment.match(/^R(\d+)\s*=\s*(.+)$/);
                if (m) set(+m[1], m[2].trim());
                break;
            }

            case 'LoadBool': {
                const m = comment.match(/^R(\d+)\s*=\s*(true|false)$/);
                if (m && c === 0) set(+m[1], m[2]);
                break;
            }

            case 'Self': {
                const m = comment.match(/R(\d+)\s*=\s*R(\d+);\s*R(\d+)\s*=\s*R(\d+)\["(.+)"\]/);
                if (m) {
                    const selfReg = +m[1];
                    const methodReg = +m[3];
                    const objReg = +m[4];
                    const methodName = m[5];
                    set(selfReg, get(objReg));
                    set(methodReg, `${get(objReg)}:${methodName}`);
                    regMethod[methodReg] = { selfArg: selfReg };
                }
                break;
            }

            case 'NewTable': {
                set(a, '{}');
                tableFields[a] = [];
                break;
            }

            case 'GetTable': {
                const m = comment.match(/^R(\d+)\s*=\s*(.+)$/);
                if (m) {
                    const dest = +m[1];
                    let expr = m[2].trim();
                    const srcMatch = expr.match(/^R(\d+)\[(.+)\]$/);
                    if (srcMatch) {
                        const srcReg = +srcMatch[1];
                        const key = srcMatch[2];
                        if (tableFields[srcReg] && tableFields[srcReg].length > 0) {
                            set(dest, `${emitTableConstructor(srcReg)}[${key}]`);
                        } else {
                            set(dest, resolve(expr));
                        }
                    } else {
                        set(dest, resolve(expr));
                    }
                }
                break;
            }

            case 'SetTable': {
                const m = comment.match(/^(.+?)\s*=\s*(.+)$/);
                if (m) {
                    const lhs = m[1].trim();
                    const rhs = m[2].trim();
                    const fieldMatch = lhs.match(/^R(\d+)\["(.+)"\]$/);
                    if (fieldMatch) {
                        const tReg = +fieldMatch[1];
                        const key = fieldMatch[2];
                        const value = resolve(rhs);
                        if (tableFields[tReg]) {
                            tableFields[tReg].push({ key: `"${key}"`, value });
                        } else {
                            line(`${resolve(lhs)} = ${resolve(rhs)};`);
                        }
                    } else {
                        line(`${resolve(lhs)} = ${resolve(rhs)};`);
                    }
                }
                break;
            }

            case 'Call': {
                const trimmed = comment.trim();

                const topM = trimmed.match(/^(R(\d+))->top\s*=\s*R(\d+)\((.*)\)$/);
                if (topM) {
                    const destReg = +topM[2];
                    const funcReg = +topM[3];
                    const rawArgs = topM[4].trim();
                    const funcExpr = get(funcReg);
                    const info = regMethod[funcReg];

                    if (info) {
                        const selfRegStr = `R${info.selfArg}`;
                        const selfExpr = get(info.selfArg);
                        const args = splitArgs(rawArgs).map(a => resolve(a)).filter(a => a !== selfRegStr && a !== selfExpr);
                        set(destReg, `${funcExpr}(${args.join(', ')})`);
                    } else {
                        set(destReg, `${funcExpr}(${resolve(rawArgs)})`);
                    }
                    break;
                }

                const retTop = trimmed.match(/^(R(\d+))\s*=\s*R(\d+)\(R(\d+)->top\)$/);
                if (retTop) {
                    const dest = +retTop[2];
                    const funcReg = +retTop[3];
                    const srcReg = +retTop[4];
                    set(dest, `${get(funcReg)}(${get(srcReg)})`);
                    break;
                }

                const retSimple = trimmed.match(/^(R(\d+))\s*=\s*R(\d+)\(\)$/);
                if (retSimple) {
                    const dest = +retSimple[2];
                    const funcReg = +retSimple[3];
                    set(dest, `${get(funcReg)}()`);
                    break;
                }

                const voidArgs = trimmed.match(/^R(\d+)\((.+)\)$/);
                if (voidArgs) {
                    const funcReg = +voidArgs[1];
                    const rawArgs = voidArgs[2].trim();
                    const info = regMethod[funcReg];
                    const funcExpr = get(funcReg);

                    let args = splitArgs(rawArgs).map(a => {
                        const t = a.trim();
                        const regM = t.match(/^R(\d+)$/);
                        if (regM && tableFields[+regM[1]] && tableFields[+regM[1]].length > 0) {
                            return emitTableConstructor(+regM[1]);
                        }
                        return resolve(t);
                    });

                    if (info) {
                        const selfRegStr = `R${info.selfArg}`;
                        const selfExpr = get(info.selfArg);
                        args = args.filter(a => a !== selfRegStr && a !== selfExpr);
                        line(`${funcExpr}(${args.join(', ')});`);
                    } else {
                        line(`${funcExpr}(${args.join(', ')});`);
                    }

                    for (const a of splitArgs(rawArgs)) {
                        const regM = a.trim().match(/^R(\d+)$/);
                        if (regM) clear(+regM[1]);
                    }
                    clear(funcReg);
                    break;
                }

                const voidCall = trimmed.match(/^R(\d+)\(\)$/);
                if (voidCall) {
                    line(`${get(+voidCall[1])}();`);
                    break;
                }

                break;
            }

            case 'Return': {
                const m = comment.match(/^return\s*(.*)/);
                const args = m ? m[1].trim() : '';
                if (args) line(`return ${resolve(args)};`);
                else line('return;');
                break;
            }

            case 'Test': {
                const m = comment.match(/^if\s+(.+?)\s+then/);
                if (m) { line(`if ${resolve(m[1])} then`); indent++; blocks.push('if'); }
                break;
            }

            case 'Eq': {
                const m = comment.match(/^if\s+(.+?)\s+then/);
                if (m) { line(`if ${resolve(m[1])} then`); indent++; blocks.push('if'); }
                break;
            }

            case 'Jmp': {
                const m = comment.match(/PC\s*\+=\s*(-?\d+)/);
                if (m) {
                    const offset = parseInt(m[1]);
                    if (offset < 0 && blocks.length > 0) {
                        blocks.pop();
                        indent = Math.max(0, indent - 1);
                        line('end');
                    }
                }
                break;
            }

            default: {
                if (comment && comment.trim()) line(`-- ${op}: ${resolve(comment)}`);
                break;
            }
        }
    }

    while (blocks.length > 0) { blocks.pop(); indent = Math.max(0, indent - 1); line('end'); }
    return out.join('\n');
}

function decompile(disassembly) {
    return parseDisassembly(disassembly).map(f => decompileFunction(f)).join('\n\n');
}

module.exports = { decompile, parseDisassembly, decompileFunction };

if (require.main === module) {
    const fs = require('fs');
    const args = process.argv.slice(2);
    if (!args.length) { console.error('Usage: node moonsec_decompile.js <file>'); process.exit(1); }
    console.log(decompile(fs.readFileSync(args[0], 'utf8')));
}
