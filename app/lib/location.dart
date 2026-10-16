import 'package:geolocator/geolocator.dart';

/// 위치 권한 상태(2026-10-17): 화면(location_flow.dart)이 "물어보기 전에 설명 → 허용/거부에 따른 안내"를 하려고 권한을 묻는 것과 읽는 것을 나눔.
enum LocationAccess {
  granted, // 허용됨(위치 서비스도 켜짐)
  askable, // 아직 안 물어봤거나 한 번 거부해서 다시 물어볼 수 있음
  blocked, // "다시 묻지 않음"으로 막힘 — 폰 설정에서만 풀 수 있음
  off, // 허용은 됐지만 폰의 위치 서비스(GPS)가 꺼져 있음
}

class UserLocation {
  const UserLocation(this.lat, this.lon);

  final double lat;
  final double lon;
}

/// 위치는 "내 지역 찾기"에 딱 한 번만 씀(찾은 지역은 기기에 저장해서 다음 실행부턴 위치를 다시 읽지 않음 — region.dart).
/// 개인정보 때문에 서버로 보내기 전에 소수 둘째 자리(약 1km)로 뭉개고, 정확한 현재 위치는 저장하지 않음.
class LocationService {
  static LocationAccess _map(LocationPermission p) => switch (p) {
        LocationPermission.deniedForever => LocationAccess.blocked,
        LocationPermission.whileInUse || LocationPermission.always => LocationAccess.granted,
        _ => LocationAccess.askable,
      };

  /// 지금 권한 상태(묻지는 않음).
  static Future<LocationAccess> access() async {
    try {
      final a = _map(await Geolocator.checkPermission());
      if (a == LocationAccess.granted && !await Geolocator.isLocationServiceEnabled()) return LocationAccess.off;
      return a;
    } catch (_) {
      return LocationAccess.askable;
    }
  }

  /// 시스템 권한 창을 띄움(설명을 보여 준 뒤에만 부를 것).
  static Future<LocationAccess> request() async {
    try {
      final a = _map(await Geolocator.requestPermission());
      if (a == LocationAccess.granted && !await Geolocator.isLocationServiceEnabled()) return LocationAccess.off;
      return a;
    } catch (_) {
      return LocationAccess.askable;
    }
  }

  static double _coarse(double v) => (v * 100).round() / 100;

  /// 현재 위치(대략). 못 받으면 null.
  static Future<UserLocation?> read() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low, // 동네 단위면 충분해서 배터리를 아낌
          timeLimit: Duration(seconds: 8),
        ),
      );
      return UserLocation(_coarse(pos.latitude), _coarse(pos.longitude));
    } catch (_) {
      return null;
    }
  }

  static Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }
}
