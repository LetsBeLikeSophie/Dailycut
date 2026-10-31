import 'dart:convert';
import 'package:http/http.dart' as http;

import 'splash_stub.dart' if (dart.library.js_interop) 'splash_web.dart' show takeEarlyWeather;

/// backend/api.py 클라이언트. 이슈팝과 같은 패턴 — 로컬 개발 기본값,
/// 배포 서버 테스트는 --dart-define=API_BASE_URL=...로 오버라이드.
class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl;

  static const _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8010',
  );

  final String baseUrl;

  // 2026-10-16: 같은 요청을 화면마다 따로 기억하던 것(장소·혜택·정부 지원·한산한 곳·장바구니·날씨 문장 6곳)을 여기 한 곳으로 합침.
  // 같은 조건의 요청은 [ttl] 동안 다시 보내지 않고 받는 중인 요청도 함께 씀(투데이·나들이 날씨, 생활·투데이 장바구니가 한 번만 받음).
  // 실패한 요청은 기억하지 않아 "눌러서 다시 시도"가 새로 요청함.
  final Map<String, ({DateTime at, Future<Map<String, dynamic>> future})> _memo = {};

  Future<Map<String, dynamic>> _memoGet(String key, Duration ttl, Future<Map<String, dynamic>> Function() load) {
    final hit = _memo[key];
    if (hit != null && DateTime.now().difference(hit.at) < ttl) return hit.future;
    final f = load();
    _memo[key] = (at: DateTime.now(), future: f);
    f.catchError((_) {
      _memo.remove(key);
      return <String, dynamic>{};
    });
    return f;
  }

  static const _min1 = Duration(minutes: 1);
  static const _min5 = Duration(minutes: 5);
  static const _min10 = Duration(minutes: 10);
  static const _min30 = Duration(minutes: 30);

  // 지역은 시도 코드(2자리)와 시군구 이름(region.dart)으로만 보냄 — 좌표는 resolveRegion에서 딱 한 번만 쓰임.
  Future<Map<String, dynamic>> today({String? sido, String? sgg}) => _memoGet('today/$sido/$sgg', _min5, () => _getJson('/today', {'sido': sido, 'sgg': sgg}));

  bool _earlyTried = false; // index.html 스플래시가 미리 받아 둔 날씨는 첫 요청에 한 번만 씀

  Future<Map<String, dynamic>> weather({String? sido, String? sgg}) => _memoGet('weather/$sido/$sgg', _min10, () async {
        if (!_earlyTried) {
          _earlyTried = true;
          final early = await takeEarlyWeather('${sido ?? '11'}|${sgg ?? ''}');
          if (early != null) return early; // 같은 지역이면 스플래시가 받은 응답을 그대로(같은 요청을 두 번 보내지 않음)
        }
        return _getJson('/weather', {'sido': sido, 'sgg': sgg});
      });

  Future<Map<String, dynamic>> market({String? sido, String? sgg}) => _memoGet('market/$sido/$sgg', _min10, () => _getJson('/market', {'sido': sido, 'sgg': sgg}));
  Future<Map<String, dynamic>> culture({String? sido, String? sgg}) => _memoGet('culture/$sido/$sgg', _min5, () => _getJson('/culture', {'sido': sido, 'sgg': sgg}));
  Future<Map<String, dynamic>> regions() => _memoGet('regions', const Duration(days: 1), () => _getJson('/regions'));
  Future<Map<String, dynamic>> support({String? sido, String? sgg, String scope = 'all'}) =>
      _memoGet('support/$sido/$sgg/$scope', _min10, () => _getJson('/support', {'sido': sido, 'sgg': sgg, 'scope': scope}));

  /// "내 조건"으로 좁힌 정부 지원. 조건은 본문(POST)으로만 보냄 — 주소창 쿼리에 넣으면 서버 접속 로그에 남기 때문.
  Future<Map<String, dynamic>> supportSearch({String? sido, String? sgg, String scope = 'all', required Map<String, dynamic> profile}) {
    final body = jsonEncode({'sido': sido, 'sgg': sgg, 'scope': scope, ...profile});
    return _memoGet('support-search/$body', _min10, () async {
      final res = await http.post(
        Uri.parse('$baseUrl/support/search'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      if (res.statusCode != 200) throw Exception('/support/search 응답 실패: ${res.statusCode}');
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    });
  }

  /// 청약(kind=apply)·공공임대(kind=rent) 공고, 서민 대출. 지역은 시도 코드·시군구 이름으로만 보냄.
  Future<Map<String, dynamic>> benefitsHousing({required String kind, String? sido, String? sgg}) =>
      _memoGet('housing/$kind/$sido/$sgg', _min10, () => _getJson('/benefits/housing', {'kind': kind, 'sido': sido, 'sgg': sgg}));
  /// 전월세 시세(국토부 실거래가 요약). 시군구를 고른 경우만 값이 있고, 처음 부르는 지역은 몇 초 걸릴 수 있음.
  Future<Map<String, dynamic>> rentMarket({String? sido, String? sgg}) =>
      _memoGet('rentmarket/$sido/$sgg', _min30, () => _getJson('/benefits/rentmarket', {'sido': sido, 'sgg': sgg}));
  Future<Map<String, dynamic>> benefitsLoans({String? usage, String? sido}) => _memoGet('loans/$usage/$sido', _min10, () => _getJson('/benefits/loans', {'usage': usage, 'sido': sido}));

  /// 이번 주말 한산한 곳(관광지 집중률 예측 + 그날 날씨). 처음 부르는 지역은 몇 초 걸릴 수 있음.
  Future<Map<String, dynamic>> outing({String? sido, String? sgg}) => _memoGet('outing/$sido/$sgg', _min30, () => _getJson('/outing', {'sido': sido, 'sgg': sgg}));

  /// 나들이: kind = library | camp | pet | wellness | trail (도서관 좌석은 자주 바뀌어 1분, 나머지는 30분)
  Future<Map<String, dynamic>> places({required String kind, String? sido, String? sgg}) =>
      _memoGet('places/$kind/$sido/$sgg', kind == 'library' ? _min1 : _min30, () => _getJson('/places', {'kind': kind, 'sido': sido, 'sgg': sgg}));

  Future<Map<String, dynamic>> cultureDetail(String id) => _memoGet('culture-detail/$id', _min30, () => _getJson('/culture/detail', {'id': id}));
  Future<Map<String, dynamic>> marketDetail({required String name, String? sigungu}) =>
      _memoGet('market-detail/$name/$sigungu', _min30, () => _getJson('/market/detail', {'name': name, 'sigungu': sigungu}));
  Future<Map<String, dynamic>> ai() => _getJson('/ai');

  /// 좌표(소수 둘째 자리로 뭉갠 값) → 시도. 서버는 좌표를 저장하지 않음.
  /// POST 본문으로 보냄(주소창 쿼리에 넣으면 서버 접속 로그에 좌표가 남기 때문).
  Future<Map<String, dynamic>> resolveRegion({required double lat, required double lon}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/region'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'lat': lat, 'lon': lon}),
    );
    if (res.statusCode != 200) throw Exception('/region 응답 실패: ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _getJson(String path, [Map<String, String?> query = const {}]) async {
    final q = {
      for (final e in query.entries)
        if (e.value != null) e.key: e.value!,
    };
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: q.isEmpty ? null : q);
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('$path 응답 실패: ${res.statusCode}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}
