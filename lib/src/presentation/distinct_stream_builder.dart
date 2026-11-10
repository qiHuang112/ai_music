import 'dart:async';

import 'package:flutter/widgets.dart';

/// Builds from the latest value of [stream], rebuilding only when it differs
/// from the one shown.
///
/// [StreamBuilder] rebuilds on every event, and the audio handler's subjects
/// replay their current value to each new listener: one extra build of
/// whatever it wraps right after it appears. Around a playlist's rows that
/// was the whole list built again in the middle of the push.
class DistinctStreamBuilder<T> extends StatefulWidget {
  const DistinctStreamBuilder({
    super.key,
    required this.stream,
    required this.initialData,
    required this.builder,
  });

  final Stream<T> stream;
  final T initialData;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<DistinctStreamBuilder<T>> createState() =>
      _DistinctStreamBuilderState<T>();
}

class _DistinctStreamBuilderState<T> extends State<DistinctStreamBuilder<T>> {
  late T _value = widget.initialData;
  StreamSubscription<T>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant DistinctStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stream, widget.stream)) {
      unawaited(_subscription?.cancel());
      _listen();
    }
  }

  void _listen() {
    _subscription = widget.stream.listen((value) {
      if (mounted && value != _value) setState(() => _value = value);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
