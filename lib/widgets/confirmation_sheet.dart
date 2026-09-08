import 'package:flutter/material.dart';

import 'app_button.dart';

/// A label/value pair shown inside a [ConfirmationSheet].
class ConfirmationItem {
  const ConfirmationItem({required this.label, required this.value});

  final String label;
  final String value;
}

/// Bottom-sheet confirmation summary. Runs [onConfirm] with an inline busy
/// state; pops with `true` on success, keeps the sheet open with an inline
/// error message on failure.
Future<bool?> showConfirmationSheet({
  required BuildContext context,
  required String title,
  required List<ConfirmationItem> items,
  required String confirmLabel,
  required Future<void> Function() onConfirm,
  String cancelLabel = 'Cancelar',
  bool destructive = false,
  IconData confirmIcon = Icons.check,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ConfirmationSheet(
      title: title,
      items: items,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      confirmIcon: confirmIcon,
      onConfirm: onConfirm,
    ),
  );
}

class _ConfirmationSheet extends StatefulWidget {
  const _ConfirmationSheet({
    required this.title,
    required this.items,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    required this.confirmIcon,
    required this.onConfirm,
  });

  final String title;
  final List<ConfirmationItem> items;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData confirmIcon;
  final Future<void> Function() onConfirm;

  @override
  State<_ConfirmationSheet> createState() => _ConfirmationSheetState();
}

class _ConfirmationSheetState extends State<_ConfirmationSheet> {
  bool _isBusy = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _error = 'Nao foi possivel concluir a operacao. Tente novamente.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          for (final item in widget.items) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(item.label, style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    item.value,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          AppButton(
            label: widget.confirmLabel,
            icon: widget.confirmIcon,
            isLoading: _isBusy,
            variant: widget.destructive
                ? AppButtonVariant.destructive
                : AppButtonVariant.primary,
            onPressed: _isBusy ? null : _confirm,
          ),
          const SizedBox(height: 8),
          AppButton(
            label: widget.cancelLabel,
            variant: AppButtonVariant.tonal,
            onPressed: _isBusy ? null : () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
