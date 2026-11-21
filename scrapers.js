'use strict';

const axios = require('axios');
const cheerio = require('cheerio');

// In-memory cache for search results
const searchCache = new Map();
const SEARCH_CACHE_TTL_MS = 15 * 60 * 1000; // 15 minutes

const SCRIPTBLOX_API_URL = 'https://scriptblox.com/api';
const HAXHELL_API_URL = 'https://haxhell.com/api/v1';

async function scrapeCheaterFun(query, maxResults = 5) {
    try {
        const cleanQuery = encodeURIComponent(query.trim().toLowerCase());
        const searchUrl = `https://cheater.fun/index.php?do=search&subaction=search&story=${cleanQuery}`;

        const searchRes = await axios.get(searchUrl, {
            headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
            },
            timeout: 12000
        });

        const $ = cheerio.load(searchRes.data);
        const articleLinks = [];

        $('article a, .news-title a, .post-title a, .story a').each((_, el) => {
            const href = $(el).attr('href');
            const title = $(el).text().trim();
            if (href && href.includes('cheater.fun') && href.endsWith('.html') && !articleLinks.some(a => a.href === href)) {
                if (!href.includes('/user/') && !href.includes('/engine/')) {
                    articleLinks.push({ href, title });
                }
            }
        });

        const limitedLinks = articleLinks.slice(0, Math.min(articleLinks.length, maxResults));
        const results = [];

        await Promise.allSettled(limitedLinks.map(async (art) => {
            try {
                const pageRes = await axios.get(art.href, {
                    headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' },
                    timeout: 8000
                });

                const page$ = cheerio.load(pageRes.data);
                let loadstringCode = '';

                // Check copy-script div
                const copyDiv = page$('div.copy-script, div.script-code, pre.code, pre code, textarea.copy-script').first();
                if (copyDiv.length > 0) {
                    loadstringCode = copyDiv.text().trim();
                }

                if (!loadstringCode) {
                    const match = pageRes.data.match(/loadstring\s*\(\s*game\s*:\s*HttpGet\s*\([^)]+\)\s*\)\s*\(\s*\)/i)
                        || pageRes.data.match(/loadstring\s*\([^)]+\)\s*\(\s*\)/i);
                    if (match) loadstringCode = match[0];
                }

                if (loadstringCode) {
                    let imgUrl = '';
                    const mainImg = page$('article img, .story-img img, .post img').first();
                    if (mainImg.length > 0) {
                        imgUrl = mainImg.attr('src') || '';
                        if (imgUrl.startsWith('/')) imgUrl = `https://cheater.fun${imgUrl}`;
                    }

                    results.push({
                        hub: art.title.replace(/\s*Roblox\s*Script.*$/i, '').trim() || 'Cheater.fun Script',
                        script: loadstringCode,
                        source: 'Cheater.fun',
                        image: imgUrl,
                        url: art.href
                    });
                }
            } catch (_) {}
        }));

        return results;
    } catch (_) {
        return [];
    }
}

async function fetchRscripts(query, maxResults = 5) {
    try {
        const cleanQuery = encodeURIComponent(query.trim());
        const res = await axios.get(`https://rscripts.net/api/v2/scripts?q=${cleanQuery}&page=1`, {
            headers: { 'User-Agent': 'Mozilla/5.0' },
            timeout: 8000
        });

        const list = res.data?.scripts || res.data?.data || [];
        if (!Array.isArray(list)) return [];

        const results = [];
        for (const s of list.slice(0, maxResults)) {
            const rawCode = s.rawScript || s.script || (s.slug ? `loadstring(game:HttpGet("https://rscripts.net/raw/${s.slug}"))()` : '');
            if (rawCode) {
                results.push({
                    hub: s.title || s.name || 'Rscripts Script',
                    script: rawCode,
                    source: 'rscripts.net',
                    image: s.thumbnail || s.image || '',
                    views: s.views || 0
                });
            }
        }
        return results;
    } catch (_) {
        return [];
    }
}

async function fetchScriptBlox(query, maxResults = 5) {
    try {
        const cleanQuery = encodeURIComponent(query.trim());
        const res = await axios.get(`${SCRIPTBLOX_API_URL}/script/search?q=${cleanQuery}&mode=free`, {
            headers: { 'User-Agent': 'Mozilla/5.0' },
            timeout: 8000
        });

        const list = res.data?.result?.scripts || [];
        if (!Array.isArray(list)) return [];

        const results = [];
        for (const s of list.slice(0, maxResults)) {
            if (s.script) {
                let img = s.image ? (s.image.startsWith('http') ? s.image : `https://scriptblox.com${s.image}`) : '';
                results.push({
                    hub: s.title || 'ScriptBlox Script',
                    script: s.script,
                    source: 'ScriptBlox',
                    image: img,
                    verified: s.verified || false
                });
            }
        }
        return results;
    } catch (_) {
        return [];
    }
}

async function searchUnifiedScripts(query, limit = 10) {
    const cacheKey = String(query).trim().toLowerCase();
    const cached = searchCache.get(cacheKey);
    if (cached && (Date.now() - cached.timestamp < SEARCH_CACHE_TTL_MS)) {
        return cached.data;
    }

    const [cf, rs, sb] = await Promise.allSettled([
        scrapeCheaterFun(query, 5),
        fetchRscripts(query, 5),
        fetchScriptBlox(query, 5)
    ]);

    const cfList = cf.status === 'fulfilled' ? cf.value : [];
    const rsList = rs.status === 'fulfilled' ? rs.value : [];
    const sbList = sb.status === 'fulfilled' ? sb.value : [];

    const merged = [];
    const seen = new Set();

    for (const item of [...cfList, ...rsList, ...sbList]) {
        const key = item.script.slice(0, 80);
        if (!seen.has(key)) {
            seen.add(key);
            merged.push(item);
        }
        if (merged.length >= limit) break;
    }

    const response = {
        query,
        count: merged.length,
        scripts: merged
    };

    searchCache.set(cacheKey, { timestamp: Date.now(), data: response });
    return response;
}

module.exports = {
    searchUnifiedScripts
};
