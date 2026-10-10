# -*- coding: utf-8 -*-
"""위치(위경도) → 각 공공 API가 요구하는 좌표/지역 코드로 바꾸는 도구.

앱이 보내는 위경도(소수 둘째 자리로 뭉갠 값)만으로 전국 어디서든 동작하게 하려고
외부 지오코더 없이 계산함:
- 기상청 격자(nx, ny): 기상청 공식 람베르트 투영식
- 에어코리아 TM 좌표: 중부원점 횡메르카토르(근접 측정소 조회용, 몇백 m 오차는 무방)
- 중기예보 지역: 가장 가까운 예보 도시(기온 구역) → 육상 구역은 접두어로 유도
- 시도 코드(생활기상지수): 가장 가까운 시도청 소재지(경계 근처는 부정확, 지역 지수라 허용)
"""

from __future__ import annotations

import math

# 위치를 못 받았을 때 쓰는 기본 위치(서울시청)
DEFAULT = (37.5665, 126.9780)


def clamp_latlon(lat: float | None, lon: float | None) -> tuple[float, float]:
    """한국 범위 밖이거나 값이 없으면 기본 위치. 소수 둘째 자리(약 1km)로 정규화."""
    if lat is None or lon is None or not (32.5 <= lat <= 39.0 and 124.0 <= lon <= 132.5):
        return DEFAULT
    return round(lat, 2), round(lon, 2)


def haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    r = 6371.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dphi, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def to_grid(lat: float, lon: float) -> tuple[int, int]:
    """위경도 → 기상청 동네예보 격자(nx, ny). 서울시청 ≈ (60, 127)."""
    re, grid = 6371.00877, 5.0
    slat1, slat2, olon, olat = 30.0, 60.0, 126.0, 38.0
    xo, yo = 43, 136
    d2r = math.pi / 180.0
    re_g = re / grid
    s1, s2, ol, oa = slat1 * d2r, slat2 * d2r, olon * d2r, olat * d2r
    sn = math.tan(math.pi * 0.25 + s2 * 0.5) / math.tan(math.pi * 0.25 + s1 * 0.5)
    sn = math.log(math.cos(s1) / math.cos(s2)) / math.log(sn)
    sf = math.tan(math.pi * 0.25 + s1 * 0.5)
    sf = math.pow(sf, sn) * math.cos(s1) / sn
    ro = math.tan(math.pi * 0.25 + oa * 0.5)
    ro = re_g * sf / math.pow(ro, sn)
    ra = math.tan(math.pi * 0.25 + lat * d2r * 0.5)
    ra = re_g * sf / math.pow(ra, sn)
    theta = lon * d2r - ol
    if theta > math.pi:
        theta -= 2.0 * math.pi
    if theta < -math.pi:
        theta += 2.0 * math.pi
    theta *= sn
    return int(math.floor(ra * math.sin(theta) + xo + 0.5)), int(math.floor(ro - ra * math.cos(theta) + yo + 0.5))


def to_tm(lat: float, lon: float) -> tuple[float, float]:
    """위경도 → TM 좌표(중부원점: 위도 38°, 경도 127°, 가산 200000/500000). 에어코리아 근접 측정소 조회용."""
    a, f = 6378137.0, 1 / 298.257222101
    e2 = f * (2 - f)
    ep2 = e2 / (1 - e2)
    phi, lam = math.radians(lat), math.radians(lon)
    phi0, lam0 = math.radians(38.0), math.radians(127.0)
    k0, fe, fn = 1.0, 200000.0, 500000.0

    def meridian(p: float) -> float:
        return a * (
            (1 - e2 / 4 - 3 * e2**2 / 64 - 5 * e2**3 / 256) * p
            - (3 * e2 / 8 + 3 * e2**2 / 32 + 45 * e2**3 / 1024) * math.sin(2 * p)
            + (15 * e2**2 / 256 + 45 * e2**3 / 1024) * math.sin(4 * p)
            - (35 * e2**3 / 3072) * math.sin(6 * p)
        )

    n = a / math.sqrt(1 - e2 * math.sin(phi) ** 2)
    t, c = math.tan(phi) ** 2, ep2 * math.cos(phi) ** 2
    aa = (lam - lam0) * math.cos(phi)
    x = fe + k0 * n * (aa + (1 - t + c) * aa**3 / 6 + (5 - 18 * t + t**2 + 72 * c - 58 * ep2) * aa**5 / 120)
    y = fn + k0 * (
        meridian(phi) - meridian(phi0)
        + n * math.tan(phi) * (aa**2 / 2 + (5 - t + 9 * c + 4 * c**2) * aa**4 / 24 + (61 - 58 * t + t**2 + 600 * c - 330 * ep2) * aa**6 / 720)
    )
    return x, y


# (도시, 위도, 경도, 중기 기온 예보 구역 코드)
MID_CITIES = [
    ("서울", 37.5665, 126.9780, "11B10101"),
    ("인천", 37.4563, 126.7052, "11B20201"),
    ("수원", 37.2636, 127.0286, "11B20601"),
    ("춘천", 37.8813, 127.7298, "11D10301"),
    ("원주", 37.3422, 127.9202, "11D10401"),
    ("강릉", 37.7519, 128.8761, "11D20501"),
    ("대전", 36.3504, 127.3845, "11C20401"),
    ("서산", 36.7848, 126.4503, "11C20101"),
    ("청주", 36.6424, 127.4890, "11C10301"),
    ("전주", 35.8242, 127.1480, "11F10201"),
    ("광주", 35.1595, 126.8526, "11F20501"),
    ("목포", 34.8118, 126.3922, "21F20801"),
    ("여수", 34.7604, 127.6622, "11F20401"),
    ("대구", 35.8714, 128.6014, "11H10701"),
    ("안동", 36.5684, 128.7294, "11H10501"),
    ("포항", 36.0190, 129.3435, "11H10201"),
    ("부산", 35.1796, 129.0756, "11H20201"),
    ("울산", 35.5384, 129.3114, "11H20101"),
    ("창원", 35.2279, 128.6811, "11H20301"),
    ("제주", 33.4996, 126.5312, "11G00201"),
]

# (시도 행정구역 코드 앞 2자리, 위도, 경도) — 시도청 소재지
SIDO = [
    ("11", 37.5665, 126.9780), ("26", 35.1796, 129.0756), ("27", 35.8714, 128.6014), ("28", 37.4563, 126.7052),
    ("29", 35.1595, 126.8526), ("30", 36.3504, 127.3845), ("31", 35.5384, 129.3114), ("36", 36.4800, 127.2890),
    ("41", 37.2636, 127.0286), ("51", 37.8813, 127.7298), ("43", 36.6357, 127.4917), ("44", 36.6588, 126.6728),
    ("52", 35.8242, 127.1480), ("46", 34.8161, 126.4629), ("47", 36.5760, 128.5056), ("48", 35.2383, 128.6925),
    ("50", 33.4996, 126.5312),
]


def _nearest(lat: float, lon: float, table: list[tuple]) -> tuple:
    return min(table, key=lambda r: haversine_km((lat, lon), (r[1], r[2])))


def mid_regions(lat: float, lon: float) -> tuple[str, str]:
    """(육상예보 구역, 기온 예보 구역) — 가장 가까운 예보 도시 기준."""
    ta = _nearest(lat, lon, MID_CITIES)[3]
    land = {
        "11B": "11B00000", "11D1": "11D10000", "11D2": "11D20000", "11C1": "11C10000", "11C2": "11C20000",
        "11F1": "11F10000", "21F1": "11F10000", "11F2": "11F20000", "21F2": "11F20000", "11H1": "11H10000",
        "11H2": "11H20000", "11G": "11G00000",
    }
    for prefix, reg in land.items():
        if ta.startswith(prefix):
            return reg, ta
    return "11B00000", ta


def sido_area_no(lat: float, lon: float) -> str:
    """생활기상지수 지점코드(시도 단위 10자리)."""
    return _nearest(lat, lon, SIDO)[0] + "00000000"
