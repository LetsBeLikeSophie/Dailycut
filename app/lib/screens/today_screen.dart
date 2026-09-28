import 'package:flutter/material.dart';
import '../api_client.dart';
import '../theme.dart';
import '../widgets/components.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.today();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('불러오지 못했어요\n${snapshot.error}', textAlign: TextAlign.center));
        }
        final data = snapshot.data!;
        final cards = (data['cards'] as List).cast<Map<String, dynamic>>();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            Text(data['headline'] as String, style: AppTheme.displaySerif(size: 24)),
            const SizedBox(height: 20),
            for (final c in cards) ...[
              HeroCard(
                section: Section.values.byName(c['section'] as String),
                title: (c['title'] ?? c['label'] ?? '') as String,
                highlight: c['highlight'] as String?,
                meta: (c['meta'] ?? c['value']?.toString()) as String?,
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}
