// What the app says when a request fails - the Dart port of the webapp's
// errormessages.ts. Worth tests rather than a reading: this copy is what a
// person sees when something goes wrong, and each rule here exists because a
// raw backend string once reached the screen.

import 'package:chatterloop_app/core/errors/request_errors.dart';
import 'package:chatterloop_app/core/ui/cl_alerts.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _refused(int status, Object? body) {
  final options = RequestOptions(path: '/u/createchannel');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: body),
  );
}

void main() {
  group('a refusal', () {
    test("shows the server's own reason", () {
      final described = describeRequestError(
        _refused(403, {
          'status': false,
          'message': 'You are not allowed to create channels in this server.',
        }),
        fallback: "We couldn't create that channel.",
      );
      expect(described.message,
          'You are not allowed to create channels in this server.');
      // 4xx is something the user can act on.
      expect(described.type, CLAlertType.warning);
    });

    test('drops the permission code the middleware appends', () {
      final described = describeRequestError(_refused(403, {
        'status': false,
        'message':
            'You do not have permission to perform this action (messages.send).',
      }));
      // Without the code it is the stock DRF sentence, which has friendlier
      // copy of its own.
      expect(described.message, "You don't have permission to do that.");
      expect(described.message, isNot(contains('messages.send')));
    });

    test('never repeats raw exception text', () {
      final described = describeRequestError(
        _refused(400, {'error': "KeyError: 'serverID'"}),
        fallback: "We couldn't create that channel.",
      );
      expect(described.message, "We couldn't create that channel.");
    });

    test('a bare 403 with nothing to say still says something specific', () {
      final described =
          describeRequestError(_refused(403, null), fallback: 'Nope.');
      expect(described.message, "You don't have permission to do that.");
    });

    test('field errors read as sentences, at most three', () {
      final described = describeRequestError(_refused(400, {
        'first_name': ['This field is required.'],
        'birth_date': ['Enter a valid date.'],
      }));
      expect(described.message,
          'First name: This field is required. Birth date: Enter a valid date.');
    });

    test('a session code gets plain-language copy', () {
      final described = describeRequestError(
          _refused(403, {'detail': 'CONSENT_REQUIRED: terms v3'}));
      expect(described.message, contains('Terms and Conditions'));
    });
  });

  group('a failure on our side', () {
    test("5xx never shows the server's exception", () {
      final described = describeRequestError(
        _refused(500, {'error': 'IntegrityError: duplicate key value'}),
        fallback: "We couldn't create that channel.",
      );
      expect(described.message,
          "We couldn't create that channel. Please try again in a moment.");
      expect(described.type, CLAlertType.error);
    });

    test('no answer at all is a connection problem', () {
      final described = describeRequestError(DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      ));
      expect(described.message, contains("couldn't reach Chatterloop"));
      expect(described.status, 0);
    });

    test('a timeout says so', () {
      final described = describeRequestError(DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.receiveTimeout,
      ));
      expect(described.message, contains('took too long'));
    });

    test('a cancelled request is silent', () {
      final described = describeRequestError(DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.cancel,
      ));
      expect(described.silent, isTrue);
    });
  });

  group('a status:false inside a 200', () {
    test("uses the body's message", () {
      expect(
        resolveResponseMessage(
            {'status': false, 'message': 'transfer ownership first'}, 'Nope.'),
        'Transfer ownership first.',
      );
    });

    test("doesn't lift a sentence out of the payload", () {
      expect(
        resolveResponseMessage({
          'status': false,
          'result': ['this is data, not a reason'],
        }, "We couldn't join that server."),
        "We couldn't join that server.",
      );
    });
  });
}
