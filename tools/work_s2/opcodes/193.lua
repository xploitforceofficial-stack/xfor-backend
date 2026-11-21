g=f[F];e=d[F];_=(N[F]);
if e==0.0 then
else
t=g+e-1.0;
end
H,q=(nil);
if e==1.0 then
H,q=z[50](r[g]());
else
H,q=z[50](r[g](z[26](g+1.0,r,t)));
end
if _==1.0 then
t=g-1.0;
else
if _~=0.0 then
H=(g+_-2.0);t=H+1.0;
else
H=(H+g-1.0);t=(H);
end
e=0.0;
for E=g,H do e+=1.0;(r)[E]=q[e];end;
end
F+=1.0;
