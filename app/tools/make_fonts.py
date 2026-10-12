# 2026-10-12: 앱에 넣는 한글 폰트 서브셋 만드는 법. 원본(variable)은 github.com/google/fonts ofl/notosanskr·notoserifkr 에서 받아 이 폴더 밖 scratch_fonts/ 에 두고 실행
# (pip install fonttools). 결과를 app/assets/fonts/ 에 복사하고 파일 이름 뒤 버전(-r2 …)을 올릴 것 — 서버가 폰트를 30일 immutable 캐시하므로.
import os,sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset

# KS X 1001 한글 2350자
ks=set()
for hi in range(0xB0,0xC9):
    for lo in range(0xA1,0xFF):
        try: ks.add(bytes([hi,lo]).decode('euc-kr'))
        except Exception: pass
ks={c for c in ks if '가'<=c<='힣'}
print("hangul",len(ks))
extra=list(range(0x20,0x7F))+list(range(0xA0,0x180))+list(range(0x2000,0x2070))+list(range(0x2100,0x2200))+list(range(0x2190,0x2200))+list(range(0x2460,0x2500))+list(range(0x2600,0x27C0))+[0x30FB,0xFF0D]+list(range(0x25A0,0x2600))+list(range(0x3000,0x3040))+list(range(0x3130,0x318F))+list(range(0x3380,0x33E0))+[0xFFE6,0xFF5E,0xFF01,0xFF08,0xFF09,0xFF0C]
base=set(extra)|{ord(c) for c in ks}
digits=set(range(0x20,0x7F))|{0xB7,0x2009}|set(range(0x2000,0x2070))

def build(src,wght,out,unis):
    f=TTFont(src)
    inst=instancer.instantiateVariableFont(f,{"wght":wght})
    opts=subset.Options(); opts.layout_features=["kern","liga","locl"]; opts.name_IDs=[1,2,3,4,6]; opts.notdef_outline=True; opts.hinting=False; opts.drop_tables+=["DSIG"]
    s=subset.Subsetter(opts); s.populate(unicodes=unis); s.subset(inst)
    inst.save(out); print(out,os.path.getsize(out)//1024,"KB")

os.makedirs("out",exist_ok=True)
for w in (400,700): build("NotoSansKR[wght%5D.ttf",w,f"out/NotoSansKR-{w}-r2.ttf",base)
build("NotoSerifKR[wght%5D.ttf",700,"out/NotoSerifKR-700-r2.ttf",base)
build("NotoSerifKR[wght%5D.ttf",900,"out/NotoSerifKR-900-r2.ttf",digits)
