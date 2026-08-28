// Deterministic LWW resolver for server authority.
// Returns 'incomingWins' when incoming should overwrite existing.
export function lwwIncomingWins(
  incoming: { updated_at: string; version: number; device_id: string },
  existing: { updated_at: string; version: number; device_id: string }
): boolean {
  if (incoming.updated_at !== existing.updated_at) return incoming.updated_at > existing.updated_at;
  if (incoming.version !== existing.version) return incoming.version > existing.version;
  return incoming.device_id > existing.device_id;
}
