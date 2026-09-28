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

  Future<Map<String, dynamic>> today() => _getJson('/today');
  Future<Map<String, dynamic>> market() => _getJson('/market');
  Future<Map<String, dynamic>> culture() => _getJson('/culture');
  Future<Map<String, dynamic>> money() => _getJson('/money');
  Future<Map<String, dynamic>> ai() => _getJson('/ai');

  Future<Map<String, dynamic>> _getJson(String path) async {
    final res = await http.get(Uri.parse('$baseUrl$path'));
    if (res.statusCode != 200) {
      throw Exception('$path 응답 실패: ${res.statusCode}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}
