import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/config/app_config.dart';
import '../../../map/data/db/cache_db.dart';
import '../../../map/presentation/controllers/map_controller.dart';
import '../controllers/theme_mode_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mapControllerProvider);
    final c = ref.read(mapControllerProvider.notifier);
    final themeSettings = ref.watch(themeSettingsProvider);
    final theme = ref.read(themeSettingsProvider.notifier);
    final mode = themeSettings.mode;
    final accent = themeSettings.accent;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Theme mode',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) => theme.setMode(s.first),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Accent color',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AccentTheme.values
                        .map(
                          (value) => ChoiceChip(
                            selected: value == accent,
                            label: Text(_accentLabel(value)),
                            onSelected: (_) => theme.setAccent(value),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                const ListTile(
                  title: Text('API base URL'),
                  subtitle: Text(
                    '${AppConfig.apiBaseUrl}${AppConfig.apiPrefix}',
                  ),
                ),
                ListTile(
                  title: const Text('Last successful sync'),
                  subtitle: Text(
                    state.lastSync?.toLocal().toString() ?? 'Not yet',
                  ),
                ),
                const ListTile(
                  title: Text('App version'),
                  subtitle: Text(AppConfig.appVersion),
                ),
                FutureBuilder<Map<String, int>>(
                  future: CacheDb.instance.status(),
                  builder: (context, snapshot) {
                    final count = snapshot.data?.length ?? 0;
                    return ListTile(
                      title: const Text('Cache entries'),
                      subtitle: Text('$count'),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => c.loadInitial(force: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Force refresh'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: c.clearCache,
            icon: const Icon(Icons.delete_sweep),
            label: const Text('Clear cache'),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Developer tools',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hidden from release builds. Use only for alert diagnostics.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: c.runAlertCheckNow,
                          icon: const Icon(Icons.play_arrow_outlined),
                          label: const Text('Run alert check now'),
                        ),
                        OutlinedButton.icon(
                          onPressed: c.startAlertServiceForDebug,
                          icon: const Icon(Icons.play_circle_outline),
                          label: const Text('Start alert service'),
                        ),
                        OutlinedButton.icon(
                          onPressed: c.stopAlertServiceForDebug,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Stop alert service'),
                        ),
                        OutlinedButton.icon(
                          onPressed: c.sendTestNotification,
                          icon: const Icon(Icons.notification_add_outlined),
                          label: const Text('Send test notification'),
                        ),
                        OutlinedButton.icon(
                          onPressed: c.clearStoredAlerts,
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('Clear stored alerts'),
                        ),
                        OutlinedButton.icon(
                          onPressed: c.resetAlertSystem,
                          icon: const Icon(Icons.restore_outlined),
                          label: const Text('Reset alert system'),
                        ),
                        OutlinedButton.icon(
                          onPressed: c.testAlertStorage,
                          icon: const Icon(Icons.science_outlined),
                          label: const Text('Test alert storage'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<Map<String, dynamic>>(
                      future: _cacheDiagnostics(state),
                      builder: (context, snapshot) {
                        final data = snapshot.data ?? const <String, dynamic>{};
                        final lastStaticSyncAt =
                            data['lastStaticSyncAt'] as DateTime?;
                        final lastReadAt = data['lastCacheReadAt'] as DateTime?;
                        final lastWriteAt =
                            data['lastCacheWriteAt'] as DateTime?;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cache diagnostics',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Selected area: ${state.selectedAreaCode} | '
                              'Routes shown: ${state.routes.length} | '
                              'Cached routes for area: ${data['cachedRoutesForSelectedArea'] ?? 0}',
                            ),
                            Text(
                              'Cache entries: ${data['cacheEntries'] ?? 0} | '
                              'Geometry cache: ${data['geometryCacheCount'] ?? 0} | '
                              'ETA cache: ${data['etaCacheCount'] ?? 0}',
                            ),
                            Text(
                              'Last static sync: ${lastStaticSyncAt?.toLocal() ?? 'n/a'}',
                            ),
                            Text(
                              'Last cache read: ${lastReadAt?.toLocal() ?? 'n/a'}',
                            ),
                            Text(
                              'Last cache write: ${lastWriteAt?.toLocal() ?? 'n/a'}',
                            ),
                            Text(
                              'Last cache error: ${data['lastCacheError'] ?? 'none'}',
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _accentLabel(AccentTheme accentTheme) {
    return switch (accentTheme) {
      AccentTheme.system => 'System dynamic',
      AccentTheme.rtlDefault => 'Default RTL',
      AccentTheme.blue => 'Blue',
      AccentTheme.green => 'Green',
      AccentTheme.purple => 'Purple',
      AccentTheme.rose => 'Rose',
      AccentTheme.orange => 'Orange',
    };
  }

  Future<Map<String, dynamic>> _cacheDiagnostics(MapState state) async {
    final diagnostics = await CacheDb.instance.diagnostics();
    final routesCache = await CacheDb.instance.get('routes');
    var cachedRoutesForSelectedArea = 0;
    final rawRoutes = routesCache?['value'];
    if (rawRoutes is List) {
      cachedRoutesForSelectedArea = rawRoutes
          .whereType<Map>()
          .where((r) => '${r['areaCode']}' == state.selectedAreaCode)
          .length;
    }
    return {
      ...diagnostics,
      'cachedRoutesForSelectedArea': cachedRoutesForSelectedArea,
    };
  }
}
