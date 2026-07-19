// Minimal, dependency-free holder for the current FCM registration token so
// ApiClient's request interceptor can read it (to set the `fcm-token` header)
// without importing the full push service / Firebase / go_router graph.
//
// PushNotificationService is the sole writer (on first fetch and on
// onTokenRefresh). The interceptor is the sole reader. Null until the first
// getToken() resolves - the interceptor omits the header while it's null.
String? fcmTokenForHeader;
