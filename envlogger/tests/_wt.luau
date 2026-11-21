local fs = require("@lune/fs")
if _G ~= nil then
	rawset(_G :: any, "__ENVNILLOG", true)
end
local Instrument = require("../src/core/instrument")
local Sandbox = require("../src/core/sandbox")

local zlib: any = nil
do
	local ok, loaded = pcall(function()
		return require("../../zlib")
	end)
	if ok then
		zlib = loaded
	end
end

local src = fs.readFile("../Samples/Luraph/luraph-v14.7.lua")

local BREAKERS = {
	[";"] = true, ["end"] = true, ["else"] = true, ["elseif"] = true,
	["do"] = true, ["then"] = true, ["repeat"] = true, ["until"] = true,
	["return"] = true, ["local"] = true, ["function"] = true, ["if"] = true,
	["for"] = true, ["while"] = true,
}
local NO_AFTER = { ["return"] = true, ["break"] = true, ["continue"] = true }

local tokens = Instrument.tokenize(src)
local out = {}
local lineOrigStart = { 1 }
local cursor = 1
local prevRaw = nil
for _, tok in ipairs(tokens) do
	local finish = tok.start + #tok.raw - 1
	if tok.start > cursor then
		local seg = src:sub(cursor, tok.start - 1)
		out[#out + 1] = seg
		local checkFrom = 1
		while true do
			local nl = seg:find("\n", checkFrom, true)
			if not nl then
				break
			end
			lineOrigStart[#lineOrigStart + 1] = cursor + nl
			checkFrom = nl + 1
		end
		cursor = tok.start
	end
	local raw = tok.raw
	local isBr = BREAKERS[raw] == true
	local danger = prevRaw ~= nil and NO_AFTER[prevRaw] == true and (raw == "function" or raw == "if")
	if isBr and not danger then
		out[#out + 1] = "\n"
		lineOrigStart[#lineOrigStart + 1] = tok.start
	end
	out[#out + 1] = raw
	cursor = finish + 1
	prevRaw = raw
end
if cursor <= #src then
	out[#out + 1] = src:sub(cursor)
end
local mapped = table.concat(out)
print(string.format("mapped=%d lines=%d", #mapped, #lineOrigStart))

do
	local mlines = {}
	for line in (mapped .. "\n"):gmatch("(.-)\n") do
		mlines[#mlines + 1] = line
	end
	print("---- mappedlines (" .. #mlines .. ")")
	for _, n in ipairs({ 3514, 3515, 3516, 3517, 3518, 3548, 3549, 3550, 3560, 3561, 3562, 3900, 3901, 3902, 4382, 4383, 4384, 5909, 5910, 5911, 5964, 5965, 5966, 5967, 6399, 6400, 6401, 6414, 6415, 6416, 6640, 6641, 6642, 6759, 6760, 6761 }) do
		print(string.format("  m%d: %s", n, tostring(mlines[n]):sub(1, 700)))
	end
end

do
	local luau = require("@lune/luau")
	local ok = pcall(luau.load, mapped)
	print("preinject-compile=" .. tostring(ok))
end

local ARITH_SYM = {
	["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true,
	["%"] = true, ["^"] = true, [".."] = true, ["#"] = true,
}

local function isAtomTok(t: any): boolean
	return t.kind == "id" or t.kind == "num" or t.kind == "str"
end

local function scanLeftOperand(toks: { any }, i: number): number?
	local j = i - 1
	if j < 1 then
		return nil
	end
	local t = toks[j]
	if not (isAtomTok(t) or (t.kind == "sym" and (t.raw == ")" or t.raw == "]"))) then
		return nil
	end
	while j >= 1 do
		local tt = toks[j]
		if tt.kind == "sym" and tt.raw == ")" then
			local depth = 0
			while j >= 1 do
				local u = toks[j]
				if u.raw == ")" then
					depth += 1
				elseif u.raw == "(" then
					depth -= 1
					if depth == 0 then
						break
					end
				end
				j -= 1
			end
			if j < 1 then
				return nil
			end
			j -= 1
		elseif tt.kind == "sym" and tt.raw == "]" then
			local depth = 0
			while j >= 1 do
				local u = toks[j]
				if u.raw == "]" then
					depth += 1
				elseif u.raw == "[" then
					depth -= 1
					if depth == 0 then
						break
					end
				end
				j -= 1
			end
			if j < 1 then
				return nil
			end
			j -= 1
			if j >= 1 and toks[j].kind == "id" then
				j -= 1
			end
		elseif tt.kind == "sym" and tt.raw == ":" then
			j -= 1
		elseif tt.kind == "sym" and tt.raw == "." then
			if j + 1 <= #toks and toks[j + 1].kind == "id" then
				j -= 1
			else
				break
			end
		elseif isAtomTok(tt) then
			j -= 1
		else
			break
		end
	end
	local ls = j + 1
	if ls < 1 then
		return nil
	end
	if ls > 1 and toks[ls - 1] ~= nil and toks[ls - 1].kind == "sym" and toks[ls - 1].raw == ":" then
		return nil
	end
	return ls
end

local function scanRightOperand(toks: { any }, i: number): (number?, number?)
	local n = #toks
	local j = i + 1
	if j > n then
		return nil, nil
	end
	local t = toks[j]
	if not (isAtomTok(t) or (t.kind == "sym" and t.raw == "(")) then
		return nil, nil
	end
	while j <= n do
		local tt = toks[j]
		if tt.kind == "sym" and tt.raw == "(" then
			local depth = 0
			while j <= n do
				local u = toks[j]
				if u.raw == "(" then
					depth += 1
				elseif u.raw == ")" then
					depth -= 1
					if depth == 0 then
						break
					end
				end
				j += 1
			end
			if j > n then
				return nil, nil
			end
			j += 1
		elseif tt.kind == "sym" and tt.raw == "[" then
			local depth = 0
			while j <= n do
				local u = toks[j]
				if u.raw == "[" then
					depth += 1
				elseif u.raw == "]" then
					depth -= 1
					if depth == 0 then
						break
					end
				end
				j += 1
			end
			if j > n then
				return nil, nil
			end
			j += 1
		elseif tt.kind == "sym" and (tt.raw == "." or tt.raw == ":") then
			if j + 1 <= n and toks[j + 1].kind == "id" then
				j += 2
			else
				break
			end
		elseif tt.kind == "sym" and tt.raw == "{" then
			local depth = 0
			while j <= n do
				local u = toks[j]
				if u.raw == "{" then
					depth += 1
				elseif u.raw == "}" then
					depth -= 1
					if depth == 0 then
						break
					end
				end
				j += 1
			end
			if j > n then
				return nil, nil
			end
			j += 1
		elseif isAtomTok(tt) then
			j += 1
		else
			break
		end
	end
	return i + 1, j - 1
end

local function guardArith(s: string)
	local ok, toks = pcall(Instrument.tokenize, s)
	if not ok or type(toks) ~= "table" or #toks == 0 then
		return nil, "tokenize failed", 0
	end
	local edits: { { pos: number, text: string, seq: number } } = {}
	local seq = 0
	local nWrapped = 0
	local nCompound = 0
	for i, tok in ipairs(toks) do
		if tok.kind == "sym" and ARITH_SYM[tok.raw] == true then
			local nextTok = toks[i + 1]
			local isCompound = nextTok ~= nil and nextTok.kind == "sym" and nextTok.raw == "="
			local ls = scanLeftOperand(toks, i)
			local rs, re = scanRightOperand(toks, i)
			if isCompound then
				if ls ~= nil and ls == i - 1 and toks[ls].kind == "id" then
					local id = toks[ls].raw
					seq += 1
					edits[#edits + 1] = { pos = toks[ls].start, text = " if " .. id .. "==nil then " .. id .. "=0 end; ", seq = seq, op = tok.start, kind = "C" }
					if rs ~= nil and re ~= nil and re == rs and toks[rs].kind == "id" then
						local rid = toks[rs].raw
						seq += 1
						edits[#edits + 1] = { pos = toks[rs].start, text = " if " .. rid .. "==nil then " .. rid .. "=0 end; ", seq = seq, op = tok.start, kind = "C" }
					end
					nCompound += 1
				end
			else
				if rs ~= nil and re ~= nil and re >= rs then
					local closeTxt = if tok.raw == "#" then " or _GAnilT())" else " or _GAnil())"
					seq += 1
					edits[#edits + 1] = { pos = toks[rs].start, text = "(", seq = seq, op = tok.start, kind = "R" }
					seq += 1
					edits[#edits + 1] = { pos = toks[re].start + #toks[re].raw, text = closeTxt, seq = seq, op = tok.start, kind = "R" }
					nWrapped += 1
				end
				if ls ~= nil and tok.raw ~= "#" and toks[ls] ~= nil and i > 1 and toks[i - 1] ~= nil then
					local okLs = toks[ls].kind ~= "sym"
					if not okLs and toks[ls].raw == "(" then
						local depth = 0
						local kLs = ls
						local lastLs = nil
						while kLs <= i - 1 do
							local uLs = toks[kLs]
							if uLs.raw == "(" then
								depth += 1
							elseif uLs.raw == ")" then
								depth -= 1
							end
							lastLs = kLs
							if depth == 0 then
								break
							end
							kLs += 1
						end
						okLs = depth == 0 and lastLs == i - 1
					end
					if okLs then
						local lEnd = toks[i - 1].start + #toks[i - 1].raw
						seq += 1
						edits[#edits + 1] = { pos = toks[ls].start, text = "(", seq = seq, op = tok.start, kind = "L" }
						seq += 1
						edits[#edits + 1] = { pos = lEnd, text = " or _GAnil())", seq = seq, op = tok.start, kind = "L" }
						nWrapped += 1
					end
				end
			end
		end
	end
	if #edits == 0 then
		return s, nil, 0
	end
	table.sort(edits, function(a, b)
		if a.pos ~= b.pos then
			return a.pos < b.pos
		end
		return a.seq < b.seq
	end)
	local parts: { string } = {}
	local p = 1
	for _, e in ipairs(edits) do
		parts[#parts + 1] = s:sub(p, e.pos - 1)
		parts[#parts + 1] = e.text
		p = e.pos
	end
	parts[#parts + 1] = s:sub(p)
	return table.concat(parts), nil, nWrapped + nCompound, edits
end

local function injectDbg(s: string)
	local luau = require("@lune/luau")
	local DBG1 = "if g[a[M]]==nil then local _dg=__SSDIAG2__; local _per=_dg and _dg[g]; local _rec=_per and _per[a[M]]; local _rs='nohist'; if _rec then _rs=tostring(_rec.n)..'/'..tostring(_rec.first)..'/'..tostring(_rec.last) end; local _kk='?'; pcall(function() _kk=tostring(g[i[M]]):sub(1,60) end); local _vt='?'; pcall(function() _vt=type(g[Z[M]]) end); local _nf1=_dg; local _c1=(_nf1 and _nf1.slot6415 or 0)+1; if _nf1 then _nf1.slot6415=_c1 end; if _c1<=25 then print(string.format('SLOT6415 c=%d slot=%s key=%s valty=%s rec=%s', _c1, tostring(a[M]), _kk, _vt, _rs)); if _rec and _rec.trace then print('TR6415<<'..tostring(_rec.trace):sub(1,550)..'>>') end; if _rec and _rec.nilTrace then print('NLT6415<<'..tostring(_rec.nilTrace):sub(1,550)..'>>') end; local _tb1=''; pcall(function() _tb1=debug.traceback('',2) or '' end); print('TB6415<'.._tb1:sub(1,450)..'>') end end;"
	local pat1 = "E==0B1111100%s+then%s+"
	local st1, en1 = s:find(pat1)
	local cnt1 = 0
	do
		local p = 1
		while true do
			local a1, b1 = s:find(pat1, p)
			if not a1 then
				break
			end
			cnt1 += 1
			p = b1 + 1
		end
	end
	print("find6415=" .. tostring(st1) .. " count=" .. tostring(cnt1))
	if st1 then
		s = s:sub(1, en1) .. DBG1 .. s:sub(en1 + 1)
		print("afterDBG1-compile=" .. tostring(pcall(luau.load, s)))
	end

	local DBG2 = ";if G==nil then local _dg=__SSDIAG2__; local _per=_dg and _dg[g]; local _rec=_per and _per[a[M]]; local _rs='nohist'; if _rec then _rs=tostring(_rec.n)..'/'..tostring(_rec.first)..'/'..tostring(_rec.last) end; print(string.format('SLOT5825 slot=%s val=nil rec=%s', tostring(a[M]), _rs)); if _rec and _rec.trace then print('TR5825<<'..tostring(_rec.trace):sub(1,550)..'>>') end; if _rec and _rec.nilTrace then print('NLT5825<<'..tostring(_rec.nilTrace):sub(1,550)..'>>') end end local _h = 0 "
	local pat2 = "_=Z%[M%]%s*;%s*G=g%[a%[M%]%]%s*;%s*%(g%)%[_%+0B1%]"
	local st2, en2 = s:find(pat2)
	print("find5825=" .. tostring(st2))
	if st2 then
		local seg = s:sub(st2, en2)
		local gst, gen = seg:find("G=g%[a%[M%]%]")
		local insPos = if gst then st2 + gen - 1 else en2
		local cand = s:sub(1, insPos) .. DBG2 .. s:sub(insPos + 1)
		local ok2, err2 = pcall(luau.load, cand)
		print("DBG2-compile=" .. tostring(ok2) .. (if ok2 then "" else " ERR: " .. tostring(err2):match("[^\n]*")))
		if ok2 then
			s = cand
		end
	end

	local function argDump(label: string)
		return "if g[_+1]==nil or g[_+2]==nil or g[_+3]==nil or g[_+4]==nil then local _nf=__SSDIAG2__; local _cn=(_nf and _nf['argc_" .. label .. "'] or 0)+1; if _nf then _nf['argc_" .. label .. "']=_cn end; if _cn<=10 then local _p=__SSDIAG2__ and __SSDIAG2__[g]; for _h=1,4 do local _sl=_+_h; if g[_sl]==nil then local _r=_p and _p[_sl]; print(string.format('"
			.. label
			.. " s=%d n=%s first=%s last=%s', _sl, _r and tostring(_r.n) or '?', _r and _r.first or '?', _r and _r.last or '?')); if _r and _r.trace then print('ARTR"
			.. label
			.. "<'..tostring(_r.trace):sub(1,550)..'>') end; if _r and _r.nilTrace then print('ANLT"
			.. label
			.. "<'..tostring(_r.nilTrace):sub(1,550)..'>') end end end end end "
	end

	local inj5 = " do local _o6=g[a[M]]; local _v6=nil; pcall(function() if _o6~=nil then _v6=_o6[B[M]] end end); if _v6==nil then local _nf5=__SSDIAG2__; if _nf5==nil then __SSDIAG2__={} _nf5=__SSDIAG2__ end; _nf5.idx6641=(_nf5.idx6641 or 0)+1; 			local _dk='k6641_'..tostring(B[M]); if _nf5[_dk]==nil then _nf5[_dk]=1; local _kn=(_nf5['kdn'] or 0)+1; _nf5['kdn']=_kn; if _kn<=40 then local _r5=__SSDIAG2__ and __SSDIAG2__[g] and __SSDIAG2__[g][a[M]]; local _ad=''; pcall(function() _ad=tostring(_o6) end); local _ln=''; pcall(function() _ln=tostring(#_o6) end); local _nk=''; pcall(function() local _k=next(_o6); _nk=type(_k) end); local _mt=''; pcall(function() _mt=if getmetatable(_o6)==nil then 'no' else 'yes' end); print(string.format('IDX6641 c=%d d=%d key=%s obj=%s addr=%s len=%s nk=%s mt=%s rec=%s', _nf5.idx6641, _kn, tostring(B[M]), type(_o6), _ad, _ln, _nk, _mt, if _r5 then tostring(_r5.n)..'/'..tostring(_r5.first)..'/'..tostring(_r5.last) else '?')); if _r5 and _r5.trace then print('IXTR6641<'..tostring(_r5.trace):sub(1,500)..'>') end; if type(B[M])=='string' then local _tb5=''; pcall(function() _tb5=debug.traceback('',2) or '' end); print('TB6641<'.._tb5:sub(1,450)..'>') end end end; end end "

	local inj6 = " if g[i[M]]==nil or g[Z[M]]==nil then local _dg=__SSDIAG2__; local _per=_dg and _dg[g]; for _j=1,3 do local _sl; if _j==1 then _sl=i[M] elseif _j==2 then _sl=Z[M] else _sl=a[M] end; local _rec=_per and _per[_sl]; local _rs='nohist'; if _rec then _rs=tostring(_rec.n)..'/'..tostring(_rec.first)..'/'..tostring(_rec.last) end; print(string.format('CR5910 slot=%s which=%s val=%s rec=%s', tostring(_sl), ({ 'iM', 'ZM', 'aM' })[_j], tostring(_j<3 and (g[_sl]) or nil), _rs)); if _rec and _rec.trace then print('CRTR<'..tostring(_rec.trace):sub(1,550)..'>>') end; if _rec and _rec.nilTrace then print('CRNLT<'..tostring(_rec.nilTrace):sub(1,550)..'>>') end end; local _tb=''; pcall(function() _tb=debug.traceback('',2) or '' end); print('CR5910TB<'..tostring(_tb):sub(1,600)..'>') end "

	local inj7 = "if X[0X1c]==X[0B10011] then local _nf=__SSDIAG2__; local _c=(_nf and _nf.nfstale or 0)+1; if _nf then _nf.nfstale=_c end; if _c<=10 then print(string.format('NFSTALE u=%s C=%s H=%s', tostring(u), type(C), tostring(H))) end end; if type(C)=='table' and type(u)=='number' and type(C[u])=='table' then local _nf2=__SSDIAG2__; local _c2=(_nf2 and _nf2.nfclear or 0)+1; if _nf2 then _nf2.nfclear=_c2 end; if _c2<=15 then local _tb=''; if _c2<=5 then pcall(function() _tb=debug.traceback('',2) or '' end) end; print(string.format('NFCLEAR u=%s tbl=%s%s', tostring(u), tostring(C[u]):sub(1,16), _tb~='' and (' tr<'.._tb:sub(1,500)..'>') or '')) end end "

	local inj8 = " if type(g)=='table' and type(H)=='number' and type(g[H])=='table' then local _nf=__SSDIAG2__; local _c=(_nf and _nf.ngclear or 0)+1; if _nf then _nf.ngclear=_c end; if _c<=15 then local _tb=''; if _c<=5 then pcall(function() _tb=debug.traceback('',2) or '' end) end; print(string.format('NGCLEAR H=%s tbl=%s%s', tostring(H), tostring(g[H]):sub(1,16), _tb~='' and (' tr<'.._tb:sub(1,500)..'>') or '')) end end "

	local inj9 = " do local _nf9=__SSDIAG2__; if _nf9==nil then __SSDIAG2__={} _nf9=__SSDIAG2__ end; local _c9=(_nf9.arg3516 or 0)+1; _nf9.arg3516=_c9; if _c9==1 then print('ARG3516-REACHED') end; if g[_+2]==nil and _c9<=40 then print(string.format('ARG3516 _=%s k=%s G=%s C=%s', tostring(_), tostring(k), tostring(G), tostring(C))); for _h=1,5 do local _sl=_+_h; local _rv=g[_sl]; local _r9=__SSDIAG2__ and __SSDIAG2__[g] and __SSDIAG2__[g][_sl]; print(string.format('  a3 s=%d ty=%s n=%s first=%s last=%s', _sl, type(_rv), _r9 and tostring(_r9.n) or '?', _r9 and _r9.first or '?', _r9 and _r9.last or '?')); if _r9 and _r9.trace then print('ARTR3516<'..tostring(_r9.trace):sub(1,500)..'>') end end local _tb9=''; pcall(function() _tb9=debug.traceback('',2) or '' end); print('A3TB<'.._tb9:sub(1,500)..'>') end; end "

	local inj10 = " do local _t2=_[2]; local _t3=_[3]; if _t2==nil and _t3~=nil then local _nf10=__SSDIAG2__; if _nf10==nil then __SSDIAG2__={} _nf10=__SSDIAG2__ end; local _c10=(_nf10.varshort or 0)+1; _nf10.varshort=_c10; if _c10<=40 then local _vn=select('#',...); local _v3=''; pcall(function() _v3=tostring(_t3):sub(1,40) end); local _tb10=''; pcall(function() _tb10=debug.traceback('',2) or '' end); print(string.format('VARSHORT c=%d got=%s want=%s t1=%s v3=%s', _c10, tostring(_vn), tostring(i[M]), type(_[1]), _v3)); print('VSTR<'.._tb10:sub(1,420)..'>') end end; end "

	local inj13 = " do local _s13=g[a[M]]; if _s13==nil then local _nf13=__SSDIAG2__; if _nf13==nil then __SSDIAG2__={} _nf13=__SSDIAG2__ end; _nf13.move6400=(_nf13.move6400 or 0)+1; if _nf13.move6400<=30 then local _per=__SSDIAG2__ and __SSDIAG2__[g]; local function _p13(_sl) local _r=_per and _per[_sl]; if not _r then return tostring(_sl)..':nohist' end; local _fs=''; pcall(function() _fs=tostring(_r.first):sub(1,44) end); local _ls=''; pcall(function() _ls=tostring(_r.last):sub(1,44) end); local _tr=''; pcall(function() if _r.trace then _tr=' tr<'..tostring(_r.trace):sub(1,240)..'>' end end); local _nl=''; pcall(function() if _r.nilTrace then _nl=' ntr<'..tostring(_r.nilTrace):sub(1,240)..'>' end end); return string.format('%s n=%s f=%s l=%s%s%s', tostring(_sl), tostring(_r.n), _fs, _ls, _tr, _nl) end; print(string.format('MOVE6400 c=%d Z=%s a=%s src{%s} dst{%s}', _nf13.move6400, tostring(Z[M]), tostring(a[M]), _p13(a[M]), _p13(Z[M]))); local _tb13=''; pcall(function() _tb13=debug.traceback('',2) or '' end); print('MTB<'.._tb13:sub(1,420)..'>') end end; end "

	local inj14 = " do local _wty=type(W); local _wg=false; if _wty=='table' then _wg=(W[G]==nil) end; if _wg or _wty~='table' then local _nf14=__SSDIAG2__; if _nf14==nil then __SSDIAG2__={} _nf14=__SSDIAG2__ end; _nf14.resnil=(_nf14.resnil or 0)+1; if _nf14.resnil<=30 then local _wn='?'; if _wty=='table' then pcall(function() _wn=tostring(#W) end) end; print(string.format('RESNIL z=%s G=%s u=%s base=%s wty=%s wlen=%s', tostring(z), tostring(G), tostring(u), tostring(_), _wty, _wn)); local _tb14=''; pcall(function() _tb14=debug.traceback('',2) or '' end); print('RTB<'.._tb14:sub(1,380)..'>') end end; end "

	local inj15 = " do local _n15=0; pcall(function() _n15=u-_+1 end); local _wty15=type(W); local _hn=false; if _wty15~='table' then _hn=true else pcall(function() for _q=1,_n15 do if W[_q]==nil then _hn=true break end end end) end; if _hn then local _tf15=''; pcall(function() _tf15=type(g[_]) end); local _f15=''; pcall(function() _f15=tostring(g[_]) end); local _fi15=''; pcall(function() local _a15,_b15=debug.info(g[_],'sl'); _fi15='ln='..tostring(_b15) end); pcall(function() _fi15=_fi15..' nm='..tostring(debug.info(g[_],'n')) end); local _nf15=__SSDIAG2__; if _nf15==nil then __SSDIAG2__={} _nf15=__SSDIAG2__ end; _nf15.callres=(_nf15.callres or 0)+1; local _av15=''; pcall(function() local _pa15,_va15=debug.info(g[_],'a'); _av15=tostring(_pa15)..','..tostring(_va15) end); local _gs15=tostring(g); _nf15.gset=_nf15.gset or {}; if not _nf15.gset[_gs15] then _nf15.gset[_gs15]=true; _nf15.gn=(_nf15.gn or 0)+1 end; if _nf15.callres<=40 then local _pts=''; pcall(function() if _wty15=='table' then for _q=1,(_n15<6 and _n15 or 6) do _pts=_pts.._q..':'..type(W[_q])..';' end end end); print(string.format('CALLRES c=%d u=%s _=%s n=%s wty=%s fnTy=%s fn=%s fi=%s g=%s gn=%d ar=%s res=%s', _nf15.callres, tostring(u), tostring(_), tostring(_n15), _wty15, _tf15, _f15:sub(1,64), _fi15:sub(1,60), _gs15, _nf15.gn, _av15, _pts)) end end; end "

	local jobs = {
		{ "DBG3", "g%[_%]%(%s*X%[0X01c%]%(_%+0x1,g,k%)%)", argDump("ARG4274"), "before" },
		{ "DBG4", "%(g%)%[_%]%s*=%s*g%[_%]%(%s*X%[28%]%(_%+0X1,g,k%)%)", argDump("ARG3561"), "before" },
		{ "DBG5", "%(g%)%[i%[M%]%]=g%[a%[M%]%]%[B%[M%]%]", inj5, "before" },
		{ "DBG6", "E==0X8A%s+then", inj6, "after" },
		{ "DBG7", "H=nil%s*;%s*%(C%)%[u%]=H", inj7, "before" },
		{ "DBG8", "for H=Z%[M%],a%[M%]%s*do%s+", inj8, "after" },
		{ "DBG9", "u,W=X%[0X38__%]%(%s*g%[_%]%(%s*X%[0B11100%]%(_%+1,g,k%)%)%)", inj9, "before" },
		{ "DBG10", "_=%s*{%.%.%.}%s*;", inj10, "after" },
		{ "DBG13", "else%(%g%)%[Z%[M%]%]=%(%g%[a%[M%]%]%)", inj13, "after" },
		{ "DBG14", "%(g%)%[z%]=W%[G%]%s*;", inj14, "after" },
		{ "DBG15", "for z=_,u,0x1%s+do", inj15, "before" },

		{ "NC1", "g%[H%]=nil", "if false then g[H]=nil end", "replace" },
	}
	local DO_DBG = false
	local function mkXC(tag: string): string
		local k = "_D['C" .. tag .. "']"
		return " do local _D=__SSDIAG2__; if _D then " .. k .. "=(" .. k .. " or 0)+1; local _f=g[_]; if type(_f)=='function' then local _src=''; pcall(function() _src=tostring(debug.info(_f,'s')) end); if _src~='' then if not _src:find('__FUHD_CHECK__',1,true) then if (_D.xn or 0)<=40 then _D.xn=(_D.xn or 0)+1; local _nm=''; pcall(function() _nm=tostring(debug.info(_f,'n')) end); local _a=nil; pcall(function() _a=g[(_ or 0)+1] end); local _s=''; pcall(function() _s=tostring(_a):sub(1,300) end); local _aln=''; if type(_a)=='function' then pcall(function() _aln=' ln='..tostring(debug.info(_a,'l'))..' fs='..tostring(debug.info(_a,'s')):sub(1,34) end) end; pcall(function() print('XCALL " .. tag .. " n='..tostring(_D.xn)..' op='..tostring(_D.op)..' nm='.._nm..' a1='..type(_a)..'='.._s..' k='..tostring(k).._aln) end) end else if (_D.pn or 0)<40 and (((_D.op or 0)>=63970 and (_D.op or 0)<=64105) or ((_D.op or 0)>3000000)) then _D.pn=(_D.pn or 0)+1; local _nm=''; pcall(function() _nm=tostring(debug.info(_f,'n')) end); local _ln=''; pcall(function() _ln=tostring(debug.info(_f,'l')) end); local _pa=nil; pcall(function() _pa=g[(_ or 0)+1] end); local _ps=''; pcall(function() _ps=tostring(_pa):sub(1,60) end); pcall(function() print('PCALL " .. tag .. " n='..tostring(_D.pn)..' op='..tostring(_D.op)..' nm='.._nm..' ln='.._ln..' k='..tostring(k)..' a1='..type(_pa)..'='.._ps) end) end end end end end end "
	end
	local probeJobs = {
		 { "DBG16", "local E=%(e%[M%]%)", " do local _D=__SSDIAG2__; if _D then _D.op=(_D.op or 0)+1; if E==124 and _D.op>=63900 and _D.op<=64700 and (_D.spn or 0)<80 then _D.spn=(_D.spn or 0)+1; local _br=a[M]; local _b=g[_br]; print('SETP op='..tostring(_D.op)..' M='..tostring(M)..' bReg='..tostring(_br)..' bT='..type(_b)..' k='..tostring(g[i[M]])..' vT='..type(g[Z[M]])); if _b==nil and (_D.rd or 0)<6 then _D.rd=(_D.rd or 0)+1; local _p={}; for _j=1,40 do local _v=g[_j]; local _s=type(_v); if _s=='number' or _s=='string' then _s=_s..'='..tostring(_v):sub(1,20) elseif _s=='userdata' then _s=_s..'='..tostring(_v):sub(1,24) end; _p[#_p+1]=_j..':'.._s end; print('RSD op='..tostring(_D.op)..' {'..table.concat(_p,' ')..'}') end end; if (_D.op==64029 or _D.op==64091 or _D.op==64193 or _D.op==64489) and (_D.rd2 or 0)<8 then _D.rd2=(_D.rd2 or 0)+1; local _p={}; for _j=1,40 do local _v=g[_j]; local _s=type(_v); if _s=='number' or _s=='string' then _s=_s..'='..tostring(_v):sub(1,20) elseif _s=='userdata' then _s=_s..'='..tostring(_v):sub(1,24) end; _p[#_p+1]=_j..':'.._s end; print('RSD op='..tostring(_D.op)..' {'..table.concat(_p,' ')..'}') end; if _D.op>=64024 and _D.op<=64220 then local _p=_D.prev; if _p and (_D.df or 0)<150 then local _hit=false; local _d={}; for _j=1,40 do local _v=g[_j]; if _p[_j]~=_v then _d[#_d+1]=_j..':'..type(_v); if _j==2 or _j==3 or _j==6 or _j==7 or _j==11 then _hit=true end end end; if _hit and #_d>0 then _D.df=(_D.df or 0)+1; print('DF op='..tostring(_D.op)..' M='..tostring(M)..' E='..tostring(E)..' {'..table.concat(_d,' ')..'}') end end; local _q={}; for _j=1,40 do _q[_j]=g[_j] end; _D.prev=_q end; do local _o=_D.op; if _o%5000000==0 and _D.sp~=_o then _D.sp=_o; print('SITE op='.._o..' A='..tostring(_D['CA'])..' B='..tostring(_D['CB'])..' C='..tostring(_D['CC'])..' D='..tostring(_D['CD'])..' E='..tostring(_D['CE'])..' F='..tostring(_D['CF'])..' G='..tostring(_D['CG'])..' H='..tostring(_D['CH'])..' I='..tostring(_D['CI'])..' J='..tostring(_D['CJ'])..' K='..tostring(_D['CK'])) end end; if M==84 then _D.n84=(_D.n84 or 0)+1; local _mi=_D.mi or 1; if _mi==1 and _D.op>=100000 then _mi=2 end; if _mi==2 and _D.op>=500000 then _mi=3 end; if _mi==3 and _D.op>=3000000 then _mi=4 end; if _mi==4 and _D.op>=15000000 then _mi=5 end; if _mi==5 and _D.op>=40000000 then _mi=6 end; if _mi~=(_D.mis or 1) then _D.mis=_mi; local p={}; for _j=1,8 do local _v=g[_j]; p[#p+1]=_j..'='..type(_v)..'='..tostring(_v):sub(1,16) end; local _t=t; local _tv='nil'; local _tid='nil'; if type(_t)=='table' then _tid=tostring(_t); _tv=tostring(_t[6])..'|'..tostring(_t[15])..'|'..tostring(_t[16])..'|'..tostring(_t[84]) end; print('SNAP mi='.._mi..' op='.._D.op..' n84='.._D.n84..' tid='.._tid..' t6|15|16|84='.._tv..' Z84='..tostring(Z[84])..' gZ84='..tostring(g[Z[84]]):sub(1,16)..' {'..table.concat(p,' ')..'}') end; _D.mi=_mi end; if M==78 then local _w=(_D.wk or 0)+1; _D.wk=_w; if _w%20000==0 then print('WK n='.._w..' op='.._D.op) end end; if _D.op==1000000 then _D.rec={}; local _t=''; pcall(function() _t=debug.traceback('',1) or '' end); print('OPSTK1<'.._t:sub(1,2200)..'>'); do local _p={}; for _j=1,12 do local _v=g[_j]; local _sv; if type(_v)=='number' or type(_v)=='string' then _sv=tostring(_v):sub(1,24) else _sv=type(_v) end; _p[#_p+1]=_j..'='.._sv end; local _el='?'; pcall(function() _el=tostring(#e) end); print('REG1M e='.._el..' M='..tostring(M)..' {'..table.concat(_p,' ')..'}') end elseif _D.op==3000000 then do local _p={}; for _j=1,12 do local _v=g[_j]; local _sv; if type(_v)=='number' or type(_v)=='string' then _sv=tostring(_v):sub(1,24) else _sv=type(_v) end; _p[#_p+1]=_j..'='.._sv end; local _el='?'; pcall(function() _el=tostring(#e) end); print('REG3M e='.._el..' M='..tostring(M)..' {'..table.concat(_p,' ')..'}') end end; if _D.rec then if #_D.rec<240 then _D.rec[#_D.rec+1]=M..':'..E; elseif not _D.recDone then _D.recDone=true; print('OPSEQ<'..table.concat(_D.rec,' ')..'>') end end; if _D.op % 500000 == 0 and _D.op <= 10000000 then print(string.format('OP n=%d', _D.op)) end end end ", "after" },
		{ "DBG18", "repeat J,T,v=o:zz%(", " do local _D=__SSDIAG2__; if _D then _D.azN=(_D.azN or 0)+1; local n=_D.azN; if n<=15 or n==100 or n==1000 or n%20000==0 then local s327='nil'; pcall(function() s327=tostring(L[327]) end); print('AZ n='..n..' v='..tostring(v)..' J='..tostring(J)..' L327='..s327) end end end; ", "before" },
		{ "DBG19", "return L,nil,T", " do local _D=__SSDIAG2__; if _D then _D.zzOut=(_D.zzOut or 0)+1; local n=_D.zzOut; if n<=15 or n==100 or n==1000 or n%20000==0 then local s327='nil'; pcall(function() s327=tostring(X[327]) end); print('ZZOUT n='..n..' T='..tostring(T)..' X327='..s327) end end end; ", "before" },
		{ "DBG20", "else _=a%[M%]", " do local _D=__SSDIAG2__; if _D and (_D.xn or 0)<=40 then local _f=g[_]; local _ty=type(_f); if _ty=='function' then local _src=''; pcall(function() _src=tostring(debug.info(_f,'s')) end); if _src~='' and not _src:find('__FUHD_CHECK__',1,true) then _D.xn=(_D.xn or 0)+1; local _nm=''; pcall(function() _nm=tostring(debug.info(_f,'n')) end); local _v1=g[_+1]; local _v2=g[_+2]; print('XCALL n='..tostring(_D.xn)..' op='..tostring(_D.op)..' src='.._src:sub(1,64)..' nm='.._nm..' a1='..type(_v1)..'='..tostring(_v1):sub(1,300)..' a2='..type(_v2)..'='..tostring(_v2):sub(1,300)) end else if (_D.fnf or 0)<20 then _D.fnf=(_D.fnf or 0)+1; print('NF n='..tostring(_D.fnf)..' op='..tostring(_D.op)..' ty='.._ty..' val='..tostring(_f):sub(1,90)) end end end end ", "after" },
		{ "DBG21", ";k=_", " do local _D=__SSDIAG2__; if _D and (_D.retn or 0)<110 and (((_D.op or 0)<4000) or ((_D.op or 0)>=63000 and (_D.op or 0)<=67000) or ((_D.op or 0)>3000000)) then _D.retn=(_D.retn or 0)+1; local _v=g[_]; local _s='?'; pcall(function() if type(_v)=='function' then _s='fn'; else _s=type(_v)..'='..tostring(_v):sub(1,56) end end); print('CRET n='..tostring(_D.retn)..' op='..tostring(_D.op)..' slot='..tostring(_)..' ret='.._s) end end ", "before" },

		{ "DBG22", ";g%[_%]=g%[_%]%(g%[%(_ or _GAnil%(%)%)%+%(0X1 or", mkXC("A"), "before" },
		{ "DBG23", ";%(g%)%[_%]=g%[_%]%(X%[28%]", mkXC("B"), "before" },
		{ "DBG24", ";%(g%)%[_%]=g%[_%]%(X%[0b11100%]", mkXC("C"), "before" },
		{ "DBG25", ";g%[_%]%(g%[%(_ or _GAnil%(%)%)%+%(1 or", mkXC("D"), "before" },
		{ "DBG26", ";g%[_%]%(X%[0X01c%]%(", mkXC("E"), "before" },
		{ "DBG27", ";g%[_%]%(X%[0x1C%]%(", mkXC("F"), "before" },
		{ "DBG28", "return g%[_%]%(X%[0X1C%]%(", mkXC("G"), "before" },
		{ "DBG29", "return g%[_%]%(X%[28%]%(", mkXC("H"), "before" },
		{ "DBG30", "return g%[_%]%(g%[%(_ or _GAnil%(%)%)%+%(0B1 or", mkXC("I"), "before" },
		{ "DBG31", "u,W=X%[0X38%]%(g%[_%]%(%)", mkXC("J"), "before" },
		{ "DBG32", "u,W=X%[0X38__%]%(g%[_%]%(X%[0B11100%]", mkXC("K"), "before" },
		{ "DBG33", ";%(g%[_%]%)%(g%[", mkXC("L"), "before" },
		{ "DBG34", ";g%[k%]=g%[k%]%(%)", mkXC("M"), "before" },
		{ "DBG35", "return g%[a%[M%]%]%(%)", mkXC("N"), "before" },
		{ "DBG36", ";g%[k%]%(%)", mkXC("O"), "before" },
		{ "DBG37", ";k=%(_%)", " do local _D=__SSDIAG2__; if _D and (_D.cr2 or 0)<110 and (((_D.op or 0)<4000) or ((_D.op or 0)>=63000 and (_D.op or 0)<=67000) or ((_D.op or 0)>3000000)) then _D.cr2=(_D.cr2 or 0)+1; local _v=g[_]; local _s='?'; pcall(function() if type(_v)=='function' then _s='fn'; else _s=type(_v)..'='..tostring(_v):sub(1,60) end end); print('CRET2 n='..tostring(_D.cr2)..' op='..tostring(_D.op)..' slot='..tostring(_)..' ret='.._s) end end ", "before" },
	}
	local allJobs: { any } = {}
	for _, j in ipairs(probeJobs) do
		allJobs[#allJobs + 1] = j
	end
	if DO_DBG then
		for _, j in ipairs(jobs) do
			allJobs[#allJobs + 1] = j
		end
	end
	for _, job in ipairs(allJobs) do
		local label, pat, inj, mode = job[1], job[2], job[3], job[4]
		local hitList = {}
		local p = 1
		while true do
			local a1, b1 = s:find(pat, p)
			if not a1 then
				break
			end
			hitList[#hitList + 1] = { a1, b1 }
			p = b1 + 1
		end
		print(label .. "-count=" .. tostring(#hitList))
		if #hitList > 0 then
			local s0 = s
			if mode == "replace" then
				local parts = {}
				local p = 1
				for _, h in ipairs(hitList) do
					parts[#parts + 1] = s:sub(p, h[1] - 1)
					parts[#parts + 1] = inj
					p = h[2] + 1
				end
				parts[#parts + 1] = s:sub(p)
				s = table.concat(parts)
			else
				for i = #hitList, 1, -1 do
					local pos = if mode == "after" then hitList[i][2] + 1 else hitList[i][1]
					s = s:sub(1, pos - 1) .. inj .. s:sub(pos)
				end
			end
			local okx, errx = pcall(luau.load, s)
			print(label .. "-compile=" .. tostring(okx) .. (if okx then "" else " ERR: " .. tostring(errx):match("[^\n]*")))
			if not okx then
				local fp = s:find(inj, 1, true)
				if fp then
					print(label .. "-failctx: " .. (s:sub(math.max(1, fp - 200), fp + 400):gsub("\n", "|")))
				end
				s = s0
				print(label .. "-rolled-back")
			end
		end
	end
	return s
end
do
	local luau2 = require("@lune/luau")
	local gsrc, gerr, gn, gedits = guardArith(mapped)
	if gsrc ~= nil and gsrc ~= mapped then
		local okG, errG = pcall(luau2.load, gsrc)
		print("guardArith count=" .. tostring(gn) .. " compile=" .. tostring(okG) .. (if okG then "" else " ERR: " .. tostring(errG):match("[^\n]*")))
		if okG then
			mapped = gsrc
		else
			pcall(function()
				fs.writeFile("C:/Users/Sandr/AppData/Local/Temp/opencode/_guarded.txt", gsrc)
				if type(gedits) == "table" then
					local starts = { 1 }
					local pNl = 0
					while true do
						local nl = string.find(mapped, "\n", pNl + 1, true)
						if not nl then
							break
						end
						starts[#starts + 1] = nl + 1
						pNl = nl
					end
					local function lineOf(pos: number): number
						local lo, hi = 1, #starts
						while lo < hi do
							local mid = (lo + hi + 1) // 2
							if starts[mid] <= pos then
								lo = mid
							else
								hi = mid - 1
							end
						end
						return lo
					end
					local out = {}
					for _, e in ipairs(gedits) do
						out[#out + 1] = string.format("L%d pos=%d kind=%s op=%d %q", lineOf(e.pos), e.pos, tostring(e.kind), e.op, e.text)
					end
					fs.writeFile("C:/Users/Sandr/AppData/Local/Temp/opencode/_gedits.txt", table.concat(out, "\n"))
				end
			end)
			local eLine = tonumber(tostring(errG):match("]:(%d+):"))
			if eLine then
				local ls2 = {}
				for line in (gsrc .. "\n"):gmatch("(.-)\n") do
					ls2[#ls2 + 1] = line
				end
				for n = math.max(1, eLine - 1), math.min(#ls2, eLine + 1) do
					print(string.format("GA%d: %s", n, (ls2[n] or "?"):sub(1, 400)))
				end
			end
		end
	else
		print("guardArith skipped: " .. tostring(gerr) .. " count=" .. tostring(gn))
	end
end

mapped = injectDbg(mapped)

do
	local okW, errW = pcall(function()
		fs.writeFile("C:/Users/Sandr/AppData/Local/Temp/opencode/_mapped147.txt", mapped)
	end)
	print("mapped-dump=" .. tostring(okW) .. " bytes=" .. #mapped .. (errW and (" err=" .. tostring(errW)) or ""))
end

do
	local luau = require("@lune/luau")
	local ok, res = pcall(luau.load, mapped)
	print("injected-compile=" .. tostring(ok) .. " res=" .. tostring(res))
	if not ok then
		local lines = {}
		for line in (mapped .. "\n"):gmatch("(.-)\n") do
			lines[#lines + 1] = line
		end
		for n = 5820, 5828 do
			print(string.format("L%d: %s", n, (lines[n] or "?"):sub(1, 500)))
		end
	end
end

local function origCtx(lineNo: number): string
	local off = lineOrigStart[lineNo]
	if off == nil then
		return "<line out of range>"
	end
	return string.format("off=%d ctx: %s", off, src:sub(math.max(1, off - 60), off + 90))
end

local function dumpTrace(label: string, trace: string)
	print("==== " .. label)
	local count = 0
	for num in trace:gmatch("%]:(%d+)") do
		local lineNo = tonumber(num)
		if lineNo and lineNo > 1 and lineNo <= #lineOrigStart then
			count += 1
			if count <= 20 then
				print(string.format("  line %d | %s", lineNo, origCtx(lineNo)))
			end
		end
	end
	if count == 0 then
		print("  (no chunk frames) RAW: " .. trace:sub(1, 600))
	end
end

local t0 = os.clock()
do
	local GANIL_PRELUDE = "_GAnil=function(...)local d=__SSDIAG2__;if d then local c=(d.gaNil or 0)+1;d.gaNil=c;	if c==1 or c==10 or c==50 or c==250 or c==1000 then local tb='';pcall(function()tb=debug.traceback('',2) or '' end);print('GANIL c='..c..' <'..tb:sub(1,900)..'>')elseif c%500000==0 then print('GANIL c='..c)end end;return 0 end;_GAnilT=function(...)local d=__SSDIAG2__;if d then local c=(d.gaNilT or 0)+1;d.gaNilT=c;if c==1 or c%500000==0 then local tb='';pcall(function()tb=debug.traceback('',2) or '' end);print('GANILT c='..c..' <'..tb:sub(1,700)..'>')end end;return {} end;"
	local ppos = mapped:find("return(", 1, true)
	if ppos then
		mapped = mapped:sub(1, ppos - 1) .. GANIL_PRELUDE .. mapped:sub(ppos)
		print("GANIL-injected at " .. tostring(ppos))
	else
		mapped = GANIL_PRELUDE .. "\n" .. mapped
		print("GANIL-injected at head")
	end
end
local r = Sandbox.run(mapped, {
	timeout = 180,
	maxNest = 4,
	traceLimit = 200000,
	onProgress = function() end,
	zlib = zlib,
	allowHttp = false,
	maxExplored = 0,
	softInstanceCall = true,
	nosoft = true,
})
local elapsed = os.clock() - t0

print(string.format(
	"t=%.1f ok=%s exhausted=%s err=%s stages=%d",
	elapsed,
	tostring(r.ok),
	tostring(r.exhausted),
	tostring(r.err),
	if type(r.stages) == "table" then #r.stages else -1
))
if type(r.err) == "string" then
	dumpTrace("ERR", r.err)
end

local diag = r.ssDiag
if type(diag) == "table" then
	print(
		"diag events=" .. tostring(diag.events)
			.. " dropBase=" .. tostring(diag.dropBase)
			.. " softKey=" .. tostring(diag.softKey)
			.. " nilKey=" .. tostring(diag.nilKey)
			.. " nilVal=" .. tostring(diag.nilVal)
			.. " softIndexNilBase=" .. tostring(diag.softIndexNilBase)
			.. " nilStrReads=" .. tostring(diag.nilStrReads)
			.. " nilTraceCount=" .. tostring(diag.nilTraceCount)
		)
	local nstr = diag.nilStrTraces
	if type(nstr) == "table" then
		for i, tr in ipairs(nstr) do
			dumpTrace("nilStr #" .. i .. " (" .. tr:match("^[^\n]*") .. ")", tr)
		end
	end
	local trs = diag.softIdxTraces
	if type(trs) == "table" then
		for i, tr in ipairs(trs) do
			dumpTrace("softIdx #" .. i .. " (" .. tr:match("^[^\n]*") .. ")", tr)
		end
	end
	local dtrs = diag.dropTraces
	if type(dtrs) == "table" then
		for i, tr in ipairs(dtrs) do
			dumpTrace("dropBase #" .. i .. " (" .. tr:match("^[^\n]*") .. ")", tr)
		end
	end
	print("instCleared=" .. tostring(diag.instCleared) .. " instReadNil=" .. tostring(diag.instReadNil))
	local ic = diag.instClearedTraces
	if type(ic) == "table" then
		for i, tr in ipairs(ic) do
			dumpTrace("instCleared #" .. i .. " (" .. tr:match("^[^\n]*") .. ")", tr)
		end
	end
	local ir = diag.instReadNilTraces
	if type(ir) == "table" then
		for i, tr in ipairs(ir) do
			dumpTrace("instReadNil #" .. i .. " (" .. tr:match("^[^\n]*") .. ")", tr)
		end
	end
else
	print("diag: missing")
end

if r.nilCulprit ~= nil then
	print("nilCulprit=" .. tostring(r.nilCulprit))
end

if type(r.antiNilIssues) == "table" then
	print("---- antiNilIssues (" .. #r.antiNilIssues .. ")")
	for i = 1, math.min(#r.antiNilIssues, 20) do
		print("  " .. tostring(r.antiNilIssues[i]):sub(1, 300))
	end
end
if type(r.undefinedGlobals) == "table" then
	print("---- undefinedGlobals (" .. #r.undefinedGlobals .. ")")
	for i = 1, math.min(#r.undefinedGlobals, 30) do
		print("  " .. tostring(r.undefinedGlobals[i]):sub(1, 200))
	end
end

print(string.format("outputsDropped=%s outputTotalBytes=%s", tostring(r.outputsDropped), tostring(r.outputTotalBytes)))

local seenTrace = {}
if type(r.outputs) == "table" then
	print("---- outputs (" .. #r.outputs .. ")")
	for i = 1, #r.outputs do
		local o = r.outputs[i]
		if type(o) == "table" then
			local rawText = tostring(o.text or o.message or "")
			local txt = rawText:gsub("\n", " | ")
			print(string.format("  out[%d] %s: %s", i, tostring(o.kind or "?"), txt))
			local la = rawText:find("<", 1, true)
			if la and rawText:find("%]:%d+") then
				local body = rawText:sub(la + 1):gsub("^<+", ""):gsub(">>?$", "")
				local key = body:sub(1, 300)
				if not seenTrace[key] then
					seenTrace[key] = true
					dumpTrace(string.format("out[%d]", i), body)
				end
			end
		else
			print(string.format("  out[%d]: %s", i, (tostring(o):gsub("\n", " | "))))
		end
	end
end

if type(r.vmTrace) == "table" then
	local n = #r.vmTrace
	print("---- vmTrace (" .. n .. ")")
	local first = math.max(1, n - 40)
	for i = first, n do
		local e = r.vmTrace[i]
		if type(e) == "table" then
			print(string.format("  vt[%d] %s | %s", i, tostring(e.kind), tostring(e.expression or e.detail or e.text):sub(1, 200)))
		else
			print(string.format("  vt[%d] %s", i, tostring(e):sub(1, 200)))
		end
	end
end

print("---- keyframes")
for _, ln in ipairs({ 4274, 6641, 5966, 4383, 3561, 3516, 3068, 3865, 6415, 5825, 5910, 3901, 4270, 3891, 6400, 7115, 8755, 2418, 6760, 1137, 8786 }) do
	local off = lineOrigStart[ln]
	if off ~= nil then
		print(string.format("  f%d off=%d :: %s", ln, off, (src:sub(math.max(1, off - 140), off + 300):gsub("\n", "|"))))
	end
end
