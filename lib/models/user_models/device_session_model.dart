/// One row from GET /api/user/devices - matches webapp's IDeviceSession
/// (DeviceSessions.tsx) exactly.
class DeviceSession {
  final String sessionID;
  final String deviceType; // "mobile" | "tablet" | "desktop"/other
  final String browser;
  final String os;
  final String ip;

  /// True = the session is active right now; false = show "Last seen ...".
  final bool status;
  final String lastSeen;
  final bool isCurrentDevice;

  const DeviceSession({
    required this.sessionID,
    required this.deviceType,
    required this.browser,
    required this.os,
    required this.ip,
    required this.status,
    required this.lastSeen,
    required this.isCurrentDevice,
  });

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    return DeviceSession(
      sessionID: (json['sessionID'] ?? '').toString(),
      deviceType: (json['deviceType'] ?? '').toString(),
      browser: (json['browser'] ?? '').toString(),
      os: (json['os'] ?? '').toString(),
      ip: (json['ip'] ?? '').toString(),
      status: json['status'] == true,
      lastSeen: (json['lastSeen'] ?? '').toString(),
      isCurrentDevice: json['is_current_device'] == true,
    );
  }
}
