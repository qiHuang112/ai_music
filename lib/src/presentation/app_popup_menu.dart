import 'package:flutter/material.dart';

/// One transition for every overflow, sort and filter menu in the app.
class MusicPopupMenuButton<T> extends PopupMenuButton<T> {
  const MusicPopupMenuButton({
    super.key,
    required super.itemBuilder,
    super.initialValue,
    super.onSelected,
    super.tooltip,
    super.enabled,
    super.icon,
    super.child,
  }) : super(
         popUpAnimationStyle: const AnimationStyle(
           duration: Duration(milliseconds: 120),
           curve: Curves.easeOutCubic,
           reverseCurve: Curves.easeOutCubic,
         ),
       );
}
