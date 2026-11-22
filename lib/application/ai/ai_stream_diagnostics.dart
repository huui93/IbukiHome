import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../core/diagnostics/safe_content_fingerprint.dart';
import '../../domain/ai/ai_generation.dart';

class AiStreamDiagnostics {
  AiStreamDiagnostics({
    required this.generationTraceId,
    required String sessionId,
    required this.requestType,
    required this.provider,
    required this.model,
    required this.requestedOutputLimit,
    required this.effectiveOutputLimit,
    this.autoRecoveryAttemptCount = 0,
  }) : sessionHash = anonymizedIdentifier(sessionId),
       _startedAt = DateTime.now().toUtc();

  final String generationTraceId;
  final String sessionHash;
  final String requestType;
  final String provider;
  final String model;
  final int? requestedOutputLimit;
  final int? effectiveOutputLimit;
  final int autoRecoveryAttemptCount;
  final DateTime _startedAt;

  var streamEventCount = 0;
  var contentPartCount = 0;
  var normalizedEmittedCharacterCount = 0;
  DateTime? firstEventAt;
  DateTime? lastEventAt;

  void record(AiStreamEvent event) {
    final now = DateTime.now().toUtc();
    firstEventAt ??= now;
    lastEventAt = now;
    streamEventCount += 1;
    if (!event.isTerminal && event.content.isNotEmpty) {
      contentPartCount += 1;
      normalizedEmittedCharacterCount += event.content.length;
    }
  }

  void recordContinueContext({
    required int previousAssistantCharacterCount,
    required String previousAssistantStatus,
  }) {
    _log(
      'stage=continue.context previousAssistantChars='
      '$previousAssistantCharacterCount '
      'previousAssistantStatus=$previousAssistantStatus',
    );
  }

  void complete({
    required String adapterOutput,
    required String authoritativeBuffer,
    required String messageContent,
    required String persistedContent,
    required String readbackContent,
    required AiFinishReason finishReason,
    required String generationStatus,
    required String streamEndType,
    String timeoutType = 'none',
    String? exceptionType,
    String? cancelReason,
  }) {
    final now = DateTime.now().toUtc();
    _log(
      'stage=generation.complete events=$streamEventCount '
      'parts=$contentPartCount '
      'normalizedEmittedChars=$normalizedEmittedCharacterCount '
      'adapterChars=${adapterOutput.length} '
      'bufferChars=${authoritativeBuffer.length} '
      'messageChars=${messageContent.length} '
      'persistedChars=${persistedContent.length} '
      'readbackChars=${readbackContent.length} '
      'adapterHash=${safeContentFingerprint(adapterOutput)} '
      'bufferHash=${safeContentFingerprint(authoritativeBuffer)} '
      'messageHash=${safeContentFingerprint(messageContent)} '
      'persistedHash=${safeContentFingerprint(persistedContent)} '
      'readbackHash=${safeContentFingerprint(readbackContent)} '
      'finishReason=${finishReason.name} generationStatus=$generationStatus '
      'generationStart=${_startedAt.toIso8601String()} '
      'firstEventAt=${firstEventAt?.toIso8601String() ?? 'none'} '
      'lastEventAt=${lastEventAt?.toIso8601String() ?? 'none'} '
      'streamEndAt=${now.toIso8601String()} '
      'durationMs=${now.difference(_startedAt).inMilliseconds} '
      'streamClosedNormally=${streamEndType == 'terminal-signal'} '
      'abnormalEOF=${streamEndType == 'abnormal-eof'} '
      'timeoutType=$timeoutType '
      'exceptionType=${exceptionType ?? 'none'} '
      'cancelReason=${cancelReason ?? 'none'} streamEnd=$streamEndType',
    );
  }

  void _log(String detail) {
    final message =
        'generationTraceId=$generationTraceId sessionHash=$sessionHash '
        'requestType=$requestType provider=$provider model=$model '
        'requestedMaxOutputTokens=${requestedOutputLimit ?? 'provider-default'} '
        'effectiveMaxOutputTokens=${effectiveOutputLimit ?? 'provider-default'} '
        'autoRecoveryAttemptCount=$autoRecoveryAttemptCount $detail';
    developer.log(message, name: 'ibuki.ai.stream');
    if (kDebugMode) debugPrint('AI_STREAM $message');
  }
}
