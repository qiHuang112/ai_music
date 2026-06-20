import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/library/presentation/library_screen.dart';
import '../../features/player/presentation/player_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LibraryScreen(),
        routes: [
          GoRoute(
            path: 'player',
            builder: (context, state) => const PlayerScreen(),
          ),
        ],
      ),
    ],
  );
});
