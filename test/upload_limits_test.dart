// The upload cap's env wiring.
//
// Worth pinning because the failure modes are both silent: a define that
// doesn't reach the constant means the app quietly keeps the old limit after a
// deployment raises it, and a define of 0 (or the key being absent, which
// `int.fromEnvironment` also reports as 0) would become a cap that rejects
// every file with no error anywhere.
//
// Run BOTH ways to exercise both branches:
//   flutter test test/upload_limits_test.dart
//   flutter test test/upload_limits_test.dart --dart-define=MAX_UPLOAD_FILE_SIZE_MB=50

import 'package:chatterloop_app/core/utils/upload_limits.dart';
import 'package:flutter_test/flutter_test.dart';

/// Read here exactly as the constant reads it, so this test follows whatever
/// the run was given rather than assuming one of the two cases.
const int _defined =
    int.fromEnvironment('MAX_UPLOAD_FILE_SIZE_MB', defaultValue: 0);

void main() {
  test('the define wins when given, the hardcoded default when not', () {
    expect(kMaxUploadMb, _defined > 0 ? _defined : 100);
  });

  test('the cap is always usable', () {
    // The guard's whole point: no define, an empty one, or a nonsensical one
    // can never leave the app unable to attach anything.
    expect(kMaxUploadMb, greaterThan(0));
    expect(kMaxUploadBytes, kMaxUploadMb * 1024 * 1024);
  });

  test('the label tracks the number it describes', () {
    // These are shown to the user next to a check made in bytes; a label that
    // drifts from the cap tells them the wrong limit.
    expect(kMaxUploadLabel, '${kMaxUploadMb}MB');
  });
}
