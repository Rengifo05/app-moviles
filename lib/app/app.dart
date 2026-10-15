import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

const supportedAppLocales = [Locale('es'), Locale('en')];

/// Raíz de la interfaz.
class NexoApp extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    return MaterialApp(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      theme: NxTheme.light(),
      darkTheme: NxTheme.dark(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // El español es el idioma principal y el de respaldo para cualquier
      // idioma no soportado (el primero de la lista).
      supportedLocales: supportedAppLocales,
      home: const _StartPlaceholder(),
    );
  }
}

// Pantalla provisional hasta que exista el router (incremento 2).
class _StartPlaceholder extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              config.appName,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(l10n.appTagline),
          ],
        ),
      ),
    );
  }
}
