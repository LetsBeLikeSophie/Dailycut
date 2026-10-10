import 'package:geolocator/geolocator.dart';

/// 사용자 위치. real=false면 위치를 못 받아서(거부/꺼짐/시간 초과) 기본 위치(서울시청)를 쓴 것.
class UserLocation {
  const UserLocation(this.lat, this.lon, this.real);

  final double lat;
  final double lon;
  final bool real;
}

/// 위치는 앱을 켠 뒤 한 번만 물어보고(권한 요청 포함) 모든 화면이 같은 값을 씀.
/// 개인정보 때문에 서버로 보내기 전에 소수 둘째 자리(약 1km)로 뭉개고, 정확한
/// 현재 위치는 저장하지 않음. 날씨·문화 데이터가 이 위치 기준으로 가까운 것을 보여줌.
class LocationService {
  static const _seoul = UserLocation(37.5665, 126.9780, false);
  static Future<UserLocation>? _cached;

  static Future<UserLocation> get() => _cached ??= _resolve();

  static double _coarse(double v) => (v * 100).round() / 100;

  static Future<UserLocation> _resolve() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return _seoul;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low, // 동네 단위면 충분해서 배터리를 아낌
          timeLimit: Duration(seconds: 8),
        ),
      );
      return UserLocation(_coarse(pos.latitude), _coarse(pos.longitude), true);
    } catch (_) {
      return _seoul;
    }
  }
}
