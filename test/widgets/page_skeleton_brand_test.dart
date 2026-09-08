import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_breakpoints.dart';
import 'package:meupet_agenda_app/app/app_spacing.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/widgets/app_page.dart';
import 'package:meupet_agenda_app/widgets/app_skeleton.dart';
import 'package:meupet_agenda_app/widgets/brand_mark.dart';

void main() {
  group('AppPage', () {
    testWidgets('renders the child inside a constrained box', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AppPage(child: Text('conteudo'))),
        ),
      );

      expect(find.text('conteudo'), findsOneWidget);
      final constrained = tester.widget<ConstrainedBox>(
        find.ancestor(
          of: find.text('conteudo'),
          matching: find.byType(ConstrainedBox),
        ),
      );
      expect(constrained.constraints.maxWidth, AppBreakpoints.contentMaxWidth);
    });

    testWidgets('applies tablet gutters on wide screens', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AppPage(child: Text('conteudo'))),
        ),
      );

      final listView = tester.widget<ListView>(find.byType(ListView));
      final padding = listView.padding as EdgeInsets;
      expect(padding.left, AppSpacing.pagePaddingTablet);
    });

    testWidgets('applies compact gutters on narrow screens', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AppPage(child: Text('conteudo'))),
        ),
      );

      final listView = tester.widget<ListView>(find.byType(ListView));
      final padding = listView.padding as EdgeInsets;
      expect(padding.left, AppSpacing.pagePadding);
    });

    testWidgets('allows overriding the padding', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: AppPage(padding: EdgeInsets.all(7), child: Text('conteudo')),
          ),
        ),
      );

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.padding, const EdgeInsets.all(7));
    });
  });

  group('AppSkeleton', () {
    testWidgets('renders a box with the requested size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AppSkeleton(width: 100, height: 20)),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.constraints, isNotNull);
      expect(container.constraints!.maxWidth, 100);
      expect(container.constraints!.maxHeight, 20);
    });

    testWidgets('renders a static box when reduced motion is enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: AppSkeleton(height: 20),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byType(AppSkeleton), findsOneWidget);
    });
  });

  group('AppSkeletonList', () {
    testWidgets('renders the requested number of skeletons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AppSkeletonList(count: 4, itemHeight: 80)),
        ),
      );
      await tester.pump();

      expect(find.byType(AppSkeleton), findsNWidgets(4));
    });
  });

  group('BrandMark', () {
    testWidgets('renders the paw and calendar icons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: BrandMark()),
        ),
      );

      expect(find.byIcon(Icons.pets), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month), findsOneWidget);
    });

    testWidgets('honors a custom size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: BrandMark(size: 80)),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(
        find.ancestor(
          of: find.byIcon(Icons.pets),
          matching: find.byType(SizedBox),
        ),
      );
      expect(sizedBox.width, 80);
      expect(sizedBox.height, 80);
    });
  });
}
