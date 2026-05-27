import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

/// Multi-URL chip input — type/paste a URL, press + or Enter, it becomes
/// a removable chip. Stores all URLs as a newline-separated string.
class WikiUrlInput extends StatelessWidget {
  final TextEditingController controller;
  final List<String> urls;
  final VoidCallback onAdd;
  final void Function(String) onRemove;

  const WikiUrlInput({
    super.key,
    required this.controller,
    required this.urls,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onAdd(),
              decoration: const InputDecoration(
                hintText: 'Paste Wiki / Confluence / Notion URL',
                prefixIcon: Icon(Icons.link_rounded, size: 18),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const Gap(8),
          FilledButton.tonal(
            onPressed: onAdd,
            style: FilledButton.styleFrom(
              minimumSize: const Size(56, 48),
              padding: EdgeInsets.zero,
            ),
            child: const Icon(Icons.add_rounded, size: 20),
          ),
        ]),
        if (urls.isNotEmpty) ...[
          const Gap(8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: urls.map((url) {
              final label =
                  url.length > 40 ? '${url.substring(0, 40)}…' : url;
              return Chip(
                avatar: Icon(Icons.link_rounded,
                    size: 14, color: cs.primary),
                label:
                    Text(label, style: const TextStyle(fontSize: 11)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => onRemove(url),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
