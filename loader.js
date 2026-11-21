'use strict';

const { asu } = require('./security');

const URL_RE = /https?:\/\/[^\s"'`\\)\]}<>,;]+/g;

const FETCH_PATTERNS = [
    { re: /\bgame\s*:\s*HttpGetAsync\s*\(/i, kind: 'game:HttpGetAsync' },
    { re: /\bgame\s*:\s*HttpGet\s*\(/i, kind: 'game:HttpGet' },
    { re: /\bHttpGet\s*\(/i, kind: 'HttpGet' },
    { re: /\bsyn\s*\.\s*request\s*\(/i, kind: 'syn.request' },
    { re: /\bhttp\s*\.\s*request\s*\(/i, kind: 'http.request' },
    { re: /\bhttp_request\s*\(/i, kind: 'http_request' },
    { re: /\bfluxus\s*\.\s*request\s*\(/i, kind: 'fluxus.request' },
    { re: /\brequest\s*\(\s*\{/i, kind: 'request{}' },
    { re: /:\s*GetAsync\s*\(/i, kind: 'HttpService:GetAsync' },
    { re: /:\s*RequestAsync\s*\(/i, kind: 'HttpService:RequestAsync' },
    { re: /\bHttpService\b/i, kind: 'HttpService' },
];

const EXEC_PATTERNS = [
    { re: /\bloadstring\s*\(/i, kind: 'loadstring' },
    { re: /\bload\s*\(/i, kind: 'load' },
    { re: /\brequire\s*\(\s*\d{5,}\s*\)/, kind: 'require(assetId)' },
];

function stripComments(src) {
    let s = src;

    s = s.replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, ' ');

    s = s.replace(/--[^\n]*/g, ' ');
    return s;
}

function trimUrl(u) {

    return u.replace(/[.,;:!?'"`)\]}\\]+$/, '');
}

const STRING_RE = /\[(=*)\[([\s\S]*?)\]\1\]|"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'/g;

function stringLiterals(src) {
    const out = [];
    let m;
    STRING_RE.lastIndex = 0;
    while ((m = STRING_RE.exec(src)) !== null) {
        out.push(m[2] !== undefined ? m[2] : (m[3] !== undefined ? m[3] : m[4]));
    }
    return out;
}

const NEVER_FETCH = /(?:discord(?:app)?\.com\/api\/|discord\.com\/api\/webhooks|\/api\/webhooks\/|googleapis\.com|google-analytics|sentry\.io|\.png$|\.jpe?g$|\.gif$|\.ico$|\.mp3$|\.ogg$|\.webp$)/i;
const RAW_HOSTS = /(?:raw\.githubusercontent\.com|gist\.githubusercontent\.com|pastebin\.com|pastefy\.app|rentry\.co|hastebin\.com|controlc\.com|cdn\.jsdelivr\.net|paste\.[a-z]+|api\.luarmor\.net)/i;

function scoreUrl(u) {
    let s = 0;
    if (NEVER_FETCH.test(u)) return -100;
    if (/\.luau?(?:\?|$)/i.test(u)) s += 5;
    if (/\.txt(?:\?|$)/i.test(u)) s += 3;
    if (RAW_HOSTS.test(u)) s += 3;
    if (/\/raw\

    if (/^https?:\/\/[^/]+\/?$/.test(u)) s -= 20;
    return s;
}

function extractUrls(content) {
    const seen = new Set();
    const out = [];
    const push = (raw) => {
        const u = trimUrl(raw);
        if (u.length < 12 || seen.has(u)) return;
        seen.add(u);
        out.push(u);
    };

    for (const lit of stringLiterals(content)) {
        if (typeof lit !== 'string' || lit.indexOf('http') < 0) continue;
        const re = /https?:\/\/[^\s\\]+/g;
        let m;
        while ((m = re.exec(lit)) !== null) push(m[0]);
    }

    const outside = content.replace(STRING_RE, ' ');
    URL_RE.lastIndex = 0;
    let m;
    while ((m = URL_RE.exec(outside)) !== null) push(m[0]);

    return out.slice(0, 12);
}

function scriptUrls(urls) {
    const scored = urls.map(u => ({ u, s: scoreUrl(u) })).filter(x => x.s > -50);
    scored.sort((a, b) => b.s - a.s);
    return scored.map(x => x.u);
}

function loaderRemainder(content) {
    let s = stripComments(content);

    s = s.replace(/\[(=*)\[[\s\S]*?\]\1\]/g, '""');
    s = s.replace(/"(?:\\.|[^"\\])*"/g, '""');
    s = s.replace(/'(?:\\.|[^'\\])*'/g, '""');
    s = s.replace(/\s+/g, '');

    let prev = null;
    for (let guard = 0; guard < 40 && prev !== s; guard++) {
        prev = s;

        s = s.replace(/(?:\w+)?:?GetService\(""\)/g, '~');

        s = s.replace(/[\w.~]*[:.](?:HttpGetAsync|HttpGet|GetAsync|RequestAsync)\((?:""|\w+)(?:,(?:true|false))?\)/g, '""');
        s = s.replace(/\bHttpGet\((?:""|\w+)(?:,(?:true|false))?\)/g, '""');
        s = s.replace(/[\w.~]*\brequest\(\{[^{}]*\}\)/g, '{}');
        s = s.replace(/\bhttp_request\(\{[^{}]*\}\)/g, '{}');
        s = s.replace(/\{\}(?:\.Body|\[""\])/g, '""');

        s = s.replace(/\b(?:loadstring|load)\((?:""|\w+)(?:,(?:""|\w+))?\)/g, '@');
        s = s.replace(/\breadfile\((?:""|\w+)\)/g, '""');

        s = s.replace(/@\((?:|""|\w+)\)/g, '');

        s = s.replace(/\blocal[\w,]*=/g, '');
        s = s.replace(/^return/g, '');
        s = s.replace(/[;()~@]/g, '');

        s = s.replace(/^[A-Za-z_]\w{0,2}$/g, '');
    }
    return s;
}

function vetUrls(urls) {
    const blocked = [];
    const denied = new Set();
    for (const url of urls) {
        const vetted = asu(url);
        if (vetted.ok) continue;
        blocked.push({ url, reason: vetted.reason });
        denied.add(url);
    }
    return { fetchable: scriptUrls(urls).filter(u => !denied.has(u)), blocked };
}

function detectLoader(content) {
    const src = String(content || '');
    const stripped = stripComments(src);
    const urls = extractUrls(stripped);
    const fetchKinds = FETCH_PATTERNS.filter(p => p.re.test(stripped)).map(p => p.kind);
    const execKinds = EXEC_PATTERNS.filter(p => p.re.test(stripped)).map(p => p.kind);

    const bareUrl = urls.length === 1 && stripped.trim().replace(/[;\s]+$/, '') === urls[0];

    const tooBig = src.length > 8000;
    const remainder = (bareUrl || tooBig) ? '' : loaderRemainder(src);

    const isLoader = bareUrl || (urls.length > 0 && (fetchKinds.length > 0 || execKinds.length > 0));

    const isPureLoader = isLoader && (bareUrl || (!tooBig && remainder.length <= 24));

    const localLoader = !isLoader && execKinds.length > 0 &&
        (/\breadfile\s*\(/i.test(stripped) || /\brequire\s*\(\s*\d{5,}\s*\)/.test(stripped));

    const { fetchable, blocked } = vetUrls(urls);

    return {
        urls, fetchable, blocked, fetchKinds, execKinds,
        isLoader, isPureLoader, localLoader, remainder, bareUrl,
    };
}

module.exports = { detectLoader, extractUrls, scriptUrls, vetUrls, loaderRemainder, stripComments };
