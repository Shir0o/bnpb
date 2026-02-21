import 'package:flutter/material.dart';

/// A custom ExpansionTile that allows for smoother, configurable animations.
class SmoothExpansionTile extends StatefulWidget {
  const SmoothExpansionTile({
    super.key,
    required this.title,
    this.children = const <Widget>[],
    this.itemCount,
    this.itemBuilder,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.duration = const Duration(milliseconds: 400),
    this.reverseDuration,
    this.curve = Curves.fastOutSlowIn,
    this.tilePadding,
    this.childrenPadding,
  });

  final Widget title;
  final List<Widget> children;
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final Duration duration;
  final Duration? reverseDuration;
  final Curve curve;
  final EdgeInsetsGeometry? tilePadding;
  final EdgeInsetsGeometry? childrenPadding;

  @override
  State<SmoothExpansionTile> createState() => _SmoothExpansionTileState();
}

class _SmoothExpansionTileState extends State<SmoothExpansionTile>
    with SingleTickerProviderStateMixin {
  static final Animatable<double> _easeInTween =
      CurveTween(curve: Curves.easeIn);
  static final Animatable<double> _halfTween =
      Tween<double>(begin: 0.0, end: 0.5);

  late AnimationController _controller;
  late Animation<double> _iconTurns;
  late Animation<double> _heightFactor;

  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      reverseDuration: widget.reverseDuration,
      vsync: this,
    );
    _heightFactor = _controller.drive(CurveTween(curve: widget.curve));
    _iconTurns = _controller.drive(_halfTween.chain(_easeInTween));

    _isExpanded = PageStorage.of(context).readState(context) as bool? ??
        widget.initiallyExpanded;
    if (_isExpanded) {
      _controller.value = 1.0;
    }
    _controller.addStatusListener(_handleStatusChange);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatusChange);
    _controller.dispose();
    super.dispose();
  }

  void _handleStatusChange(AnimationStatus status) {
    setState(() {
      // Rebuild to update 'closed' state when animation finishes.
    });
  }

  void _handleTap() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
      PageStorage.of(context).writeState(context, _isExpanded);
    });
    widget.onExpansionChanged?.call(_isExpanded);
  }

  @override
  void didUpdateWidget(SmoothExpansionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyExpanded != oldWidget.initiallyExpanded &&
        widget.initiallyExpanded != _isExpanded) {
      setState(() {
        _isExpanded = widget.initiallyExpanded;
        if (_isExpanded) {
          _controller.forward();
        } else {
          _controller.reverse();
        }
        PageStorage.of(context).writeState(context, _isExpanded);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool closed = !_isExpanded && _controller.isDismissed;
    Widget? result;

    if (!closed) {
      List<Widget> children;
      if (widget.children.isNotEmpty) {
        children = widget.children;
      } else if (widget.itemCount != null && widget.itemBuilder != null) {
        children = List.generate(
          widget.itemCount!,
          (index) => widget.itemBuilder!(context, index),
        );
      } else {
        children = const <Widget>[];
      }

      // Optimization: Wrap the children in a RepaintBoundary.
      // This isolates the list of children (which can be complex, e.g., PeopleCard)
      // from the expansion animation. The animation only needs to clip/align
      // the cached layer, preventing expensive repaints of the children on every frame.
      result = RepaintBoundary(
        child: Padding(
          padding: widget.childrenPadding ?? EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ListTile(
          onTap: _handleTap,
          contentPadding: widget.tilePadding,
          title: widget.title,
          trailing: RotationTransition(
            turns: _iconTurns,
            child: const Icon(Icons.expand_more),
          ),
        ),
        AnimatedBuilder(
          animation: _controller.view,
          builder: (context, child) {
            return ClipRect(
              child: Align(
                heightFactor: _heightFactor.value,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          child: result,
        ),
      ],
    );
  }
}
