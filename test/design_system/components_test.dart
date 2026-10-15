import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/design_system/components/nx_avatar.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_hold_button.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme ?? NxTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

Future<void> expectAccessible(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  group('NxButton', () {
    testWidgets('llama a onPressed y cumple las guías de accesibilidad', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pump(tester, NxButton(label: 'Continuar', onPressed: () => taps++));
      await tester.tap(find.text('Continuar'));
      expect(taps, 1);
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('en carga se desactiva pero conserva su etiqueta accesible', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pump(
        tester,
        NxButton(label: 'Enviar', onPressed: () => taps++, loading: true),
      );
      await tester.tap(find.byType(NxButton));
      expect(taps, 0);
      expect(find.bySemanticsLabel('Enviar'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('todas las variantes cumplen el contraste en modo oscuro', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final variant in NxButtonVariant.values)
              NxButton(label: variant.name, onPressed: () {}, variant: variant),
          ],
        ),
        theme: NxTheme.dark(),
      );
      await expectAccessible(tester);
      handle.dispose();
    });
  });

  group('NxStatusPill', () {
    testWidgets('expone su texto como etiqueta accesible única', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        const NxStatusPill(
          label: 'Actualizada hace 2 min',
          icon: Icons.schedule,
          tone: NxTone.positive,
        ),
      );
      expect(find.bySemanticsLabel('Actualizada hace 2 min'), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  group('NxHoldButton', () {
    testWidgets('un toque corto no activa y muestra la instrucción', (
      tester,
    ) async {
      var confirmed = 0;
      await pump(
        tester,
        NxHoldButton(
          label: 'SOS',
          hint: 'Mantén pulsado 2 segundos',
          onConfirmed: () => confirmed++,
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(NxHoldButton)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(confirmed, 0);
    });

    testWidgets('mantener pulsado el tiempo completo activa una sola vez', (
      tester,
    ) async {
      var confirmed = 0;
      await pump(
        tester,
        NxHoldButton(
          label: 'SOS',
          hint: 'Mantén pulsado 2 segundos',
          onConfirmed: () => confirmed++,
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(NxHoldButton)),
      );
      // El reconocedor confirma el toque tras ~100 ms; la animación avanza
      // fotograma a fotograma.
      await tester.pump(const Duration(milliseconds: 150));
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(confirmed, 0, reason: '1,8 s de 2 s: aún no se activa');
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(confirmed, 1);
      // Seguir pulsando o soltar después no vuelve a activar.
      await tester.pump(const Duration(seconds: 3));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(confirmed, 1);
    });

    testWidgets('los lectores de pantalla lo activan con la acción larga', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var confirmed = 0;
      await pump(
        tester,
        NxHoldButton(
          label: 'SOS',
          hint: 'Mantén pulsado 2 segundos',
          onConfirmed: () => confirmed++,
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('SOS'));
      expect(node.hint, 'Mantén pulsado 2 segundos');
      tester.semantics.longPress(find.semantics.byLabel('SOS'));
      expect(confirmed, 1);
      handle.dispose();
    });
  });

  group('NxBanner y NxMessageView', () {
    testWidgets('el banner ofrece una acción concreta', (tester) async {
      var retries = 0;
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        NxBanner(
          icon: Icons.cloud_off,
          message: 'Sin conexión. Mostramos los últimos datos guardados.',
          actionLabel: 'Reintentar',
          onAction: () => retries++,
        ),
      );
      await tester.tap(find.text('Reintentar'));
      expect(retries, 1);
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('el estado vacío explica y ofrece el siguiente paso', (
      tester,
    ) async {
      var created = 0;
      await pump(
        tester,
        NxMessageView(
          icon: Icons.group_outlined,
          title: 'Aún no hay integrantes',
          body: 'Invita a tu familia con un código de un solo uso.',
          actionLabel: 'Invitar',
          onAction: () => created++,
        ),
      );
      await tester.tap(find.text('Invitar'));
      expect(created, 1);
    });

    testWidgets('admite texto al 200 % sin desbordarse', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 360,
          child: NxBanner(
            icon: Icons.location_off,
            message: 'No compartes tu ubicación con esta familia.',
            actionLabel: 'Configurar',
          ),
        ),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('NxAvatar', () {
    test('calcula iniciales sin datos adicionales', () {
      expect(NxAvatar.initialsOf('Ana María'), 'AM');
      expect(NxAvatar.initialsOf('  luis '), 'L');
      expect(NxAvatar.initialsOf(''), '?');
      expect(NxAvatar.initialsOf('Ángela Pérez Gómez'), 'ÁP');
    });
  });
}
