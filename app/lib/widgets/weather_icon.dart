import 'package:flutter/material.dart';

import '../theme.dart';

/// 날씨 문구(맑음·구름 많음·흐림·비·눈·소나기…)를 아이콘으로. 기상청 단기·중기 예보 문구를 그대로 받아서 찾음.
IconData weatherIconFor(String? condition) {
  final c = condition ?? '';
  if (c.contains('소나기') || c.contains('뇌우')) return Icons.thunderstorm_outlined;
  if (c.contains('비') && c.contains('눈')) return Icons.cloudy_snowing;
  if (c.contains('눈')) return Icons.ac_unit;
  if (c.contains('비') || c.contains('빗방울')) return Icons.water_drop_outlined;
  if (c.contains('흐림')) return Icons.cloud_outlined;
  if (c.contains('구름')) return Icons.filter_drama_outlined; // 해와 구름
  if (c.contains('맑')) return Icons.wb_sunny_outlined;
  return Icons.wb_cloudy_outlined;
}

class WeatherIcon extends StatelessWidget {
  const WeatherIcon(this.condition, {super.key, this.size = 20, this.color = AppColors.ink});

  final String? condition;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Icon(weatherIconFor(condition), size: size, color: color);
}
