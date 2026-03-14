import 'package:flutter/material.dart';
import '../services/chat_service.dart';

class ModelSelector extends StatelessWidget {
  final String currentModel;
  final List<ModelInfo> models;
  final ValueChanged<String> onModelChanged;

  const ModelSelector({
    super.key,
    required this.currentModel,
    required this.models,
    required this.onModelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return PopupMenuButton<String>(
      onSelected: onModelChanged,
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.colorScheme.surface,
      elevation: 8,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 12,
          vertical: isMobile ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMobile)
              Icon(
                Icons.smart_toy_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            if (!isMobile) const SizedBox(width: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isMobile ? 100 : 140),
              child: Text(
                currentModel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: isMobile ? 11 : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: isMobile ? 16 : 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
      itemBuilder: (context) {
        final grouped = <String, List<ModelInfo>>{};
        for (final model in models) {
          grouped.putIfAbsent(model.provider, () => []).add(model);
        }

        final items = <PopupMenuEntry<String>>[];
        grouped.forEach((provider, providerModels) {
          items.add(PopupMenuItem<String>(
            enabled: false,
            height: 32,
            child: Text(
              provider,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ));

          for (final model in providerModels) {
            final isSelected = model.id == currentModel;
            items.add(PopupMenuItem<String>(
              value: model.id,
              child: Row(
                children: [
                  if (isSelected)
                    Icon(Icons.check_rounded,
                        size: 16, color: theme.colorScheme.primary)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      model.id,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ));
          }

          items.add(const PopupMenuDivider(height: 8));
        });

        if (items.isNotEmpty) items.removeLast();
        return items;
      },
    );
  }
}
