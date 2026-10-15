import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Estructura de las pantallas de configuración de familia (crear, unirse,
/// bienvenida): título grande, explicación y contenido desplazable.
class FamilyFormScaffold extends StatelessWidget {
  const new({
    required this.title,
    required this.subtitle,
    required this.children,
    super.key,
    this.appBarTitle,
    this.actions,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final String? appBarTitle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: appBarTitle == null ? null : Text(appBarTitle!),
      actions: actions,
    ),
    body: SafeArea(
      top: false,
      child: NxPageBody(
        children: [
          const SizedBox(height: NxSpace.md),
          Semantics(
            header: true,
            child: Text(title, style: context.text.headlineMedium),
          ),
          const SizedBox(height: NxSpace.xs),
          Text(
            subtitle,
            style: context.text.bodyLarge?.copyWith(color: context.nx.inkMuted),
          ),
          const SizedBox(height: NxSpace.xl),
          ...children,
        ],
      ),
    ),
  );
}

/// Línea de texto con un ícono decorativo a la izquierda: explicaciones y
/// avisos dentro del contenido, sin tarjetas.
class FamilyNote extends StatelessWidget {
  const new({required this.icon, required this.text, super.key, this.style});

  final IconData icon;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    final textStyle = style ?? context.text.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NxSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Alinea el ícono con la primera línea del texto.
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: ExcludeSemantics(
              child: Icon(
                icon,
                size: nxScaledIcon(context, NxSize.iconMd - 4),
                color: c.inkMuted,
              ),
            ),
          ),
          const SizedBox(width: NxSpace.sm),
          Expanded(child: Text(text, style: textStyle)),
        ],
      ),
    );
  }
}

/// Pide confirmar una acción con consecuencias. Explica cada consecuencia
/// en su propia línea. Devuelve `true` solo si se confirma.
Future<bool> showFamilyConfirmDialog(
  BuildContext context, {
  required String title,
  required List<(IconData, String)> consequences,
  required String confirmLabel,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (icon, text) in consequences)
              FamilyNote(icon: icon, text: text),
          ],
        ),
      ),
      actions: [
        NxButton(
          label: l10n.commonCancel,
          variant: NxButtonVariant.tertiary,
          expand: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NxButton(
          label: confirmLabel,
          variant: NxButtonVariant.destructive,
          expand: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Vuelve a construir [builder] cada [period], para que los textos que
/// dependen de la hora ("hace 5 min", "Vence en 3 h") no se queden
/// desactualizados mientras la pantalla sigue abierta.
class PeriodicRebuild extends StatefulWidget {
  const new({
    required this.builder,
    super.key,
    this.period = const Duration(seconds: 30),
  });

  final WidgetBuilder builder;
  final Duration period;

  @override
  State<PeriodicRebuild> createState() => _PeriodicRebuildState();
}

class _PeriodicRebuildState extends State<PeriodicRebuild> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.period, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Pasa a mayúsculas solo las letras ASCII del código mientras se escribe.
///
/// `toUpperCase` de Unicode cambia la longitud de algunos textos ('ß' →
/// 'SS') y descuadraría el cursor; las letras ajenas al alfabeto del código
/// las rechaza después `FamilyRules.normalizeCode`.
class InvitationCodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = String.fromCharCodes(
      newValue.text.codeUnits.map(
        (unit) => unit >= 0x61 && unit <= 0x7A ? unit - 0x20 : unit,
      ),
    );
    return newValue.copyWith(text: upper);
  }
}

/// Tras el próximo fotograma, desplaza la página para que el widget de
/// [key] quede a la vista: un error o un resultado que aparece lejos del
/// botón pulsado (frecuente con texto grande) no debe quedar oculto.
///
/// Con [alignEnd], si el widget queda por debajo, se alinea su borde
/// inferior con el de la vista; si no, se alinea su borde superior cuando
/// queda por encima.
void revealAfterFrame(GlobalKey key, {bool alignEnd = false}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = key.currentContext;
    if (context == null || !context.mounted) return;
    Scrollable.ensureVisible(
      context,
      duration: NxMotion.of(context, NxMotion.medium),
      curve: NxMotion.standard,
      alignmentPolicy: alignEnd
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  });
}
