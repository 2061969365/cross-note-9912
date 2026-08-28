// Deterministic LWW — mirrors server logic. Used when applying pull/broadcast locally.
bool lwwIncomingWins({required String updatedAtA, required int versionA, required String deviceIdA, required String updatedAtB, required int versionB, required String deviceIdB}) {
  if (updatedAtA != updatedAtB) return updatedAtA.compareTo(updatedAtB) > 0;
  if (versionA != versionB) return versionA > versionB;
  return deviceIdA.compareTo(deviceIdB) > 0;
}

bool shouldApplyIncoming(Map<String, dynamic> incoming, Map<String, dynamic> existing) {
  return lwwIncomingWins(
    updatedAtA: (incoming['updated_at'] as String?) ?? '',
    versionA: (incoming['version'] as num?)?.toInt() ?? 0,
    deviceIdA: (incoming['device_id'] as String?) ?? '',
    updatedAtB: (existing['updated_at'] as String?) ?? '',
    versionB: (existing['version'] as num?)?.toInt() ?? 0,
    deviceIdB: (existing['device_id'] as String?) ?? '',
  );
}
