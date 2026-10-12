import 'dart:convert';
import 'package:http/http.dart' as http;

/// backend/api.py 클라이언트. 이슈팝과 같은 패턴 — 로컬 개발 기본값,
/// 배포 서버 테스트는 --dart-define=API_BASE_URL=...로 오버라이드.
class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl;

  static const _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8010',
  );

  final String baseUrl;

  // 지역은 시도 코드(2자리)와 시군구 이름(region.dart)으로만 보냄 — 좌표는 resolveRegion에서 딱 한 번만 쓰임.
  Future<Map<String, dynamic>> today({String? sido, String? sgg}) => _getJson('/today', {'sido': sido, 'sgg': sgg});
  Future<Map<String, dynamic>> weather({String? sido, String? sgg}) => _getJson('/weather', {'sido': sido, 'sgg': sgg});
  Future<Map<String, dynamic>> market({String? sido, String? sgg}) => _getJson('/market', {'sido': sido, 'sgg': sgg});
  Future<Map<String, dynamic>> culture({String? sido, String? sgg}) => _getJson('/culture', {'sido': sido, 'sgg': sgg});
  Future<Map<String, dynamic>> regions() => _getJson('/regions');
  Future<Map<String, dynamic>> support({String? sido, String? sgg, String scope = 'all'}) => _getJson('/support', {'sido': sido, 'sgg': sgg, 'scope': scope});
  /// "내 조건"으로 좁힌 정부 지원. 조건은 본문(POST)으로만 보냄 — 주소창 쿼리에 넣으면 서버 접속 로그에 남기 때문.
  Future<Map<String, dynamic>> supportSearch({String? sido, String? sgg, String scope = 'all', required Map<String, dynamic> profile}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/support/search'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'sido': sido, 'sgg': sgg, 'scope': scope, ...profile}),
    );
    if (res.statusCode != 200) throw Exception('/support/search 응답 실패: ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
  Future<Map<String, dynamic>> movieDetail(String code) => _getJson('/movie/detail', {'code': code});
  Future<Map<String, dynamic>> cultureDetail(String id) => _getJson('/culture/detail', {'id': id});
  Future<Map<String, dynamic>> marketDetail({required String name, String? sigungu}) => _getJson('/market/detail', {'name': name, 'sigungu': sigungu});
  Future<Map<String, dynamic>> money() => _getJson('/money');
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
