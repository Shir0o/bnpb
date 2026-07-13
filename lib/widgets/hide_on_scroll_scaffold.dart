import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A [Scaffold] wrapper that hides its [AppBar] when the user scrolls down
/// and reveals it again when the user scrolls up.
///
/// It wraps the body in a [NotificationListener] to intercept scroll events
/// and uses an [AnimationController] to smoothly slide the AppBar out of view.
class HideOnScrollScaffold extends StatefulWidget {
  /// Creates a scaffold that hides its app bar on scroll.
  const HideOnScrollScaffold({
    super.key,
    required this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.bottomSheet,
    this.resizeToAvoidBottomInset,
  });

  /// The [AppBar] to display at the top. It will be hidden/shown based on
  /// scroll direction.
  final PreferredSizeWidget appBar;

  /// The primary content of the scaffold.
  final Widget body;

  /// An optional floating action button passed through to the inner [Scaffold].
  final Widget? floatingActionButton;

  /// The location of the floating action button.
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  /// The background color of the [Scaffold].
  final Color? backgroundColor;

  /// A persistent bottom sheet displayed at the bottom of the scaffold.
  final Widget? bottomSheet;

  /// Whether the body should resize when the keyboard appears.
  final bool? resizeToAvoidBottomInset;

  @override
  State<HideOnScrollScaffold> createState() => _HideOnScrollScaffoldState();
}

class _HideOnScrollScaffoldState extends State<HideOnScrollScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // 1.0 = fully visible, 0.0 = fully hidden.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      final direction = notification.direction;
      if (direction == ScrollDirection.reverse) {
        // Scrolling down → hide.
        if (_controller.value != 0.0) {
          _controller.reverse();
        }
      } else if (direction == ScrollDirection.forward) {
        // Scrolling up → show.
        if (_controller.value != 1.0) {
          _controller.forward();
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.backgroundColor,
      floatingActionButton: widget.floatingActionButton,
      floatingActionButtonLocation: widget.floatingActionButtonLocation,
      bottomSheet: widget.bottomSheet,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      body: Column(
        children: [
          // Animated AppBar: SizeTransition clips and resizes it.
          SizeTransition(
            sizeFactor: _animation,
            alignment: Alignment.topCenter,
            child: widget.appBar,
          ),
          // Body fills the remaining space.
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: widget.body,
            ),
          ),
        ],
      ),
    );
  }
}
