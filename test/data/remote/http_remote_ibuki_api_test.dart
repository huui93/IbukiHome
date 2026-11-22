import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ibukihome/core/network/api_client_exceptions.dart';
import 'package:ibukihome/core/network/remote_api_config.dart';
import 'package:ibukihome/data/remote/http_remote_ibuki_api.dart';

import 'remote_test_helpers.dart';

void main() {
  group('HttpRemoteIbukiApi', () {
    test('sends Bearer header for protected endpoints', () async {
      late Map<String, String> headers;
      final api = apiWithClient(
        MockClient((request) async {
          headers = request.headers;
          return jsonResponse(fixtureJson('capabilities_response.json'));
        }),
      );
      await api.getCapabilities();
      expect(
        headers['authorization'] ?? headers['Authorization'],
        'Bearer test-token',
      );
    });

    test('does not require Bearer header for health', () async {
      late Map<String, String> headers;
      final api = apiWithClient(
        MockClient((request) async {
          headers = request.headers;
          return jsonResponse(fixtureJson('health_response.json'));
        }),
      );
      await api.getHealth();
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('401 maps to auth exception', () async {
      final api = apiWithStatus(401);
      expect(api.getCapabilities(), throwsA(isA<RemoteAuthException>()));
    });

    test('404 maps to not found exception', () async {
      final api = apiWithStatus(404);
      expect(
        api.getProject('missing'),
        throwsA(isA<RemoteNotFoundException>()),
      );
    });

    test('409 maps to conflict exception', () async {
      final api = apiWithStatus(409);
      expect(api.listProjects(), throwsA(isA<RemoteConflictException>()));
    });

    test('500 maps to server exception', () async {
      final api = apiWithStatus(500);
      expect(api.listProjects(), throwsA(isA<RemoteServerException>()));
    });

    test('non JSON response maps to protocol exception', () async {
      final api = apiWithClient(
        MockClient((_) async => http.Response('not-json', 200)),
      );
      expect(api.listProjects(), throwsA(isA<RemoteProtocolException>()));
    });

    test('timeout maps to network exception', () async {
      final api = apiWithClient(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return jsonResponse(fixtureJson('health_response.json'));
        }),
        timeout: const Duration(milliseconds: 1),
      );
      expect(api.getHealth(), throwsA(isA<RemoteNetworkException>()));
    });

    test('token does not appear in exception text', () async {
      final api = apiWithStatus(401, token: 'redacted-input-value');
      try {
        await api.getCapabilities();
      } catch (error) {
        expect(error.toString(), isNot(contains('redacted-input-value')));
      }
    });

    test('client close has explicit behavior', () async {
      final api = apiWithClient(
        MockClient(
          (_) async => jsonResponse(fixtureJson('health_response.json')),
        ),
      );
      api.close();
      expect(api.getHealth(), throwsA(isA<RemoteClientClosedException>()));
    });

    test('listProjects decodes project summaries', () async {
      final api = apiWithClient(
        MockClient(
          (_) async => jsonResponse(fixtureJson('project_list_response.json')),
        ),
      );
      final projects = await api.listProjects();
      expect(projects.single.id, 'project-alpha');
    });

    test('listSegments decodes segments', () async {
      final api = apiWithClient(
        MockClient(
          (_) async => jsonResponse(fixtureJson('segment_list_response.json')),
        ),
      );
      final segments = await api.listSegments('project-alpha');
      expect(segments, hasLength(2));
    });
  });
}

HttpRemoteIbukiApi apiWithStatus(int status, {String token = 'test-token'}) {
  return apiWithClient(
    MockClient(
      (_) async => jsonResponse(fixtureJson('api_error.json'), status),
    ),
    token: token,
  );
}

HttpRemoteIbukiApi apiWithClient(
  http.Client client, {
  String token = 'test-token',
  Duration timeout = const Duration(seconds: 10),
}) {
  return HttpRemoteIbukiApi(
    config: RemoteApiConfig(
      baseUri: Uri.parse('http://127.0.0.1:8765/api/v1'),
      bearerToken: token,
      timeout: timeout,
    ),
    client: client,
  );
}

http.Response jsonResponse(Object body, [int status = 200]) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json', 'x-request-id': 'req-test'},
  );
}
