class ApiRequestId {
  const ApiRequestId(this.value);

  final String value;

  bool get isEmpty => value.trim().isEmpty;

  @override
  String toString() => value;
}
