import 'package:flutter/material.dart';

import 'app_skeleton.dart';
import 'empty_state.dart';

/// Renders a Firestore stream snapshot with four visually distinct states:
/// loading (skeleton), error (with retry), empty (with CTA) and content.
class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.snapshot,
    required this.builder,
    this.isEmpty,
    this.loading,
    this.errorTitle = 'Nao foi possivel carregar',
    this.errorMessage = 'Verifique sua conexao e tente novamente.',
    this.onRetry,
    this.emptyTitle = 'Nada por aqui ainda',
    this.emptyMessage = 'Ainda nao ha conteudo para mostrar.',
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyAction,
    this.emptyBuilder,
  });

  final AsyncSnapshot<T> snapshot;
  final Widget Function(BuildContext context, T data) builder;
  final bool Function(T data)? isEmpty;
  final Widget? loading;
  final String errorTitle;
  final String errorMessage;
  final VoidCallback? onRetry;
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final Widget? emptyAction;

  /// When provided, replaces the default [EmptyState] for the empty case
  /// (e.g. a banner that renders nothing).
  final Widget Function(BuildContext context)? emptyBuilder;

  static bool _defaultIsEmpty<T>(T data) {
    return data == null || (data is Iterable && data.isEmpty);
  }

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return loading ?? const AppSkeletonList(count: 3);
    }

    if (snapshot.hasError) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: errorTitle,
        message: errorMessage,
        action: onRetry == null
            ? null
            : TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Tentar novamente'),
              ),
      );
    }

    final data = snapshot.data;
    if (data == null || (isEmpty ?? _defaultIsEmpty)(data)) {
      return emptyBuilder?.call(context) ??
          EmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            message: emptyMessage,
            action: emptyAction,
          );
    }

    return builder(context, data);
  }
}
