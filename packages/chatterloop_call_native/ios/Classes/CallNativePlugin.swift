import Flutter
import UIKit

/// iOS half of chatterloop/call_native - the same contract as Android, with
/// what iOS can do safely today:
///
///   ringer   Not available (startRinging answers false). iOS will not let an
///            app keep a ringtone playing from a push unless the call goes
///            through CallKit and VoIP pushes, so an iOS ring is the
///            notification's own sound - played once. Dart falls back to that
///            whenever startRinging is false.
///   ongoing  Tracked (isInCall), with no notification: iOS shows its own
///            in-call indicator, and the "audio" background mode in the app's
///            Info.plist is what keeps the call running in the background.
///   pip      Not yet (isPipSupported answers false). It needs the call's
///            video frames fed natively into an AVPictureInPictureController
///            (iOS 15+), which has to be built and tested on a Mac; the Dart
///            side already asks, so it lights up without Dart changes.
public class CallNativePlugin: NSObject, FlutterPlugin {
  private static var inCall = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "chatterloop/call_native",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(CallNativePlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startRinging":
      result(false)
    case "stopRinging", "updateOngoingCall", "updatePip", "exitPip":
      result(nil)
    case "startOngoingCall":
      CallNativePlugin.inCall = true
      result(true)
    case "stopOngoingCall":
      CallNativePlugin.inCall = false
      result(nil)
    case "isInCall":
      result(CallNativePlugin.inCall)
    case "isPipSupported":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
