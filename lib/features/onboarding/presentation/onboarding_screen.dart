import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Bienvenida: explica qué hace la app, la privacidad, los permisos y sus
/// límites. El último paso (no sustituye a emergencias) no se puede saltar.
class OnboardingScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;
  bool _saving = false;

  static const List<IconData> _icons = [
    Icons.diversity_1_outlined,
    Icons.lock_person_outlined,
    Icons.notifications_paused_outlined,
    Icons.health_and_safety_outlined,
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _next(int total) async {
    if (_index < total - 1) {
      await _pages.nextPage(
        duration: NxMotion.of(context, NxMotion.medium),
        curve: NxMotion.standard,
      );
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(preferencesRepositoryProvider)
        .update((p) => p.copyWith(onboardingCompleted: true));
    // La sesión cambia y el enrutador lleva a iniciar sesión.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final number = ref.watch(appConfigProvider).emergencyNumber;
    final steps = [
      (l10n.onboarding1Title, l10n.onboarding1Body),
      (l10n.onboarding2Title, l10n.onboarding2Body),
      (l10n.onboarding3Title, l10n.onboarding3Body),
      (l10n.onboarding4Title, l10n.onboarding4Body(number)),
    ];
    final isLast = _index == steps.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _Step(
                  icon: _icons[i],
                  title: steps[i].$1,
                  body: steps[i].$2,
                  stepLabel: l10n.onboardingStep(i + 1, steps.length),
                ),
              ),
            ),
            _Dots(count: steps.length, index: _index),
            Padding(
              padding: const EdgeInsets.all(NxSpace.gutter),
              child: NxButton(
                label: isLast ? l10n.onboardingStart : l10n.onboardingNext,
                loading: _saving,
                onPressed: () => _next(steps.length),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.body,
    required this.stepLabel,
  });

  final IconData icon;
  final String title;
  final String body;
  final String stepLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        NxSpace.gutter,
        NxSpace.xxl,
        NxSpace.gutter,
        NxSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: c.secondaryContainer,
              borderRadius: NxRadius.lgAll,
            ),
            child: Icon(icon, size: 36, color: c.onSecondaryContainer),
          ),
          const SizedBox(height: NxSpace.xl),
          Text(
            stepLabel,
            style: context.text.labelLarge?.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: NxSpace.xs),
          Semantics(
            header: true,
            child: Text(title, style: context.text.headlineMedium),
          ),
          const SizedBox(height: NxSpace.md),
          Text(body, style: context.text.bodyLarge?.copyWith(height: 1.45)),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const new({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: NxMotion.of(context, NxMotion.fast),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == index ? c.primary : c.outline,
                borderRadius: NxRadius.pillAll,
              ),
            ),
        ],
      ),
    );
  }
}
