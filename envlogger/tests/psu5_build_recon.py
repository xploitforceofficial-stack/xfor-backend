"""Build the runnable PSU v5 reconstruction: v4.5 wrapper + intact v5 body.

Two scrambler artifacts to remove:
1. Dead wrapper fragment 'P-(90));' at body start (P is shadowed, unused).
2. Tail: env table closer duplicated with junk entries re-injected:
   ...958991711));})[(576707054)]=((1810));...;}),...)})do return e end;
   The real tail is:  ...958991711));}),...)})do return e end;   (v4.5 shape)
   Fix: from the first '})' after the env table's last real entry, drop
   everything up to the final '}),' before ',...)})do return e end;'.
"""
s = open(r"C:/Users/Sandr/OneDrive/Desktop/OmniDBF/Samples/PSU/v5/1.lua",
         encoding="utf-8", errors="replace").read()

body = s[1000524 + 8:]
assert body.startswith("local function o(n,e,...)"), repr(body[:40])

fi = body.rfind("do return e end")
assert body[fi:].startswith("do return e end"), repr(body[fi:fi+30])

head = body[:fi]

dup = head.find("})[(")
assert dup > 0, "dup closer not found"
print("dup closer at body offset", dup, ":", repr(head[dup:dup+60]))

recon_body = head[:dup+2] + ",...)})" + body[fi:]

out = "for l,e in pairs({(function(e,...)" + recon_body + "\n"
open(r"C:/Users/Sandr/OneDrive/Desktop/OmniDBF/Samples/PSU/v5/_recon5.lua",
     "w", encoding="utf-8", newline="").write(out)
print("wrote _recon5.lua, len:", len(out))
print("tail:", repr(out[-120:]))
