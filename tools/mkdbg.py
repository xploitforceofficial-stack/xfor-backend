t = open("tools/patch_s2.py", encoding="utf-8").read()
old = ("\"if(not MKSEEN[k])then MKSEEN[k]=true;\"\n"
       "    \"table.insert(MKENTRY,{hid=tostring(k),cnt=#m,r=r,f=f,y=y,m=m,N=N,h=h,d=d,n=n});end;\"\n"
       ")")
new = "\"table.insert(MKENTRY,{kid=type(k),mm=type(m)});\"\n)"
assert old in t
t = t.replace(old, new)
t = t.replace("stage_inst.lua", "stage_dbg.lua")
open("tools/patch_s2_dbg.py", "w", encoding="utf-8").write(t)
print("wrote dbg patch")
