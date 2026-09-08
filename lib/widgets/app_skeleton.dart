import 'package:flutter/material.dart';

import '../app/app_radius.dart';

/// Neutral loading placeholder with an animated shimmer. The animation is
/// disabled when the platform requests reduced motion
/// ([MediaQuery.disableAnimationsOf]) so the skeleton stays static.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = AppRadius.xs,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseColor = scheme.surfaceContainerHighest;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final box = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );

    if (reduceMotion) return box;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2.0;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            colors: [baseColor, scheme.surface, baseColor],
            stops: const [0.35, 0.5, 0.65],
            begin: Alignment(-1 + 2 * t, 0),
            end: Alignment(-0.5 + 2 * t, 0),
          ).createShader(bounds),
          child: box,
        );
      },
    );
  }
}

/// A short list of card-shaped skeletons for list loading states.
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({super.key, this.count = 3, this.itemHeight = 96});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppSkeleton(height: itemHeight, radius: AppRadius.lg),
          ),
      ],
    );
  }
}
