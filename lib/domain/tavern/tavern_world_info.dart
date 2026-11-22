import 'dart:convert';
import 'package:crypto/crypto.dart';

String tavernDigest(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

typedef TavernLoreIdentity = (String bookId, String entryId);

class TavernLoreTimer {
  const TavernLoreTimer({
    required this.bookId,
    required this.entryId,
    required this.activatedAt,
    required this.definitionFingerprint,
    required this.stickyUntil,
    required this.cooldownUntil,
    required this.delayMessages,
  });
  final String bookId, entryId, definitionFingerprint;
  final int activatedAt, stickyUntil, cooldownUntil, delayMessages;
  TavernLoreIdentity get identity => (bookId, entryId);
  Map<String, Object?> toJson() => {
    'book': bookId,
    'entry': entryId,
    'activatedAt': activatedAt,
    'definition': definitionFingerprint,
    'stickyUntil': stickyUntil,
    'cooldownUntil': cooldownUntil,
    'delay': delayMessages,
  };
  factory TavernLoreTimer.fromJson(Map<String, dynamic> json) {
    final timer = TavernLoreTimer(
      bookId: json['book'] as String,
      entryId: json['entry'] as String,
      activatedAt: json['activatedAt'] as int,
      definitionFingerprint: json['definition'] as String,
      stickyUntil: json['stickyUntil'] as int,
      cooldownUntil: json['cooldownUntil'] as int,
      delayMessages: json['delay'] as int,
    );
    if (timer.bookId.isEmpty ||
        timer.entryId.isEmpty ||
        timer.activatedAt < 0 ||
        timer.stickyUntil < timer.activatedAt ||
        timer.cooldownUntil < timer.stickyUntil ||
        timer.delayMessages < 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(timer.definitionFingerprint)) {
      throw const FormatException('Invalid durable timer.');
    }
    return timer;
  }
}

int _timerOrder(TavernLoreTimer a, TavernLoreTimer b) {
  final book = a.bookId.compareTo(b.bookId);
  return book == 0 ? a.entryId.compareTo(b.entryId) : book;
}

class TavernWorldInfoData {
  const TavernWorldInfoData({
    this.messageCount = 0,
    this.historyMarker = '',
    this.timers = const [],
  });
  final int messageCount;
  final String historyMarker;
  final List<TavernLoreTimer> timers;
  Map<String, Object?> toJson() => {
    'messageCount': messageCount,
    'historyMarker': historyMarker,
    'timers': ([...timers]..sort(_timerOrder)).map((t) => t.toJson()).toList(),
  };
  String get fingerprint => tavernDigest(toJson());
  factory TavernWorldInfoData.fromJson(Map<String, dynamic> json) {
    final result = TavernWorldInfoData(
      messageCount: json['messageCount'] as int,
      historyMarker: json['historyMarker'] as String,
      timers: List.unmodifiable(
        (json['timers'] as List).map(
          (j) => TavernLoreTimer.fromJson(Map<String, dynamic>.from(j as Map)),
        ),
      ),
    );
    if (result.messageCount < 0 ||
        (result.historyMarker.isNotEmpty &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(result.historyMarker)) ||
        result.timers.map((t) => t.identity).toSet().length !=
            result.timers.length) {
      throw const FormatException('Invalid durable World Info data.');
    }
    return result;
  }
}

class TavernWorldInfoDelta {
  const TavernWorldInfoDelta({
    required this.messageCount,
    required this.historyMarker,
    this.upserts = const [],
    this.removed = const [],
  });
  final int messageCount;
  final String historyMarker;
  final List<TavernLoreTimer> upserts;
  final List<TavernLoreIdentity> removed;
  factory TavernWorldInfoDelta.between(
    TavernWorldInfoData before,
    TavernWorldInfoData after,
  ) {
    final old = {for (final t in before.timers) t.identity: t};
    final next = {for (final t in after.timers) t.identity: t};
    return TavernWorldInfoDelta(
      messageCount: after.messageCount,
      historyMarker: after.historyMarker,
      upserts: List.unmodifiable(
        after.timers.where(
          (t) =>
              jsonEncode(old[t.identity]?.toJson()) != jsonEncode(t.toJson()),
        ),
      ),
      removed: List.unmodifiable(old.keys.where((id) => !next.containsKey(id))),
    );
  }
  TavernWorldInfoData apply(TavernWorldInfoData before) {
    final timers = {for (final t in before.timers) t.identity: t};
    for (final id in removed) {
      timers.remove(id);
    }
    for (final timer in upserts) {
      timers[timer.identity] = timer;
    }
    return TavernWorldInfoData(
      messageCount: messageCount,
      historyMarker: historyMarker,
      timers: List.unmodifiable(timers.values.toList()..sort(_timerOrder)),
    );
  }

  Map<String, Object?> toJson() => {
    'messageCount': messageCount,
    'historyMarker': historyMarker,
    'upserts': ([
      ...upserts,
    ]..sort(_timerOrder)).map((t) => t.toJson()).toList(),
    'removed':
        ([...removed]..sort(
              (a, b) =>
                  '${a.$1}\u0000${a.$2}'.compareTo('${b.$1}\u0000${b.$2}'),
            ))
            .map((id) => [id.$1, id.$2])
            .toList(),
  };
  factory TavernWorldInfoDelta.fromJson(Map<String, dynamic> json) {
    final result = TavernWorldInfoDelta(
      messageCount: json['messageCount'] as int,
      historyMarker: json['historyMarker'] as String,
      upserts: List.unmodifiable(
        (json['upserts'] as List).map(
          (j) => TavernLoreTimer.fromJson(Map<String, dynamic>.from(j as Map)),
        ),
      ),
      removed: List.unmodifiable(
        (json['removed'] as List).map((j) {
          final pair = j as List;
          return (pair[0] as String, pair[1] as String);
        }),
      ),
    );
    if (result.messageCount < 0 ||
        (result.historyMarker.isNotEmpty &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(result.historyMarker)) ||
        result.upserts.map((t) => t.identity).toSet().length !=
            result.upserts.length ||
        result.removed.toSet().length != result.removed.length ||
        result.removed.any((id) => id.$1.isEmpty || id.$2.isEmpty) ||
        result.upserts.any((t) => result.removed.contains(t.identity))) {
      throw const FormatException('Invalid durable delta.');
    }
    return result;
  }
}

enum TavernWorldInfoProvenance {
  fresh,
  legacyUnavailable,
  historicalUnavailable,
  forkCheckpoint,
}

enum TavernReconciliationOutcome { prepared, committed, discarded, conflict }

class TavernWorldInfoSnapshot {
  const TavernWorldInfoSnapshot({
    required this.sessionId,
    required this.storyLineId,
    this.version = 0,
    this.data = const TavernWorldInfoData(),
    this.initialData = const TavernWorldInfoData(),
    this.provenance = TavernWorldInfoProvenance.fresh,
    this.lastAttemptId,
    this.initialAttemptId,
  });
  final String sessionId, storyLineId;
  final int version;
  final TavernWorldInfoData data, initialData;
  final TavernWorldInfoProvenance provenance;
  final String? lastAttemptId, initialAttemptId;
  TavernWorldInfoSnapshot committed(TavernWorldInfoPlan plan) =>
      TavernWorldInfoSnapshot(
        sessionId: sessionId,
        storyLineId: storyLineId,
        version: version + 1,
        data: plan.delta.apply(data),
        initialData: initialData,
        provenance: provenance,
        lastAttemptId: plan.attemptId,
        initialAttemptId: initialAttemptId,
      );
}

class TavernWorldInfoPlan {
  const TavernWorldInfoPlan({
    required this.attemptId,
    required this.sessionId,
    required this.storyLineId,
    required this.turnId,
    required this.alternativeId,
    required this.compileFingerprint,
    required this.requestFingerprint,
    required this.expectedVersion,
    required this.baseFingerprint,
    required this.delta,
    required this.included,
  });
  final String attemptId, sessionId, storyLineId, turnId, alternativeId;
  final String compileFingerprint, requestFingerprint, baseFingerprint;
  final int expectedVersion;
  final TavernWorldInfoDelta delta;
  final List<TavernLoreIdentity> included;
  String get identity => tavernDigest(toJson());
  Map<String, Object?> toJson() => {
    'attempt': attemptId,
    'session': sessionId,
    'line': storyLineId,
    'turn': turnId,
    'alternative': alternativeId,
    'compile': compileFingerprint,
    'request': requestFingerprint,
    'expectedVersion': expectedVersion,
    'baseFingerprint': baseFingerprint,
    'delta': delta.toJson(),
    'included':
        ([...included]..sort(
              (a, b) =>
                  '${a.$1}\u0000${a.$2}'.compareTo('${b.$1}\u0000${b.$2}'),
            ))
            .map((id) => [id.$1, id.$2])
            .toList(),
  };
  factory TavernWorldInfoPlan.fromJson(Map<String, dynamic> json) {
    final result = TavernWorldInfoPlan(
      attemptId: json['attempt'] as String,
      sessionId: json['session'] as String,
      storyLineId: json['line'] as String,
      turnId: json['turn'] as String,
      alternativeId: json['alternative'] as String,
      compileFingerprint: json['compile'] as String,
      requestFingerprint: json['request'] as String,
      expectedVersion: json['expectedVersion'] as int,
      baseFingerprint: json['baseFingerprint'] as String,
      delta: TavernWorldInfoDelta.fromJson(
        Map<String, dynamic>.from(json['delta'] as Map),
      ),
      included: List.unmodifiable(
        (json['included'] as List).map((j) {
          final p = j as List;
          return (p[0] as String, p[1] as String);
        }),
      ),
    );
    final digest = RegExp(r'^[a-f0-9]{64}$');
    if ([
          result.attemptId,
          result.sessionId,
          result.storyLineId,
          result.turnId,
          result.alternativeId,
        ].any((s) => s.isEmpty) ||
        result.expectedVersion < 0 ||
        !digest.hasMatch(result.compileFingerprint) ||
        !digest.hasMatch(result.requestFingerprint) ||
        !digest.hasMatch(result.baseFingerprint) ||
        result.included.toSet().length != result.included.length ||
        result.included.any((id) => id.$1.isEmpty || id.$2.isEmpty)) {
      throw const FormatException('Invalid durable plan.');
    }
    return result;
  }
}

class TavernWorldInfoJournal {
  const TavernWorldInfoJournal({
    required this.plan,
    this.outcome = TavernReconciliationOutcome.prepared,
    this.committedVersion,
    this.reason,
    this.originalPlanIdentity,
  });
  final TavernWorldInfoPlan plan;
  final TavernReconciliationOutcome outcome;
  final int? committedVersion;
  final String? reason, originalPlanIdentity;
  TavernWorldInfoJournal settled(
    TavernReconciliationOutcome result, {
    int? version,
    String? reason,
  }) => TavernWorldInfoJournal(
    plan: plan,
    outcome: result,
    committedVersion: version ?? committedVersion,
    reason: reason,
    originalPlanIdentity: originalPlanIdentity,
  );
}

class TavernReconciliationConflict implements Exception {
  const TavernReconciliationConflict(this.reason);
  final String reason;
  @override
  String toString() => 'Tavern reconciliation blocked ($reason).';
}
