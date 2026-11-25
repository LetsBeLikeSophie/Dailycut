from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, sys
FONTS='C:/Projects/dailycut/app/assets/fonts/'
SERIF=lambda s: ImageFont.truetype(FONTS+'NotoSerifKR-700-r2.ttf', s)
SANS7=lambda s: ImageFont.truetype(FONTS+'NotoSansKR-700-r2.ttf', s)
SANS4=lambda s: ImageFont.truetype(FONTS+'NotoSansKR-400-r2.ttf', s)
W,H=1080,2160
INK=(26,26,26); GRAY=(110,110,110)

# (파일, 섹션 이름, 제목 줄들, 형광펜 칠할 낱말(줄 번호, 글자), 설명)
SLIDES=[
 ('1_benefit','혜택',['받을 수 있는 혜택,','한 번에 찾아봐요'],(0,'혜택'),'정부 지원 · 청약 · 공공임대 · 내 조건으로 추리기'),
 ('2_rent','혜택',['우리 동네 전월세,','요즘 얼마일까요?'],(0,'전월세'),'실거래가로 계산한 아파트·오피스텔 시세'),
 ('3_localcur','혜택',['우리 동네 상품권,','어디서 쓸 수 있을까?'],(0,'상품권'),'지역사랑상품권 결제 현황과 쓸 수 있는 가게'),
 ('4_life','생활',['이번 주 장바구니,','얼마나 올랐을까?'],(1,'올랐을까'),'채소·과일·수산·정육 시세를 지난주와 비교'),
 ('5_today','투데이',['오늘 날씨,','한눈에 확인해요'],(1,'한눈에'),'옷차림 추천 · 시간대별 · 주간 예보 · 미세먼지'),
 ('6_culture','문화',['우리 동네 이번 주','행사는 뭐가 있지?'],(0,'이번 주'),'축제 · 전시 · 공연을 달력으로 모아 봐요'),
 ('7_outing','나들이',['이번 주말,','어디가 한산할까?'],(1,'한산할까'),'덜 붐비는 관광지 · 도서관 · 캠핑 · 반려동물 동반'),
 ('8_museum','나들이',['가까운 박물관·미술관,','둘러볼까요?'],(0,'박물관·미술관'),'공립·사립 구분과 주소까지 한 번에'),
]
# 2026-11-26: 검색·스토어 첫인상 때문에 순서를 혜택 중심으로 바꿈(날씨는 경쟁이 가장 심한 분야라 5번째로). 원본 캡처 파일 이름은 그대로.
RAW={'1_benefit':'raw_5_benefit.png','2_rent':'raw_6_rent.png','3_localcur':'raw_7_localcur.png','4_life':'raw_2_life.png',
     '5_today':'raw_1_today.png','6_culture':'raw_3_culture.png','7_outing':'raw_4_outing.png','8_museum':'raw_8_museum.png'}

def accent(img):
    px=img.convert('RGB')
    w,h=px.size
    best=None
    for (x,y) in [(int(w*.85),int(h*.02)),(int(w*.9),int(h*.04)),(int(w*.8),int(h*.05)),(int(w*.88),int(h*.06))]:
        c=px.getpixel((x,y))
        if sum(c)<690: best=c; break
    return best or (224,137,60)

def mix(c,t,a): return tuple(int(c[i]*(1-a)+t[i]*a) for i in range(3))

os.makedirs('out',exist_ok=True)
for name,label,lines,(hl_line,hl_word),sub in SLIDES:
    shot=Image.open(RAW[name]).convert('RGB')
    ac=accent(shot)
    bg=mix(ac,(255,255,255),0.90)
    can=Image.new('RGB',(W,H),bg)
    d=ImageDraw.Draw(can,'RGBA')
    # 섹션 이름(작게, 섹션 색)
    f=SANS7(38)
    d.text((84,96),'데일리컷  ·  '+label,font=f,fill=mix(ac,(0,0,0),0.18))
    # 제목(세리프) + 형광펜
    ft=SERIF(80); y=170
    for i,ln in enumerate(lines):
        if i==hl_line and hl_word in ln:
            pre=ln[:ln.index(hl_word)]
            x0=84+d.textlength(pre,font=ft); x1=x0+d.textlength(hl_word,font=ft)
            d.rectangle([x0-6,y+50,x1+6,y+112],fill=ac+(95,))
        d.text((84,y),ln,font=ft,fill=INK)
        y+=108
    d.text((84,y+14),sub,font=SANS4(34),fill=GRAY)
    # 폰 화면: 둥근 모서리 + 얇은 테두리 + 부드러운 그림자
    pw=736; ph=int(shot.height*pw/shot.width)
    s=shot.resize((pw,ph),Image.LANCZOS)
    top=H-ph-70
    if top<470: # 너무 길면 아래를 잘라 맞춤
        top=470; ph=H-top-70; s=s.crop((0,0,pw,ph))
    px_=(W-pw)//2
    shadow=Image.new('RGBA',(W,H),(0,0,0,0))
    ImageDraw.Draw(shadow).rounded_rectangle([px_,top+18,px_+pw,top+ph+18],radius=70,fill=(0,0,0,70))
    shadow=shadow.filter(ImageFilter.GaussianBlur(26))
    can=Image.alpha_composite(can.convert('RGBA'),shadow)
    mask=Image.new('L',(pw,ph),0)
    ImageDraw.Draw(mask).rounded_rectangle([0,0,pw-1,ph-1],radius=64,fill=255)
    can.paste(s,(px_,top),mask)
    ImageDraw.Draw(can).rounded_rectangle([px_,top,px_+pw-1,top+ph-1],radius=64,outline=(30,30,30,60),width=2)
    can.convert('RGB').save(f'out/{name}.png',optimize=True)
    print(name,ac,os.path.getsize(f'out/{name}.png')//1024,'KB')
