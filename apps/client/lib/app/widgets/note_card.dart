import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/utils/date_format.dart';

class NoteCard extends StatefulWidget {
  final String title;
  final String content;
  final DateTime updatedAt;
  final String? folderName;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const NoteCard({
    super.key,
    required this.title,
    required this.content,
    required this.updatedAt,
    this.folderName,
    required this.onTap,
    this.onDelete,
  });
  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 8)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 1, offset: const Offset(0, 1)),
          ],
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title.isEmpty ? '无标题' : widget.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.25)),
                  const SizedBox(height: 6),
                  Text(widget.content.isEmpty ? '空内容' : widget.content,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.45, fontSize: 13.5)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.schedule_rounded, size: 13, color: scheme.outline),
                    const SizedBox(width: 4),
                    Text(relativeTime(widget.updatedAt), style: text.labelSmall?.copyWith(color: scheme.outline, fontSize: 11)),
                    if (widget.folderName != null) ...[
                      const SizedBox(width: 8),
                      Container(width: 1, height: 10, color: scheme.outlineVariant),
                      const SizedBox(width: 8),
                      Icon(Icons.folder_rounded, size: 12, color: scheme.outline),
                      const SizedBox(width: 3),
                      Flexible(child: Text(widget.folderName!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: text.labelSmall?.copyWith(color: scheme.outline, fontSize: 11))),
                    ],
                  ]),
                ])),
                if (widget.onDelete != null)
                  PopupMenuButton<String>(
                    onSelected: (v) { if (v == 'delete') widget.onDelete!.call(); },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('删除'))],
                    icon: Icon(Icons.more_horiz_rounded, size: 20, color: scheme.outline),
                    padding: EdgeInsets.zero,
                  )
                else
                  const SizedBox(width: 8),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class FolderCard extends StatefulWidget {
  final String name;
  final DateTime updatedAt;
  final int version;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  const FolderCard({super.key, required this.name, required this.updatedAt, required this.version, this.onRename, this.onDelete});
  @override
  State<FolderCard> createState() => _FolderCardState();
}

class _FolderCardState extends State<FolderCard> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 140),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
          boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Material(color: Colors.transparent, child: InkWell(
          onTap: widget.onRename,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.folder_rounded, color: scheme.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('v${widget.version} · ${formatDateTime(widget.updatedAt)}',
                  style: text.labelSmall?.copyWith(color: scheme.outline, fontSize: 11)),
              ])),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'rename') widget.onRename?.call();
                  if (v == 'delete') widget.onDelete?.call();
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('重命名')), PopupMenuItem(value: 'delete', child: Text('删除'))],
                icon: Icon(Icons.more_horiz_rounded, size: 20, color: scheme.outline),
                padding: EdgeInsets.zero,
              ),
            ]),
          ),
        )),
      ),
    );
  }
}
