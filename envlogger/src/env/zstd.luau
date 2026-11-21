local Zstd = {}

local band = bit32.band
local rshift = bit32.rshift
local lshift = bit32.lshift

local ZSTD_MAGIC = 0xFD2FB528
local SKIP_MAGIC = 0x184D2A50

local HIGHBIT: { [number]: number } = { [0] = 0 }
local function highbit(v)
	if v <= 0 then
		return 0
	end
	local cached = HIGHBIT[v]
	if cached ~= nil then
		return cached
	end
	local n, x = 0, v
	while x >= 2 do
		x = math.floor(x / 2)
		n = n + 1
	end
	HIGHBIT[v] = n
	return n
end

local function newFwd(d, p)
	return { d = d, p = p, bo = 0 }
end

local function fwdPeek(st, n)
	if n == 0 then
		return 0
	end
	local v, got = 0, 0
	local p, bo, d = st.p, st.bo, st.d
	while got < n do
		local b = d:byte(p)
		if b == nil then
			b = 0
		end
		local take = 8 - bo
		local need = n - got
		if take > need then
			take = need
		end
		v = v + band(rshift(b, bo), 2 ^ take - 1) * 2 ^ got
		got = got + take
		bo = bo + take
		if bo == 8 then
			bo = 0
			p = p + 1
		end
	end
	return v
end

local function fwdRead(st, n)
	if n == 0 then
		return 0
	end
	local v = fwdPeek(st, n)
	local bo = st.bo + n
	local p = st.p
	while bo >= 8 do
		bo = bo - 8
		p = p + 1
	end
	st.bo = bo
	st.p = p
	return v
end

local function newRev(d, first, last)
	local lb = d:byte(last)
	if lb == nil then
		return nil, "empty bitstream"
	end
	if lb == 0 then
		return nil, "bitstream marker bit missing"
	end
	local hb = 7
	while band(lb, 2 ^ hb) == 0 do
		hb = hb - 1
	end
	return { d = d, first = first, bi = last, bb = hb, used = 0, over = false }, nil
end

local function revPeek(st, n)
	if n == 0 then
		return 0
	end
	local v, got = 0, 0
	local bi, bb, d = st.bi, st.bb, st.d
	while got < n do
		local take = bb
		local need = n - got
		if take > need then
			take = need
		end
if take > 0 then
			local b = d:byte(bi)
			if b == nil then
				b = 0
			end

			v = v * (2 ^ take) + band(rshift(b, bb - take), 2 ^ take - 1)
			got = got + take
			bb = bb - take
		end
		if bb == 0 then
			bi = bi - 1
			bb = 8
		end
	end
	return v
end

local function revSkip(st, n)
	local bi, bb = st.bi, st.bb
	local left = n
	while left > 0 do
		if bb == 0 then
			bi = bi - 1
			bb = 8
		end
		local take = bb
		if take > left then
			take = left
		end
		bb = bb - take
		left = left - take
	end
	if bi < st.first then
		st.over = true
	end
	st.bi = bi
	st.bb = bb
	st.used = st.used + n
end

local function revRead(st, n)
	local v = revPeek(st, n)
	revSkip(st, n)
	return v
end

local function buildFseTable(norm, maxSymbol, tableLog)
	local size = 1 * 2 ^ tableLog
	local highThreshold = size - 1
	local symNext = {}
	for s = 0, maxSymbol do
		local c = norm[s] or 0
		symNext[s] = if c == -1 then 1 else c
	end
	local sym = {}
	local step = math.floor(size / 2) + math.floor(size / 8) + 3
	local mask = size - 1
	local pos = 0

	for s = 0, maxSymbol do
		if (norm[s] or 0) == -1 then
			sym[highThreshold] = s
			highThreshold = highThreshold - 1
		end
	end
	for s = 0, maxSymbol do
		local c = norm[s] or 0
		if c > 0 then
			for _ = 1, c do
				sym[pos] = s
				pos = band(pos + step, mask)
				while pos > highThreshold do
					pos = band(pos + step, mask)
				end
			end
		end
	end
	if pos ~= 0 then
		return nil, "fse spread left holes"
	end
	for u = 0, size - 1 do
		local s = sym[u]
		if s == nil then
			return nil, "fse table hole"
		end
		local nextState = symNext[s]
		symNext[s] = nextState + 1
		local nbBitsOut = tableLog - highbit(nextState)
		sym[u] = { symbol = s, nbBits = nbBitsOut, newState = lshift(nextState, nbBitsOut) - size }
	end
	return sym, nil, tableLog
end

local function readNCount(st, maxSymbol, maxLog)
	local tableLog = fwdRead(st, 4) + 5
	if tableLog > maxLog then
		return nil, nil, "fse accuracy out of range"
	end
	local remaining = (1 * 2 ^ tableLog) + 1
	local threshold = 1 * 2 ^ tableLog
	local nbBits = tableLog + 1
	local charnum = 0
	local previous0 = false
	local norm = {}
	while remaining > 1 and charnum <= maxSymbol do
		if previous0 then
			local n0 = charnum
			while fwdPeek(st, 16) == 0xFFFF do
				n0 = n0 + 24
				fwdRead(st, 16)
			end
			while fwdPeek(st, 2) == 3 do
				n0 = n0 + 3
				fwdRead(st, 2)
			end
			n0 = n0 + fwdRead(st, 2)
			if n0 > maxSymbol + 1 then
				return nil, nil, "fse zero run past symbol range"
			end
			for i = charnum, n0 - 1 do
				norm[i] = 0
			end
			charnum = n0
			previous0 = false
		else
			local max = (2 * threshold - 1) - remaining
			local v = fwdPeek(st, nbBits)
			local count
			if band(v, threshold - 1) < max then
				count = band(v, threshold - 1)
				fwdRead(st, nbBits - 1)
			else
				count = band(v, (2 * threshold) - 1)
				if count >= threshold then
					count = count - max
				end
				fwdRead(st, nbBits)
			end
			count = count - 1
			local mag = if count < 0 then -count else count
			remaining = remaining - mag
			if charnum > maxSymbol then
				return nil, nil, "fse symbol overflow"
			end
			norm[charnum] = count
			charnum = charnum + 1
			previous0 = count == 0
			while remaining < threshold do
				nbBits = nbBits - 1
				threshold = rshift(threshold, 1)
			end
		end
	end
	if remaining ~= 1 then
		return nil, nil, "fse distribution does not sum to 1"
	end
	return norm, charnum - 1, tableLog
end

local function buildHuffTable(weights, nbSymbols)
	local total = 0
	for i = 1, nbSymbols do
		local w = weights[i]
		if w and w > 0 then
			total = total + 2 ^ (w - 1)
		end
	end
	if total == 0 then
		return nil, "empty huffman weights"
	end
	local tableLog = highbit(total) + 1
	if tableLog > 11 then
		return nil, "huffman table log too large"
	end
	local left = (1 * 2 ^ tableLog) - total
	if left <= 0 or band(left, left - 1) ~= 0 then
		return nil, "huffman weights do not complete the tree"
	end

	weights[nbSymbols + 1] = highbit(left) + 1
	nbSymbols = nbSymbols + 1

	local rankCount = {}
	for i = 1, nbSymbols do
		local w = weights[i]
		rankCount[w] = (rankCount[w] or 0) + 1
	end
	local rankStart = {}
	local next = 0
	for w = 1, tableLog + 1 do
		rankStart[w] = next
		next = next + (rankCount[w] or 0) * 2 ^ (w - 1)
	end
	if next ~= 1 * 2 ^ tableLog then
		return nil, "huffman table size mismatch"
	end

	local dt = {}
	for i = 1, nbSymbols do
		local w = weights[i]

		if w == nil or w <= 0 then
			continue
		end
		local length = 2 ^ (w - 1)
		local start = rankStart[w]
		if start == nil then
			return nil, "huffman weight out of table range"
		end
		local nbBits = tableLog + 1 - w
		for k = start, start + length - 1 do
			dt[k] = { symbol = i - 1, nbBits = nbBits }
		end
		rankStart[w] = start + length
	end
	return dt, nil, tableLog
end

local function readFseWeights(d, first, last)
	local st = newFwd(d, first)
	local norm, maxSym, tableLog = readNCount(st, 255, 6)
	if not norm then
		return nil, maxSym
	end
	local tbl = buildFseTable(norm, maxSym, tableLog)
	if not tbl then
		return nil, "bad huffman weight table"
	end

	local rst, rerr = newRev(d, first, last)
	if not rst then
		return nil, rerr
	end
	local s1 = revRead(rst, tableLog)
	local s2 = revRead(rst, tableLog)
	local weights = {}
	local n = 0
	while true do

		local e1 = tbl[s1]
		n = n + 1
		weights[n] = e1.symbol
		s1 = e1.newState + revRead(rst, e1.nbBits)
		if rst.over then
			local e2 = tbl[s2]
			n = n + 1
			weights[n] = e2.symbol
			break
		end
		local e2 = tbl[s2]
		n = n + 1
		weights[n] = e2.symbol
		s2 = e2.newState + revRead(rst, e2.nbBits)
		if rst.over then
			local e1b = tbl[s1]
			n = n + 1
			weights[n] = e1b.symbol
			break
		end
		if n > 255 then
			return nil, "too many huffman weights"
		end
	end
	return weights, n
end

local function readHuffTable(d, p, last)
	local hb = d:byte(p)
	if hb == nil then
		return nil, nil, p, "truncated huffman description"
	end
	if hb >= 128 then
		local nbSymbols = hb - 127
		local bytes = (nbSymbols + 1) // 2
		if p + bytes > last then
			return nil, nil, p, "truncated huffman weights"
		end
		local weights = {}
		for i = 1, nbSymbols do
			local byte = d:byte(p + 1 + ((i - 1) // 2))
			if i % 2 == 1 then
				weights[i] = band(byte, 15)
			else
				weights[i] = rshift(byte, 4)
			end
		end
		local dt, derr, tableLog = buildHuffTable(weights, nbSymbols)
		if not dt then
			return nil, nil, p, derr
		end
		return dt, tableLog, p + 1 + bytes
	end
	local size = hb
	if p + size > last then
		return nil, nil, p, "truncated fse huffman weights"
	end
	local weights, n = readFseWeights(d, p + 1, p + size)
	if not weights then
		return nil, nil, p, n
	end
	local dt, derr, tableLog = buildHuffTable(weights, n)
	if not dt then
		return nil, nil, p, derr
	end
	return dt, tableLog, p + 1 + size
end

local function makePreset(dist, log)
	local norm = {}
	for i = 1, #dist do
		norm[i - 1] = dist[i]
	end
	return buildFseTable(norm, #dist - 1, log)
end

local LL_PRESET = makePreset({
	4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1,
	2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1,
	-1, -1, -1, -1,
}, 6)

local ML_PRESET = makePreset({
	1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
	-1, -1, -1, -1, -1,
}, 6)

local OF_PRESET = makePreset({
	1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1,
}, 5)

local LL_BASE = {
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
	16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024,
	2048, 4096, 8192, 16384, 32768, 65536,
}
local LL_BITS = {
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
}
local ML_BASE = {
	3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
	19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
	35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027,
	2051, 4099, 8195, 16387, 32771, 65539,
}
local ML_BITS = {
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11,
	12, 13, 14, 15, 16,
}

local Buf = {}
Buf.__index = Buf

local function newBuf()
	return setmetatable({ b = {}, n = 0 }, Buf)
end

function Buf:append(src, from, count)
	local b, n = self.b, self.n

	local fromString = type(src) == "string"
	for i = 0, count - 1 do
		n = n + 1
		b[n] = if fromString then (src:byte(from + i) or 0) else (src[from + i] or 0)
	end
	self.n = n
end

function Buf:fill(byte, count)
	local b, n = self.b, self.n
	for _ = 1, count do
		n = n + 1
		b[n] = byte
	end
	self.n = n
end

function Buf:copyMatch(offset, count)
	local b, n = self.b, self.n
	local from = n - offset + 1
	if offset <= 0 or from < 1 then
		return false
	end
	for i = 0, count - 1 do
		n = n + 1
		b[n] = b[from + i]
	end
	self.n = n
	return true
end

function Buf:toString()
	local b, n = self.b, self.n
	local parts = {}
	local p = 1
	while p <= n do
		local stop = if p + 16383 > n then n else p + 16383
		local chunk = {}
		for i = p, stop do
			chunk[#chunk + 1] = string.char(b[i])
		end
		parts[#parts + 1] = table.concat(chunk)
		p = stop + 1
	end
	return table.concat(parts)
end

local function readLE(d, p, nbytes)
	local v, scale = 0, 1
	for i = 0, nbytes - 1 do
		v = v + (d:byte(p + i) or 0) * scale
		scale = scale * 256
	end

	return v
end

local function decodeLiterals(d, p, endPos, ctx)
	local lh = d:byte(p)
	if lh == nil then
		return nil, nil, p, "truncated literals header"
	end
local litType = band(lh, 3)
	local sizeFormat = band(rshift(lh, 2), 3)

	if litType <= 1 then
		local regen, hdrBytes

		if sizeFormat == 0 or sizeFormat == 2 then
			regen = rshift(lh, 3)
			hdrBytes = 1
		elseif sizeFormat == 1 then
			regen = band(rshift(readLE(d, p, 2), 4), 0xFFF)
			hdrBytes = 2
		else
			regen = band(rshift(readLE(d, p, 3), 4), 0xFFFFF)
			hdrBytes = 3
		end
		p = p + hdrBytes
		local out, n = {}, 0
		if litType == 0 then
			if p + regen - 1 > endPos then
				return nil, nil, p, "truncated raw literals"
			end
			for i = 0, regen - 1 do
				n = n + 1
				out[n] = d:byte(p + i)
			end
			p = p + regen
		else
			if p > endPos then
				return nil, nil, p, "truncated rle literals"
			end
			local byte = d:byte(p)
			p = p + 1
			for _ = 1, regen do
				n = n + 1
				out[n] = byte
			end
		end
		return out, n, p
	end

	local regen, comp, streams, hdrBytes
	if sizeFormat == 0 then
		local v = readLE(d, p, 3)
		regen = band(rshift(v, 4), 0x3FF)
		comp = band(rshift(v, 14), 0x3FF)
		streams = 1
		hdrBytes = 3
	elseif sizeFormat == 1 then
		local v = readLE(d, p, 3)
		regen = band(rshift(v, 4), 0x3FF)
		comp = band(rshift(v, 14), 0x3FF)
		streams = 4
		hdrBytes = 3
	elseif sizeFormat == 2 then
		local v = readLE(d, p, 4)
		regen = band(rshift(v, 4), 0x3FFF)
		comp = band(rshift(v, 18), 0x3FFF)
		streams = 4
		hdrBytes = 4
	else
		local v = readLE(d, p, 5)
		regen = band(rshift(v, 4), 0x3FFFF)
		comp = band(rshift(v, 22), 0x3FFFF)
		streams = 4
		hdrBytes = 5
	end
	p = p + hdrBytes

	local litStart = p

	local dt, tableLog
	if litType == 2 then
		local nextPos, derr
		dt, tableLog, nextPos, derr = readHuffTable(d, p, p + comp - 1)
		if not dt then
			return nil, nil, p, derr
		end
		ctx.huff = { table = dt, tableLog = tableLog }
		p = nextPos
	else
		local prev = ctx.huff
		if not prev then
			return nil, nil, p, "treeless literals without a previous table"
		end
		dt, tableLog = prev.table, prev.tableLog
	end

	if litStart + comp - 1 > endPos then
		return nil, nil, p, "literals exceed block"
	end
	local dataEnd = litStart + comp - 1
	local out, n = {}, 0

	if streams == 1 then
		local rst = newRev(d, p, dataEnd)		if not rst then
			return nil, nil, p, "bad literals bitstream"
		end
		for _ = 1, regen do
			local idx = revPeek(rst, tableLog)
			local e = dt[idx]
			if e == nil then
				return nil, nil, p, string.format(
					"literal code %d outside huffman table (tableLog=%d)", idx, tableLog)
			end
			revSkip(rst, e.nbBits)
			n = n + 1
			out[n] = e.symbol
		end
	else

		local jtSize = 6
		local sizes = {
			readLE(d, p, 2),
			readLE(d, p + 2, 2),
			readLE(d, p + 4, 2),
		}
		local rest = dataEnd - (p + jtSize - 1)
		if rest < 0 then
			return nil, nil, p, "literals jump table overruns block"
		end
		sizes[4] = rest - sizes[1] - sizes[2] - sizes[3]
		if sizes[4] < 0 then
			return nil, nil, p, "literals jump table overruns block"
		end
		p = p + jtSize
		local seg = (regen + 3) // 4
		local targets = { seg, seg, seg, regen - 3 * seg }
		local sp = p
		for s = 1, 4 do
			local sEnd = sp + sizes[s] - 1
			if sEnd > dataEnd then
				return nil, nil, sp, "literals jump table overruns block"
			end
			local rst = newRev(d, sp, sEnd)
			if not rst then
				return nil, nil, sp, "bad literals bitstream"
			end
			for _ = 1, targets[s] do

			local idx = revPeek(rst, tableLog)
			local e = dt[idx]
				if e == nil then
					return nil, nil, sp, string.format(
						"literal code %d outside huffman table (tableLog=%d)", idx, tableLog)
				end
				revSkip(rst, e.nbBits)
				n = n + 1
				out[n] = e.symbol
			end
			sp = sEnd + 1
		end
	end
	return out, n, dataEnd + 1
end

local function readSeqTable(d, p, mode, preset, maxSymbol, prev, presetLog)
	if mode == 0 then

		return preset, presetLog, p
	elseif mode == 1 then
		local b = d:byte(p)
		if b == nil then
			return nil, nil, p, "truncated rle fse table"
		end
		return { { symbol = b, nbBits = 0, newState = 0 } }, 0, p + 1
	elseif mode == 2 then
		local st = newFwd(d, p)
		local norm, ms, log = readNCount(st, maxSymbol, 9)
		if not norm then
			return nil, nil, p, ms
		end
		local tbl = buildFseTable(norm, ms, log)
		if not tbl then
			return nil, nil, p, "bad sequence fse table"
		end
		return tbl, log, st.p
	else
		if not prev then
			return nil, nil, p, "repeat mode without a previous table"
		end
		return prev.table, prev.log, p
	end
end

local function decodeSequences(d, p, endPos, literals, litCount, buf, ctx)
	local nbSeq
	local b0 = d:byte(p)
	if b0 == nil then
		return p, "truncated sequence count"
	end
	if b0 == 0 then

		buf:append(literals, 1, litCount)
		return endPos + 1
	elseif b0 < 128 then
		nbSeq = b0
		p = p + 1
	elseif b0 < 255 then
		nbSeq = (b0 - 128) * 256 + (d:byte(p + 1) or 0)
		p = p + 2
	else
		nbSeq = (d:byte(p + 1) or 0) + (d:byte(p + 2) or 0) * 256 + 0x7F00
		p = p + 3
	end

	if nbSeq == 0 then
		buf:append(literals, 1, litCount)
		return endPos + 1
	end

	local scm = d:byte(p)
	if scm == nil then
		return p, "truncated symbol compression modes"
	end
	p = p + 1
	local llMode = band(rshift(scm, 4), 3)
	local ofMode = band(rshift(scm, 2), 3)
	local mlMode = band(scm, 3)

	local llTbl, llLog, p2, e1 = readSeqTable(d, p, llMode, LL_PRESET, 35, ctx.ll, 6)
	if not llTbl then
		return p2, e1
	end
	p = p2
	local ofTbl, ofLog, p3, e2 = readSeqTable(d, p, ofMode, OF_PRESET, 31, ctx.of, 5)
	if not ofTbl then
		return p3, e2
	end
	p = p3
	local mlTbl, mlLog, p4, e3 = readSeqTable(d, p, mlMode, ML_PRESET, 52, ctx.ml, 6)
	if not mlTbl then
		return p4, e3
	end
	p = p4

	ctx.ll = { table = llTbl, log = llLog }
	ctx.of = { table = ofTbl, log = ofLog }
	ctx.ml = { table = mlTbl, log = mlLog }

	local rst = newRev(d, p, endPos)
	if not rst then
		return p, "bad sequence bitstream"
	end

local llState = revRead(rst, llLog)
	local ofState = revRead(rst, ofLog)
	local mlState = revRead(rst, mlLog)

	local rep1, rep2, rep3 = 1, 4, 8
	local litPos = 1

	for _ = 1, nbSeq do
		local lle = llTbl[llState]
		local ofe = ofTbl[ofState]
		local mle = mlTbl[mlState]
		local llCode = lle.symbol
		local ofCode = ofe.symbol
		local mlCode = mle.symbol

		local offsetValue
		if ofCode > 1 then
			offsetValue = 2 ^ ofCode + revRead(rst, ofCode)
		else
			offsetValue = ofCode + 1
		end
		local matchLength = ML_BASE[mlCode + 1] + revRead(rst, ML_BITS[mlCode + 1])
		local literalLength = LL_BASE[llCode + 1] + revRead(rst, LL_BITS[llCode + 1])

		llState = lle.newState + revRead(rst, lle.nbBits)
		mlState = mle.newState + revRead(rst, mle.nbBits)
		ofState = ofe.newState + revRead(rst, ofe.nbBits)

		local offset
		if offsetValue > 3 then
			offset = offsetValue - 3
			rep3, rep2, rep1 = rep2, rep1, offset
		else
			local idx = offsetValue
			if literalLength == 0 then
				idx = idx + 1
			end
			if idx == 1 then
				offset = rep1
			elseif idx == 2 then
				offset = rep2
				rep2 = rep1
				rep1 = offset
			elseif idx == 3 then
				offset = rep3
				rep3 = rep2
				rep2 = rep1
				rep1 = offset
			else
				offset = rep1 - 1
				rep3, rep2, rep1 = rep2, rep1, offset
			end
		end
		if offset <= 0 then
			return p, "invalid repeat offset"
		end

		if literalLength > 0 then
			if litPos + literalLength - 1 > litCount then
				return p, "literal run past end of literals"
			end
			buf:append(literals, litPos, literalLength)
			litPos = litPos + literalLength
		end
		if not buf:copyMatch(offset, matchLength) then
			return p, "match offset " .. tostring(offset) .. " before start of output"
		end
	end

	if litPos <= litCount then
		buf:append(literals, litPos, litCount - litPos + 1)
	end
	return endPos + 1
end

local function decodeCompressedBlock(d, p, endPos, buf, ctx)
	local literals, litCount, np, err = decodeLiterals(d, p, endPos, ctx)
	if not literals then
		return err
	end
	local np2, err2 = decodeSequences(d, np, endPos, literals, litCount, buf, ctx)
	if err2 then
		return err2
	end
	return nil
end

local function decodeFrame(d, p, buf, ctx)
	local n = #d
	if p + 3 > n then
		return p, "truncated frame magic"
	end
	local magic = readLE(d, p, 4)
	if magic == SKIP_MAGIC then
		if p + 7 > n then
			return p, "truncated skippable frame"
		end
		return p + 8 + readLE(d, p + 4, 4)
	end
	if magic ~= ZSTD_MAGIC then
		return p, "not a zstd frame"
	end
	p = p + 4

	local fhd = d:byte(p)
	if fhd == nil then
		return p, "truncated frame header"
	end
	p = p + 1
	local fcsFlag = rshift(fhd, 6)
	local singleSegment = band(rshift(fhd, 5), 1) == 1
	local checksum = band(rshift(fhd, 2), 1) == 1
	local didFlag = band(fhd, 3)

	if not singleSegment then
		if p > n then
			return p, "truncated window descriptor"
		end
		p = p + 1
	end
	if didFlag ~= 0 then
		p = p + ({ [1] = 1, [2] = 2, [3] = 4 })[didFlag]
	end

local fcsSize = ({ [0] = if singleSegment then 1 else 0, [1] = 2, [2] = 4, [3] = 8 })[fcsFlag]
	p = p + fcsSize

	ctx.ll, ctx.of, ctx.ml, ctx.huff = nil, nil, nil, nil

	while true do
		if p + 2 > n then
			return p, "truncated block header"
		end
		local bh = readLE(d, p, 3)
		p = p + 3
local last = band(bh, 1) == 1
		local btype = band(rshift(bh, 1), 3)
		local bsize = rshift(bh, 3)

		if btype == 0 then
			if p + bsize - 1 > n then
				return p, "truncated raw block"
			end
			buf:append(d, p, bsize)
			p = p + bsize
		elseif btype == 1 then
			if p > n then
				return p, "truncated rle block"
			end
			buf:fill(d:byte(p), bsize)
			p = p + 1
		elseif btype == 2 then
			if p + bsize - 1 > n then
				return p, "truncated compressed block"
			end
			local err = decodeCompressedBlock(d, p, p + bsize - 1, buf, ctx)
			if err then
				return p, err
			end
			p = p + bsize
		else
			return p, "reserved block type"
		end
		if last then
			break
		end
	end

	if checksum then
		p = p + 4
	end
	return p
end

function Zstd.decompress(data)
	if type(data) ~= "string" or #data < 4 then
		return nil, "input too small to be a zstd frame"
	end
	local buf = newBuf()
	local ctx = {}
	local p = 1
	while p <= #data do
		local np, err = decodeFrame(data, p, buf, ctx)
		if err then
			return nil, err
		end
		if np <= p then
			return nil, "frame decoder made no progress"
		end
		p = np
	end
	return buf:toString()
end

function Zstd.isFrame(data)
	if type(data) ~= "string" or #data < 4 then
		return false
	end
	return readLE(data, 1, 4) == ZSTD_MAGIC or readLE(data, 1, 4) == SKIP_MAGIC
end

return Zstd
