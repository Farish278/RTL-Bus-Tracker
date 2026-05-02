import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/settings/presentation/controllers/theme_mode_controller.dart';
import '../main.dart';
import 'router.dart';
import 'theme.dart';

class RtlBusTrackerApp extends ConsumerWidget {
  const RtlBusTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeSettingsProvider);
    final safeMode = ThemeMode.values.contains(themeSettings.mode)
        ? themeSettings.mode
        : ThemeMode.system;

    return ValueListenableBuilder<StartupErrorState?>(
      valueListenable: startupErrorNotifier,
      builder: (context, startupError, _) {
        final accentTheme = themeSettings.accent;
        if (startupError != null) {
          return _StartupErrorApp(
            error: startupError,
            themeMode: safeMode,
            accentTheme: accentTheme,
          );
        }
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            try {
              final router = ref.watch(appRouterProvider);
              return MaterialApp.router(
                title: 'RTL Bus Tracker',
                debugShowCheckedModeBanner: false,
                theme: buildTheme(
                  brightness: Brightness.light,
                  accentTheme: accentTheme,
                  dynamicScheme: lightDynamic,
                ),
                darkTheme: buildTheme(
                  brightness: Brightness.dark,
                  accentTheme: accentTheme,
                  dynamicScheme: darkDynamic,
                ),
                themeMode: safeMode,
                routerConfig: router,
                builder: (context, child) =>
                    child ?? const _EmptyRootFallback(),
              );
            } catch (e, st) {
              startupErrorNotifier.value = StartupErrorState(e, st);
              return _StartupErrorApp(
                error: StartupErrorState(e, st),
                themeMode: safeMode,
                accentTheme: accentTheme,
              );
            }
          },
        );
      },
    );
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({
    required this.error,
    required this.themeMode,
    required this.accentTheme,
  });

  final StartupErrorState error;
  final ThemeMode themeMode;
  final AccentTheme accentTheme;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RTL Bus Tracker',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness: Brightness.light, accentTheme: accentTheme),
      darkTheme: buildTheme(
        brightness: Brightness.dark,
        accentTheme: accentTheme,
      ),
      themeMode: themeMode,
      home: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RTL Bus Tracker',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text('Something went wrong while starting the app'),
                      if (kDebugMode) ...[
                        const SizedBox(height: 10),
                        Text(
                          '${error.error}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRootFallback extends StatelessWidget {
  const _EmptyRootFallback();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: const Center(child: Text('Loading RTL Bus Tracker...')),
    );
  }
}
