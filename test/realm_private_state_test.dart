import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// The plugin's platform boundary is replaced only in this isolated lifecycle test.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:chatterloop_app/views/realm/realm_private_state.dart';

class DelayedStorage extends TestFlutterSecureStoragePlatform {
  DelayedStorage() : super({});
  Completer<String?>? pending;
  @override
  Future<String?> read(
          {required String key, required Map<String, String> options}) =>
      pending?.future ?? Future.value(null);
}

class GuardFixture extends StatefulWidget {
  const GuardFixture({super.key});
  @override
  State<GuardFixture> createState() => GuardState();
}

class GuardState extends RealmPrivateState<GuardFixture> {
  @override
  void reloadPrivate() {}
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets(
      'opening a review dialog preserves in-flight reads until a refresh',
      (tester) async {
    final previous = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance = DelayedStorage();
    addTearDown(() => FlutterSecureStoragePlatform.instance = previous);
    final key = GlobalKey<GuardState>();
    await tester.pumpWidget(GuardFixture(key: key));
    final state = key.currentState!;
    final reading = await state.requestTicket();
    final reviewing = await state.requestTicket(invalidate: false);
    expect(await state.isCurrent(reading), true);
    expect(await state.isCurrent(reviewing), true);
    await state.requestTicket();
    expect(await state.isCurrent(reading), false);
    expect(await state.isCurrent(reviewing), false);
  });

  testWidgets(
      'an unmounted private screen rejects validation completing after a token read',
      (tester) async {
    final previous = FlutterSecureStoragePlatform.instance;
    final storage = DelayedStorage();
    FlutterSecureStoragePlatform.instance = storage;
    addTearDown(() => FlutterSecureStoragePlatform.instance = previous);
    final key = GlobalKey<GuardState>();
    await tester.pumpWidget(GuardFixture(key: key));
    final state = key.currentState!;
    final ticket = await state.requestTicket();
    storage.pending = Completer<String?>();
    final result = state.isCurrent(ticket);
    await tester.pumpWidget(const SizedBox());
    storage.pending!.complete(null);
    expect(await result, false);
  });
}
