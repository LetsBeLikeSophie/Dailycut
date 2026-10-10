# -*- coding: utf-8 -*-
"""공공데이터포털 호출 공통 도구.

- 인증키는 DECODED 값을 requests params로 넘겨서 라이브러리가 인코딩하게 함
  (ENCODED를 params에 넣으면 이중 인코딩돼서 SERVICE_KEY_IS_NOT_REGISTERED가 남).
- requests 예외 메시지에는 키가 담긴 URL이 들어가므로, 그대로 올리지 않고
  키가 없는 짧은 메시지로 바꿔서 던짐(job_status에 저장되는 값이라서).
"""

from __future__ import annotations

import xml.etree.ElementTree as ET

import requests

import config

KEY_ENV = "DATA_GO_KR_SERVICE_KEY_DECODED"
OK_CODES = {"00", "0", "0000", "03"}  # 03: NODATA_ERROR(데이터 없음)는 빈 목록으로 취급


def get(url: str, params: dict | None = None, timeout: int = 20) -> requests.Response:
    key = config.get_key(KEY_ENV)
    if not key:
        raise RuntimeError("공공데이터포털 인증키 없음")
    r = None
    for attempt in range(2):  # 포털이 가끔 일시적으로 5xx/타임아웃을 줘서 한 번만 재시도
        try:
            r = requests.get(url, params={"serviceKey": key, **(params or {})}, timeout=timeout)
        except requests.RequestException as e:
            if attempt == 1:
                raise RuntimeError(f"요청 실패({type(e).__name__})") from None
            continue
        if r.status_code < 500 or attempt == 1:
            break
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}")
    return r


def _check(code: str | None, msg: str | None) -> None:
    if code is not None and str(code) not in OK_CODES:
        raise RuntimeError(f"API 오류 {code} {msg or ''}".strip())


def get_json(url: str, params: dict | None = None, timeout: int = 20) -> dict:
    """응답 JSON의 response.body를 돌려줌(오류 코드면 예외)."""
    try:
        data = get(url, params, timeout).json()
    except ValueError:
        raise RuntimeError("JSON 아님") from None
    resp = data.get("response", data)
    header = resp.get("header") or {}
    _check(header.get("resultCode"), header.get("resultMsg"))
    return resp.get("body") or {}


def items_of(body: dict) -> list[dict]:
    """body.items.item(또는 body.items)을 항상 dict 리스트로."""
    items = body.get("items")
    if isinstance(items, dict):
        items = items.get("item")
    if not items:
        return []
    return items if isinstance(items, list) else [items]


def get_xml_items(url: str, params: dict | None = None, timeout: int = 20) -> list[dict]:
    """XML 응답의 <item>들을 {태그: 글자} dict 리스트로."""
    root = ET.fromstring(get(url, params, timeout).content)
    _check(root.findtext(".//resultCode"), root.findtext(".//resultMsg"))
    return [{c.tag: (c.text or "").strip() for c in it} for it in root.iter("item")]
