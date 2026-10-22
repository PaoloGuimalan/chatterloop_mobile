/// Older servers omit the catalog flag and keep their existing enabled state.
bool isEncryptionPurposeEnabled(Map<String, dynamic>? purpose) =>
    purpose?['is_active'] != false;
