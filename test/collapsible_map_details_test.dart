import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtl_bus_tracker/features/map/presentation/widgets/collapsible_map_details.dart';

Widget harness({
  Object? selection = 'route:1',
  String content = 'Selected details',
  bool dark = false,
  bool reducedMotion = false,
  double textScale = 1,
  VoidCallback? onMapTap,
  VoidCallback? onOpened,
}) => MaterialApp(
  theme: dark ? ThemeData.dark() : ThemeData.light(),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(800, 600),
      padding: const EdgeInsets.only(bottom: 24),
      disableAnimations: reducedMotion,
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onMapTap,
              child: const Text('Map'),
            ),
          ),
          CollapsibleMapDetails(
            selectionKey: selection,
            onOpened: onOpened,
            icon: Icons.route,
            detailsBuilder: (_) =>
                Column(children: [Text(content), const SizedBox(height: 1000)]),
            overlaysBuilder: (_, bottom) => [
              Positioned(
                key: const ValueKey('map-control'),
                right: 12,
                bottom: bottom,
                child: const SizedBox(width: 48, height: 48),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'loads details only on explicit opening, not refreshes or drags',
    (tester) async {
      var opens = 0;
      await tester.pumpWidget(harness(onOpened: () => opens++));
      expect(opens, 0);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(opens, 1);
      await tester.pumpWidget(
        harness(content: 'Updated details', onOpened: () => opens++),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(opens, 1);
      await tester.drag(find.byType(ListView), const Offset(0, 700));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(opens, 2);
    },
  );

  testWidgets('all selection types open only on request and collapse to pill', (
    tester,
  ) async {
    for (final selection in ['route:1', 'stop:2', 'bus:3']) {
      await tester.pumpWidget(harness(selection: selection));
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Selected details'), findsNothing);
      final pill = tester.getRect(find.byType(FilledButton));
      expect(pill.height, greaterThanOrEqualTo(48));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Selected details'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      expect(find.text('Details'), findsNothing);
      expect(tester.getRect(find.byType(ListView)).top, closeTo(300, 1));
      await tester.drag(find.byType(ListView), const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Selected details'), findsOneWidget);
    }
  });

  testWidgets('refresh preserves extent; changed selection starts collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(harness(content: 'Updated details'));
    expect(find.text('Updated details'), findsOneWidget);
    expect(find.text('Details'), findsNothing);
    await tester.pumpWidget(harness(selection: 'stop:2'));
    expect(find.text('Details'), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    await tester.pumpWidget(harness(selection: null));
    expect(find.text('Details'), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    await tester.pumpWidget(harness(selection: 'route:1'));
    expect(find.text('Details'), findsOneWidget);
  });

  testWidgets('drag updates controls and collapses at minimum extent', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    final initialControl = tester.getRect(
      find.byKey(const ValueKey('map-control')),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    final expandedControl = tester.getRect(
      find.byKey(const ValueKey('map-control')),
    );
    expect(expandedControl.top, lessThan(initialControl.top));
    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    final collapsedControl = tester.getRect(
      find.byKey(const ValueKey('map-control')),
    );
    expect(collapsedControl.top, greaterThan(initialControl.top));
  });

  testWidgets('map stays interactive outside the pill and sheet', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(harness(onMapTap: () => taps++));
    await tester.tapAt(const Offset(30, 100));
    expect(taps, 1);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(30, 100));
    expect(taps, 2);
    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(30, 450));
    expect(taps, 3);
  });

  testWidgets('small screens, safe areas, large text and reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        harness(
          selection: dark ? 'bus:1' : 'stop:1',
          dark: dark,
          reducedMotion: true,
          textScale: 2,
        ),
      );
      final pill = tester.getRect(find.byType(FilledButton));
      expect(pill.bottom, lessThanOrEqualTo(640 - 24));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
