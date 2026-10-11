import 'resolver_models.dart';

/// Access requirements are separate from a provider's protocol implementation.
enum MusicSourceAccess { direct, authorizationRequired, limitedFallback }

class MusicSourceRequestLimits {
  const MusicSourceRequestLimits({
    this.spacing = const Duration(milliseconds: 400),
    this.maxConcurrent = 2,
    this.maxBackgroundConcurrent = 1,
    this.cooldown = const Duration(seconds: 15),
  }) : assert(maxConcurrent > 0),
       assert(maxBackgroundConcurrent > 0);
  final Duration spacing;
  final int maxConcurrent;
  final int maxBackgroundConcurrent;
  final Duration cooldown;
}

class MusicSourcePolicy {
  const MusicSourcePolicy({
    required this.source,
    required this.access,
    required this.priority,
    this.requestHosts = const [],
    this.requestLimits,
    this.maxBackgroundOperations = 2,
  });
  final MusicDataSource source;
  final MusicSourceAccess access;
  final int priority;
  final List<String> requestHosts;
  // Null deliberately preserves the provider's existing request behavior.
  final MusicSourceRequestLimits? requestLimits;
  final int maxBackgroundOperations;

  bool get fallbackOnly => access == MusicSourceAccess.limitedFallback;
  bool get supportsManualSelection => !fallbackOnly;
  bool canRequest({required bool authorized}) =>
      access != MusicSourceAccess.authorizationRequired || authorized;
}

class MusicSourceCatalog {
  const MusicSourceCatalog(this.policies);
  final List<MusicSourcePolicy> policies;

  static const standard = MusicSourceCatalog([
    MusicSourcePolicy(
      source: MusicDataSource.flac,
      access: MusicSourceAccess.direct,
      priority: 10,
      requestHosts: ['flac.music.hi.cn'],
    ),
    MusicSourcePolicy(
      source: MusicDataSource.buguyy,
      access: MusicSourceAccess.direct,
      priority: 20,
      requestHosts: ['buguyy.top'],
      requestLimits: MusicSourceRequestLimits(),
      maxBackgroundOperations: 1,
    ),
    MusicSourcePolicy(
      source: MusicDataSource.twentyFourBit,
      access: MusicSourceAccess.limitedFallback,
      priority: 30,
      requestHosts: ['24bit.net', 'www.24bit.net'],
      requestLimits: MusicSourceRequestLimits(spacing: Duration(seconds: 1)),
    ),
  ]);

  MusicSourcePolicy? policyFor(MusicDataSource source) =>
      policies.where((p) => p.source == source).firstOrNull;
  MusicSourcePolicy? policyForHost(String host) =>
      policies.where((p) => p.requestHosts.contains(host)).firstOrNull;

  List<MusicSourcePolicy> get orderedPolicies {
    final ordered = [...policies];
    ordered.sort((a, b) {
      if (a.fallbackOnly != b.fallbackOnly) return a.fallbackOnly ? 1 : -1;
      return a.priority.compareTo(b.priority);
    });
    return ordered;
  }

  List<MusicDataSource> autoSources({
    bool Function(MusicDataSource)? isAuthorized,
  }) => [
    for (final policy in orderedPolicies)
      if (policy.canRequest(
        authorized: isAuthorized?.call(policy.source) == true,
      ))
        policy.source,
  ];

  List<MusicDataSource> manualSources({
    bool Function(MusicDataSource)? isAuthorized,
  }) => [
    for (final source in autoSources(isAuthorized: isAuthorized))
      if (policyFor(source)!.supportsManualSelection) source,
  ];

  List<MusicDataSource> sourcesBefore(MusicDataSource source) =>
      policyFor(source) == null
      ? const []
      : orderedPolicies
            .map((p) => p.source)
            .takeWhile((s) => s != source)
            .toList();
}

abstract interface class MusicSourcePolicyResolver {
  MusicSourceCatalog get sourceCatalog;
  bool isSourceAuthorized(MusicDataSource source);
}

enum MusicSourceAvailability {
  unknown,
  checking,
  available,
  quotaExhausted,
  unavailable,
  authorizationRequired,
}

abstract interface class SourceAvailabilityResolver {
  MusicSourceAvailability sourceAvailability(MusicDataSource source);
  int get sourceAvailabilityRevision;
  Future<void> recheckSourceAvailability({bool networkChanged = false});
}
