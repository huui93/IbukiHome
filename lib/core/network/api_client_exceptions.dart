class RemoteApiException implements Exception {
  const RemoteApiException(this.message, {this.statusCode, this.requestId});

  final String message;
  final int? statusCode;
  final String? requestId;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' status=$statusCode';
    final request = requestId == null ? '' : ' request_id=$requestId';
    return '$runtimeType:$code$request $message';
  }
}

class RemoteAuthException extends RemoteApiException {
  const RemoteAuthException(super.message, {super.statusCode, super.requestId});
}

class RemoteNotFoundException extends RemoteApiException {
  const RemoteNotFoundException(
    super.message, {
    super.statusCode,
    super.requestId,
  });
}

class RemoteConflictException extends RemoteApiException {
  const RemoteConflictException(
    super.message, {
    super.statusCode,
    super.requestId,
  });
}

class RemoteServerException extends RemoteApiException {
  const RemoteServerException(
    super.message, {
    super.statusCode,
    super.requestId,
  });
}

class RemoteNetworkException extends RemoteApiException {
  const RemoteNetworkException(super.message);
}

class RemoteProtocolException extends RemoteApiException {
  const RemoteProtocolException(
    super.message, {
    super.statusCode,
    super.requestId,
  });
}

class RemoteClientClosedException extends RemoteApiException {
  const RemoteClientClosedException() : super('Remote API client is closed.');
}
