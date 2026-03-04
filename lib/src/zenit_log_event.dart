class ZenitLogEvent {
  const ZenitLogEvent({required this.timestamp, required this.message});

  final DateTime timestamp;
  final String message;

  @override
  String toString() => '${timestamp.toIso8601String()} $message';
}
