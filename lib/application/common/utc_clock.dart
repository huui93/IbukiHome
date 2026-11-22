class UtcClock {
  const UtcClock();

  DateTime now() => DateTime.now().toUtc();
}
