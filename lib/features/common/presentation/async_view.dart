import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/features/common/presentation/failure_text.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Pinta un [AsyncValue] con estados de carga y error consistentes.
///
/// Si hay datos previos, se siguen mostrando mientras se recarga o tras un
/// error (los datos antiguos se marcan en la propia pantalla).
class AsyncView<T> extends StatelessWidget {
  const new({
    required this.value,
    required this.builder,
    super.key,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (value.hasValue) return builder(value.requireValue);
    if (value.hasError) {
      final error = value.error;
      final failure = error is Failure
          ? error
          : Failure.unexpected('async-view', error);
      return NxMessageView(
        icon: Icons.error_outline,
        title: failureMessage(l10n, failure),
        actionLabel: onRetry == null ? null : l10n.commonRetry,
        onAction: onRetry,
      );
    }
    return NxLoadingView(label: l10n.commonLoading);
  }
}
