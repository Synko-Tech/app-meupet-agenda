import 'package:flutter/material.dart';

import '../app/app_semantic_colors.dart';

/// Brand symbol: a paw inside a rounded primary tile with a small coral
/// calendar badge. Theme-aware and resolution-independent (no bitmap assets).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48, this.borderRadius});

  final double size;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final deep = Color.lerp(scheme.primary, Colors.black, 0.18)!;
    final pawSize = size * 0.5;
    final badgeSize = size * 0.42;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius ?? size * 0.26),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, deep],
              ),
            ),
            child: Icon(Icons.pets, size: pawSize, color: scheme.onPrimary),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppSemanticColors.coral,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: size * 0.045,
                ),
              ),
              child: Icon(
                Icons.calendar_month,
                size: badgeSize * 0.55,
                color: AppSemanticColors.onCoral,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand mark followed by the "MeuPet Agenda" wordmark.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.size = 44,
    this.textStyle,
    this.spacing = 12,
  });

  final double size;
  final TextStyle? textStyle;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: size),
        SizedBox(width: spacing),
        Flexible(
          child: Text(
            'MeuPet Agenda',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                textStyle ??
                TextStyle(
                  fontFamily: 'VarelaRound',
                  fontSize: size * 0.6,
                  height: 1.1,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppSemanticColors.darkText
                      : scheme.onSurface,
                ),
          ),
        ),
      ],
    );
  }
}
