import 'package:flutter/material.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/navigation/novel_workspace_section.dart';
import '../../../app/theme/ibuki_motion.dart';

class NovelSectionTabs extends StatelessWidget {
  const NovelSectionTabs({
    required this.selected,
    required this.onSelected,
    super.key,
  });
  final NovelWorkspaceSection selected;
  final ValueChanged<NovelWorkspaceSection> onSelected;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final section in NovelWorkspaceSection.values)
        Flexible(
          child: Semantics(
            selected: section == selected,
            button: true,
            excludeSemantics: true,
            onTap: () => onSelected(section),
            label: context.tr('小说{section}', {
              'section': context.tr(section.label),
            }),
            child: TextButton(
              key: Key('novel-tab-${section.name}'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                foregroundColor: section == selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              onPressed: () => onSelected(section),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: IbukiMotion.durationOf(
                      context,
                      IbukiMotion.feedback,
                    ),
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      fontSize: 17,
                      fontWeight: section == selected
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: section == selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    child: Text(context.tr(section.label), maxLines: 1),
                  ),
                  const SizedBox(height: 3),
                  AnimatedContainer(
                    duration: IbukiMotion.durationOf(
                      context,
                      IbukiMotion.feedback,
                    ),
                    width: section == selected ? 18 : 0,
                    height: 2,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
