// Planned error hierarchy — sealed AppError with typed subclasses (Network/Database/Sync/Validation).
// Extend as features require; not yet exhaustively applied across all call sites.
sealed class AppError implements Exception {
  final String message;
  const AppError(this.message);
  @override
  String toString() => '$runtimeType: $message';
}

class NetworkError extends AppError {
  const NetworkError(super.message);
}

class DatabaseError extends AppError {
  const DatabaseError(super.message);
}

class SyncError extends AppError {
  const SyncError(super.message);
}

class ValidationError extends AppError {
  const ValidationError(super.message);
}
