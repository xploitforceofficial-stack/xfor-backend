'use strict';

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const axios = require('axios');
const { deobfuscateUnified, detectObfuscator } = require('./engine');
const { searchUnifiedScripts } = require('./scrapers');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));

// In-memory cache for deobfuscation results (saves CPU & memory)
const deobfCache = new Map();
const DEOBF_CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour

// Rate limiter for obfuscator (10 requests per user/IP window)
const userObfRequests = new Map();
const OBF_LIMIT = 10;
const OBF_WINDOW_MS = 60 * 60 * 1000; // 1 hour window

function checkObfRateLimit(userKey) {
    const now = Date.now();
    const records = userObfRequests.get(userKey) || [];
    const valid = records.filter(ts => now - ts < OBF_WINDOW_MS);
    userObfRequests.set(userKey, valid);

    if (valid.length >= OBF_LIMIT) {
        const oldest = valid[0];
        const resetSeconds = Math.ceil((oldest + OBF_WINDOW_MS - now) / 1000);
        return { allowed: false, remaining: 0, resetSeconds };
    }

    valid.push(now);
    userObfRequests.set(userKey, valid);
    return { allowed: true, remaining: OBF_LIMIT - valid.length, resetSeconds: 0 };
}

// Health check
app.get('/', (req, res) => {
    res.json({
        status: 'online',
        service: 'XFOR Backend & Community XploitForce Engine',
        uptime: process.uptime(),
        timestamp: new Date().toISOString()
    });
});

app.get('/health', (req, res) => {
    res.json({ status: 'ok', uptime: process.uptime() });
});

// Detection endpoint
app.post('/api/detect', (req, res) => {
    try {
        const { script } = req.body;
        if (!script || typeof script !== 'string') {
            return res.status(400).json({ error: 'Missing script parameter' });
        }
        const detection = detectObfuscator(script);
        res.json({ success: true, detection });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

// Deobfuscate endpoint
app.post('/api/deobfuscate', async (req, res) => {
    try {
        const { script, engine = 'auto', filename = 'script.lua' } = req.body;
        if (!script || typeof script !== 'string' || script.trim().length === 0) {
            return res.status(400).json({ success: false, error: 'Empty script payload' });
        }

        // Generate cache key based on content hash and engine
        const hash = crypto.createHash('sha256').update(script).digest('hex').slice(0, 32);
        const cacheKey = `${engine}:${hash}`;

        const cached = deobfCache.get(cacheKey);
        if (cached && (Date.now() - cached.timestamp < DEOBF_CACHE_TTL_MS)) {
            return res.json({
                ...cached.data,
                cached: true
            });
        }

        const result = await deobfuscateUnified(script, engine, filename);
        if (result.success && result.code) {
            deobfCache.set(cacheKey, { timestamp: Date.now(), data: result });
        }

        res.json(result);
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

// PVM Obfuscator API endpoint
app.post('/api/obfuscate', async (req, res) => {
    try {
        const { script, mode = 'utmost', userKey = 'anonymous' } = req.body;
        if (!script || typeof script !== 'string' || script.trim().length === 0) {
            return res.status(400).json({ success: false, error: 'Empty script payload' });
        }

        // Check 10 requests per user/IP limit
        const limitCheck = checkObfRateLimit(userKey);
        if (!limitCheck.allowed) {
            return res.status(429).json({
                success: false,
                error: `Batas kuota tercapai: Maksimal ${OBF_LIMIT} request per jam. Coba lagi dalam ${limitCheck.resetSeconds} detik.`,
                rateLimit: limitCheck
            });
        }

        const pvmUrl = 'https://www.pvmobf.web.id/api/v1/obfuscate?api_key=5GdrEbXnhurIVHG1qvjXyXei23W4eglz';
        const pvmRes = await axios.post(pvmUrl, {
            script,
            mode
        }, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 30000
        });

        const data = pvmRes.data;
        res.json({
            success: data.success || true,
            result: data.result || '',
            mode: data.mode || mode,
            stats: data.stats || {},
            rateLimit: {
                remaining: limitCheck.remaining,
                limit: OBF_LIMIT
            }
        });
    } catch (err) {
        res.status(500).json({
            success: false,
            error: err.response?.data?.message || err.message || 'Obfuscation API failed'
        });
    }
});

// Script Search endpoint (Cheater.fun + Rscripts + ScriptBlox)
app.get('/api/scripts/search', async (req, res) => {
    try {
        const q = String(req.query.q || '').trim();
        const limit = parseInt(req.query.limit, 10) || 10;
        if (!q) {
            return res.status(400).json({ error: 'Query parameter "q" is required' });
        }
        const data = await searchUnifiedScripts(q, limit);
        res.json(data);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`[XFOR-BACKEND] 🚀 Server running on port ${PORT}`);
});
