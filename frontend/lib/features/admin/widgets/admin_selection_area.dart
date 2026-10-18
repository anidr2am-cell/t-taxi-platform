import 'package:flutter/material.dart';

/// Only administrator pages opt into document selection. TextField keeps its
/// own editable selection; nested administrator routes get a fresh region.
class AdminSelectionArea extends StatelessWidget {
  const AdminSelectionArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SelectionArea(child: child);
}

class AdminPageRoute<T> extends MaterialPageRoute<T> {
  AdminPageRoute({required WidgetBuilder builder, super.settings})
    : super(builder: (context) => AdminSelectionArea(child: builder(context)));
}
