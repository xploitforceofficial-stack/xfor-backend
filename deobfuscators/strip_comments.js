'use strict';

function longBracketLevel(src, i) {
    if (src[i] !== '[') return null;
    let j = i + 1;
    let level = 0;
    while (src[j] === '=') { level++; j++; }
    return src[j] === '[' ? level : null;
}

function scanQuoted(src, i) {
    const quote = src[i];
    let j = i + 1;
    while (j < src.length) {
        const c = src[j];
        if (c === '\\') { j += 2; continue; }
        if (c === quote) return j + 1;
        if (c === '\n') return j;
        j++;
    }
    return j;
}

function stripLuaComments(src) {
    if (typeof src !== 'string' || src.length === 0) return src;
    const n = src.length;
    let out = '';
    let i = 0;

    if (src.startsWith('#!')) {
        const nl = src.indexOf('\n');
        if (nl === -1) return src;
        out = src.slice(0, nl) + '\n';
        i = nl + 1;
    }

    while (i < n) {
        const c = src[i];

        if (c === '[') {
            const level = longBracketLevel(src, i);
            if (level !== null) {
                const close = ']' + '='.repeat(level) + ']';
                const end = src.indexOf(close, i);
                const stop = end === -1 ? n : end + close.length;
                out += src.slice(i, stop);
                i = stop;
                continue;
            }
        }

        if (c === '"' || c === "'") {
            const stop = scanQuoted(src, i);
            out += src.slice(i, stop);
            i = stop;
            continue;
        }

        if (c === '-' && src[i + 1] === '-') {
            const level = longBracketLevel(src, i + 2);
            if (level !== null) {
                const close = ']' + '='.repeat(level) + ']';
                const end = src.indexOf(close, i + 2);
                i = end === -1 ? n : end + close.length;
            } else {
                const nl = src.indexOf('\n', i);
                i = nl === -1 ? n : nl;
            }
            continue;
        }

        out += c;
        i++;
    }
    return out;
}

function stripComments(src) {
    let text = stripLuaComments(src);
    const lines = text.split('\n').map(l => l.replace(/[ \t]+$/, ''));
    const out = [];
    let blank = false;
    for (const line of lines) {
        if (line === '') {
            if (blank) continue;
            blank = true;
        } else {
            blank = false;
        }
        out.push(line);
    }
    while (out.length && out[0] === '') out.shift();
    while (out.length && out[out.length - 1] === '') out.pop();
    return out.join('\n');
}

module.exports = { stripLuaComments, stripComments };
