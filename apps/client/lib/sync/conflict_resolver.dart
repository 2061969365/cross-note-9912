// Deterministic LWW — mirrors server logic. Used when applying pull/broadcast locally.
DateTime? _parseUtc(String s) {
  if (s.isEmpty) return null;
  try {
    return DateTime.parse(s).toUtc();
  } catch (_) {
    return null;
  }
}

String _normalizeIso(String s) {
  final dt = _parseUtc(s);
  if (dt != null) return dt.toIso8601String();
  return s;
}

bool lwwIncomingWins({required String updatedAtA, required int versionA, required String deviceIdA, required String updatedAtB, required int versionB, required String deviceIdB}) {
  final dtA = _parseUtc(updatedAtA);
  final dtB = _parseUtc(updatedAtB);
  if (dtA != null && dtB != null) {
    if (dtA.isAtSameMomentAs(dtB) == false) return dtA.isAfter(dtB);
  } else {
    final nA = dtA?.toIso8601String() ?? _normalizeIso(updatedAtA);
    final nB = dtB?.toIso8601String() ?? _normalizeIso(updatedAtB);
    if (nA != nB) return nA.compareTo(nB) > 0;
  }
  if (versionA != versionB) return versionA > versionB;
  return deviceIdA.compareTo(deviceIdB) > 0;
}

bool shouldApplyIncoming(Map<String, dynamic> incoming, Map<String, dynamic> existing) {
  // Normalize updated_at via UTC before comparison; handles server/client clock skew
  // and differing ISO formats (e.g. missing Z, millis).
  final incUpdatedAt = _normalizeIso((incoming['updated_at'] as String?) ?? '');
  final exUpdatedAt = _normalizeIso((existing['updated_at'] as String?) ?? '');
  // Reconstruct maps with normalized strings so lwwIncomingWins compares UTC-normalized values.
  return lwwIncomingWins(
    updatedAtA: incUpdatedAt,
    versionA: (incoming['version'] as num?)?.toInt() ?? 0,
    deviceIdA: (incoming['device_id'] as String?) ?? '',
    updatedAtB: exUpdatedAt,
    versionB: (existing['version'] as num?)?.toInt() ?? 0,
    deviceIdB: (existing['device_id'] as String?) ?? '',
  );
}
