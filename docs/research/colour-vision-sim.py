# Simulates colour-vision deficiency on the Klassik palette. See docs/research/colour-vision.md.
# Usage: python3 colour-vision-sim.py <mode> <path to the palette-*.css directory>
import re, sys, math, itertools, json
D = sys.argv[2] if len(sys.argv) > 2 else "prototypes/specimen/variants/"
ACC = ["oxblood","claret","green","plum"]
def parse(name):
    t = open(D+f"palette-{name}.css").read()
    modes = {}
    for m in re.finditer(r'((?::root[^{]*,\s*)*:root[^{]*)\{([^}]*)\}', t):
        sel = m.group(1)
        paper = re.search(r'data-paper="(\w+)"', sel); theme = re.search(r'data-theme="(\w+)"', sel); con = re.search(r'data-contrast="(\w+)"', sel)
        key = f"{theme.group(1)}-{paper.group(1) if paper else 'all'}-{con.group(1)}"
        modes[key] = dict(re.findall(r'--color-([\w-]+):\s*(#[0-9a-fA-F]{6,8})', m.group(2)))
    return modes
P = {a: parse(a) for a in ACC}
# sRGB <-> linear
def hex2(h): return [int(h[i:i+2],16)/255 for i in (1,3,5)]
def lin(c): return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
def enc(c):
    c = min(max(c,0),1); return 12.92*c if c<=0.0031308 else 1.055*c**(1/2.4)-0.055
def mm(M,v): return [sum(M[i][j]*v[j] for j in range(3)) for i in range(3)]
MACH = {
 ("protan",0.6):[[0.385450,0.769005,-0.154455],[0.100526,0.829802,0.069673],[-0.007442,-0.022190,1.029632]],
 ("protan",1.0):[[0.152286,1.052583,-0.204868],[0.114503,0.786281,0.099216],[-0.003882,-0.048116,1.051998]],
 ("deutan",0.6):[[0.498864,0.674741,-0.173604],[0.205199,0.754872,0.039929],[-0.011131,0.030969,0.980162]],
 ("deutan",1.0):[[0.367322,0.860646,-0.227968],[0.280085,0.672501,0.047413],[-0.011820,0.042940,0.968881]],
 ("tritan",0.6):[[1.104996,-0.046633,-0.058363],[-0.032137,0.971635,0.060503],[0.001336,0.317922,0.680742]],
 ("tritan",1.0):[[1.255528,-0.076749,-0.178779],[-0.078411,0.930809,0.147602],[0.004733,0.691367,0.303900]],
}
BT1=[[1.01277,0.13548,-0.14826],[-0.01243,0.86812,0.14431],[0.07589,0.80500,0.11911]]
BT2=[[0.93678,0.18979,-0.12657],[0.06154,0.81526,0.12320],[-0.37562,1.12767,0.24796]]
BTN=[0.03901,-0.02788,-0.01113]
def sim(h, kind):
    rgb=[lin(c) for c in hex2(h)]
    if kind=="normal": out=rgb
    elif kind.startswith("brettel-tritan"):
        s=float(kind.split("@")[1]); M = BT1 if sum(a*b for a,b in zip(rgb,BTN))>=0 else BT2
        o=mm(M,rgb); out=[o[i]*s+rgb[i]*(1-s) for i in range(3)]
    else:
        d,s=kind.split("@"); out=mm(MACH[(d,float(s))],rgb)
    return [enc(c) for c in out]   # clip to gamut, as a display would
def oklab(srgb):
    r,g,b=[lin(c) for c in srgb]
    l=0.4122214708*r+0.5363325363*g+0.0514459929*b
    m=0.2119034982*r+0.6806995451*g+0.1073969566*b
    s=0.0883024619*r+0.2817188376*g+0.6299787005*b
    l,m,s=[math.copysign(abs(x)**(1/3),x) for x in (l,m,s)]
    return [0.2104542553*l+0.7936177850*m-0.0040720468*s,1.9779984951*l-2.4285922050*m+0.4505937099*s,0.0259040371*l+0.7827717662*m-0.8086757660*s]
def lab(srgb):
    r,g,b=[lin(c) for c in srgb]
    X=(0.4124564*r+0.3575761*g+0.1804375*b)/0.95047; Y=0.2126729*r+0.7151522*g+0.0721750*b; Z=(0.0193339*r+0.1191920*g+0.9503041*b)/1.08883
    f=lambda t: t**(1/3) if t>216/24389 else (24389/27*t+16)/116
    fx,fy,fz=f(X),f(Y),f(Z); return [116*fy-16,500*(fx-fy),200*(fy-fz)]
def de2000(l1,l2):
    L1,a1,b1=l1;L2,a2,b2=l2
    C1=math.hypot(a1,b1);C2=math.hypot(a2,b2);Cb=(C1+C2)/2
    G=0.5*(1-math.sqrt(Cb**7/(Cb**7+25**7)))
    a1p,a2p=(1+G)*a1,(1+G)*a2;C1p,C2p=math.hypot(a1p,b1),math.hypot(a2p,b2)
    h1=math.degrees(math.atan2(b1,a1p))%360;h2=math.degrees(math.atan2(b2,a2p))%360
    dL=L2-L1;dC=C2p-C1p
    if C1p*C2p==0: dh=0
    else:
        dh=h2-h1
        if dh>180: dh-=360
        elif dh<-180: dh+=360
    dH=2*math.sqrt(C1p*C2p)*math.sin(math.radians(dh/2))
    Lb=(L1+L2)/2;Cbp=(C1p+C2p)/2
    if C1p*C2p==0: hb=h1+h2
    elif abs(h1-h2)<=180: hb=(h1+h2)/2
    elif h1+h2<360: hb=(h1+h2+360)/2
    else: hb=(h1+h2-360)/2
    T=1-0.17*math.cos(math.radians(hb-30))+0.24*math.cos(math.radians(2*hb))+0.32*math.cos(math.radians(3*hb+6))-0.20*math.cos(math.radians(4*hb-63))
    dth=30*math.exp(-((hb-275)/25)**2);Rc=2*math.sqrt(Cbp**7/(Cbp**7+25**7))
    Sl=1+0.015*(Lb-50)**2/math.sqrt(20+(Lb-50)**2);Sc=1+0.045*Cbp;Sh=1+0.015*Cbp*T;Rt=-math.sin(math.radians(2*dth))*Rc
    return math.sqrt((dL/Sl)**2+(dC/Sc)**2+(dH/Sh)**2+Rt*(dC/Sc)*(dH/Sh))
KINDS=["normal","protan@0.6","protan@1.0","deutan@0.6","deutan@1.0","brettel-tritan@1.0"]
def pair(h1,h2,k):
    s1,s2=sim(h1,k),sim(h2,k)
    o1,o2=oklab(s1),oklab(s2)
    return de2000(lab(s1),lab(s2)), 100*math.dist(o1,o2), 100*abs(o1[0]-o2[0])
RED={"light":"#ff3b30","dark":"#ff453a"}
def rows(mode):
    R=[]
    th=mode.split("-")[0]
    for a,b in itertools.combinations(ACC,2):
        R.append(("accent tint",f"{a} vs {b}",P[a][mode]["tint"],P[b][mode]["tint"]))
    for a in ACC:
        R.append(("favourite on/off",a,P[a][mode]["favourite"],P[a][mode]["favourite-off"]))
    for a in ACC:
        sw={k:P[a][mode]["swipe-"+k] for k in ["playNext","addToQueue","download","reference"]}
        for x,y in itertools.combinations(sw,2):
            R.append(("swipe",f"{a}: {x} vs {y}",sw[x],sw[y]))
    for a in ACC:
        R.append(("vs system red",f"{a} tint",P[a][mode]["tint"],RED[th]))
        R.append(("vs system red",f"{a} favourite",P[a][mode]["favourite"],RED[th]))
    return R
if __name__=="__main__":
    mode=sys.argv[1]
    print("mode",mode)
    print("| group | pair | colours | "+" | ".join(KINDS)+" |")
    for g,n,h1,h2 in rows(mode):
        cells=[]
        for k in KINDS:
            d00,dok,dL=pair(h1,h2,k); cells.append(f"{d00:.1f}/{dok:.1f}/{dL:.1f}")
        print(f"| {g} | {n} | {h1} {h2} | "+" | ".join(cells)+" |")
