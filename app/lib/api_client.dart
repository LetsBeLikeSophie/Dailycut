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

  // 위치(lat, lon)는 소수 둘째 자리로 뭉갠 값만 받음(location.dart). 날씨·문화는 이 위치 기준.
  Future<Map<String, dynamic>> today({double? lat, double? lon}) => _getJson('/today', lat: lat, lon: lon);
  Future<Map<String, dynamic>> weather({double? lat, double? lon}) => _getJson('/weather', lat: lat, lon: lon);
  Future<Map<String, dynamic>> market() => _getJson('/market');
  Future<Map<String, dynamic>> culture({double? lat, double? lon}) => _getJson('/culture', lat: lat, lon: lon);
  Future<Map<String, dynamic>> money() => _getJson('/money');
  Future<Map<String, dynamic>> ai() => _getJson('/ai');

  Future<Map<String, dynamic>> _getJson(String path, {double? lat, double? lon}) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: (lat != null && lon != null) ? {'lat': '$lat', 'lon': '$lon'} : null,
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('$path 응답 실패: ${res.statusCode}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}
