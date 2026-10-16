import 'package:flutter/material.dart';

import '../theme.dart';
import 'components.dart';
import 'weather_icon.dart';

/// 주간 한 줄: 왼쪽에 요일(오늘은 강조)과 그 아래 날짜, 가운데 날씨, 오른쪽 최저/최고.
/// 기상청이 안 주는 날(단기·중기예보 사이)은 "예보 없음"으로 비워둠.
Widget weeklyRow(Map<String, dynamic> w, {String? hint}) {
  final high = w['high'];
  final has = high != null;
  final pop = (w['pop'] as num?)?.toInt() ?? 0;
  final today = w['is_today'] == true;
  return ListLine(
    leading: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                w['day'] as String,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: today ? AppColors.ink : AppColors.ink,
                ),
              ),
              Text(
                w['date'] as String,
                style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 22,
          child: has ? WeatherIcon(w['condition'] as String?, size: 20) : null,
        ),
      ],
    ),
    name: has ? (w['condition'] as String? ?? '') : '예보 없음',
    sub: has ? hint : '기상청이 이 날은 제공하지 않아요',
    middle: pop > 0
        ? Text(
            '$pop%',
            style: const TextStyle(fontSize: 13, color: AppColors.down),
          )
        : null,
    value: has ? '${w['low']}° / $high°' : '–',
  );
}
