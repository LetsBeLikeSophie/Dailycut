import 'package:flutter_test/flutter_test.dart';
import 'package:dailycut/widgets/support_profile.dart';

void main() {
  final today = DateTime(2026, 10, 13);
  test('만 나이: 생일 전/후', () {
    expect(ageFromBirth('1992-10-13', today: today), 34); // 생일 당일
    expect(ageFromBirth('1992-10-14', today: today), 33); // 하루 전
    expect(ageFromBirth('2000-02-29', today: today), 26);
    expect(ageFromBirth('2027-01-01', today: today), null); // 미래
  });
  test('생년월일 검증', () {
    expect(birthFromParts('1990', '5', '12', today: today), '1990-05-12');
    expect(birthFromParts('1990', '2', '30', today: today), null); // 없는 날짜
    expect(birthFromParts('1990', '13', '1', today: today), null);
    expect(birthFromParts('90', '5', '12', today: today), null); // 4자리 아님
    expect(birthFromParts('2030', '1', '1', today: today), null); // 미래
  });
}
