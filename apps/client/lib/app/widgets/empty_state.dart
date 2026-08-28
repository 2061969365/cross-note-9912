import 'package:flutter/material.dart';
import '../theme.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, size: 32, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: 16),
        Text(title, style: text.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(subtitle, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 18),
          FilledButton.icon(onPressed: onAction, icon: Icon(actionIcon ?? Icons.add_rounded, size: 18), label: Text(actionLabel!)),
        ],
      ]),
    ));
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.7);
    Widget bar(double w, double h) => Container(width: w, height: h,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).cardTheme.color, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        bar(120, 14),
        const SizedBox(height: 10),
        bar(double.infinity, 10),
        const SizedBox(height: 6),
        bar(200, 10),
        const SizedBox(height: 12),
        Row(children: [bar(72, 10), const SizedBox(width: 10), bar(60, 10)]),
      ]),
    );
  }
}

class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 5});
  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(12),
    itemCount: count,
    separatorBuilder: (_, __) => const SizedBox(height: 10),
    itemBuilder: (_, __) => const SkeletonCard(),
  );
}

class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const AppSectionHeader({super.key, required this.title, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(children: [
      Text(title, style: text.titleMedium),
      const Spacer(),
      if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
    ]);
  }
}
