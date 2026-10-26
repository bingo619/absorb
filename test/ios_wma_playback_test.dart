import 'dart:convert';

import 'package:absorb/services/api_service.dart';
import 'package:absorb/services/playback_format_policy.dart';
import 'package:absorb/services/session_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> directSession({List<Map<String, dynamic>>? tracks}) => {
  'id': 'direct',
  'playMethod': 0,
  'currentTime': 123.0,
  'audioTracks':
      tracks ??
      [
        {'mimeType': 'audio/x-ms-wma', 'contentUrl': '/audio/book.wma'},
      ],
};

Map<String, dynamic> transcodedSession() => {
  'id': 'transcoded',
  'playMethod': 2,
  'currentTime': 123.0,
  'audioTracks': [
    {
      'mimeType': 'application/vnd.apple.mpegurl',
      'contentUrl': '/hls/transcoded/output.m3u8',
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final episode in [false, true]) {
    test(
      '${episode ? "episode" : "book"}: replace direct WMA before returning',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/close'))
            return http.Response('', 200);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(
              body['forceTranscode'] == true
                  ? transcodedSession()
                  : directSession(),
            ),
            200,
          );
        });
        final api = ApiService(
          baseUrl: 'https://abs.invalid',
          token: 'test-key',
          isLegacyToken: true,
          httpClient: client,
        );

        final result = episode
            ? await api.startEpisodePlaybackSession('book', 'episode')
            : await api.startPlaybackSession('book', startOffset: 123);
        expect(result?['id'], 'transcoded');
        expect(result?['currentTime'], 123.0);
        final playPath = episode
            ? '/api/items/book/play/episode'
            : '/api/items/book/play';
        expect(requests.map((r) => r.url.path), [
          playPath,
          '/api/session/direct/close',
          playPath,
        ]);
        final first = jsonDecode(requests.first.body) as Map<String, dynamic>;
        final retry = jsonDecode(requests.last.body) as Map<String, dynamic>;
        expect(first['supportedMimeTypes'], isNot(contains('audio/x-ms-wma')));
        expect(retry['forceTranscode'], isTrue);
        expect(retry['forceDirectPlay'], isFalse);
        expect(retry['deviceInfo'], first['deviceInfo']);
        if (!episode) expect(retry['startOffset'], 123);
      },
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final mime in ['audio/mpeg', 'audio/mp4', 'audio/flac', 'audio/ogg']) {
      test(
        '$platform: $mime retains the existing direct-play request',
        () async {
          debugDefaultTargetPlatformOverride = platform;
          final requests = <http.Request>[];
          final client = MockClient((r) async {
            requests.add(r);
            return http.Response(
              jsonEncode(
                directSession(
                  tracks: [
                    {'mimeType': mime, 'contentUrl': '/audio/track'},
                  ],
                ),
              ),
              200,
            );
          });
          final api = ApiService(
            baseUrl: 'https://abs.invalid',
            token: 'test-key',
            isLegacyToken: true,
            httpClient: client,
          );
          expect((await api.startPlaybackSession('book'))?['id'], 'direct');
          expect(requests, hasLength(1));
          final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
          expect(body['forceDirectPlay'], isTrue);
          expect(body['forceTranscode'], isFalse);
          expect(body['supportedMimeTypes'], contains(mime));
          expect(
            body['supportedMimeTypes'],
            hasLength(platform == TargetPlatform.iOS ? 12 : 13),
          );
        },
      );
    }
  }

  test('Android WMA still uses direct play and advertises WMA', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final requests = <http.Request>[];
    final client = MockClient((r) async {
      requests.add(r);
      return http.Response(jsonEncode(directSession()), 200);
    });
    final api = ApiService(
      baseUrl: 'https://abs.invalid',
      token: 'test-key',
      isLegacyToken: true,
      httpClient: client,
    );
    expect(
      (await api.startEpisodePlaybackSession('book', 'episode'))?['id'],
      'direct',
    );
    expect(requests, hasLength(1));
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['forceDirectPlay'], isTrue);
    expect(body['forceTranscode'], isFalse);
    expect(body['supportedMimeTypes'], contains('audio/x-ms-wma'));
  });

  test('forced transcoding takes precedence over forceDirectPlay', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((r) async {
      bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
      return http.Response(jsonEncode(transcodedSession()), 200);
    });
    final api = ApiService(
      baseUrl: 'https://abs.invalid',
      token: 'test-key',
      isLegacyToken: true,
      httpClient: client,
    );
    expect(
      (await api.startPlaybackSession(
        'book',
        forceDirectPlay: true,
        forceTranscode: true,
      ))?['playMethod'],
      2,
    );
    expect(bodies, hasLength(1));
    expect(bodies.single['forceDirectPlay'], isFalse);
    expect(bodies.single['forceTranscode'], isTrue);
  });

  test('a server ignoring forceTranscode cannot cause a retry loop', () async {
    var playRequests = 0;
    var closes = 0;
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/close')) {
        closes++;
        return http.Response('', 200);
      }
      playRequests++;
      return http.Response(jsonEncode(directSession()), 200);
    });
    final api = ApiService(
      baseUrl: 'https://abs.invalid',
      token: 'test-key',
      isLegacyToken: true,
      httpClient: client,
    );
    expect(
      await api.startPlaybackSession('book', forceDirectPlay: true),
      isNull,
    );
    expect(playRequests, 2);
    expect(closes, 2);
  });

  test('a failed transcode request does not return the original WMA', () async {
    var playRequests = 0;
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/close')) return http.Response('', 200);
      playRequests++;
      return playRequests == 1
          ? http.Response(jsonEncode(directSession()), 200)
          : http.Response('transcoding unavailable', 500);
    });
    final api = ApiService(
      baseUrl: 'https://abs.invalid',
      token: 'test-key',
      isLegacyToken: true,
      httpClient: client,
    );
    expect(await api.startPlaybackSession('book'), isNull);
    expect(playRequests, 2);
  });

  test(
    'WMA detection includes MIME variants, codecs, filenames and later tracks',
    () {
      for (final track in [
        {'mimeType': 'Audio/X-MS-WMA; codecs=wmav2'},
        {'mimeType': 'audio/wma'},
        {'mimeType': 'audio/x-wma'},
        {'codec': 'WMAPRO'},
        {'codec': 'wmalossless'},
        {'contentUrl': 'https://abs.invalid/audio/Track.WMA?token=redacted'},
        {'contentUrl': '/audio/Track%2Ewma'},
        {
          'metadata': {'filename': 'Track.WMA'},
        },
        {
          'metadata': {'ext': '.WMA'},
        },
      ]) {
        expect(
          PlaybackFormatPolicy.needsWmaTranscode(
            directSession(
              tracks: [
                {'mimeType': 'audio/mpeg', 'contentUrl': '/audio/first.mp3'},
                track,
              ],
            ),
          ),
          isTrue,
          reason: '$track',
        );
      }
      expect(
        PlaybackFormatPolicy.needsWmaTranscode({'audioTracks': []}),
        isFalse,
      );
    },
  );

  test('transcoded output is not mistaken for its WMA source metadata', () {
    final session = directSession();
    session['playMethod'] = 2;
    expect(PlaybackFormatPolicy.needsWmaTranscode(session), isFalse);
    expect(
      PlaybackFormatPolicy.needsWmaTranscode({
        'audioTracks': [
          {'mimeType': 'audio/x-ms-wma', 'contentUrl': '/hls/output.m3u8'},
        ],
      }),
      isFalse,
    );
  });

  test('only the old iOS/WMA cache entry is discarded', () async {
    await SessionCache.save(
      itemId: 'book',
      episodeId: 'wma',
      audioTracks: directSession()['audioTracks'] as List<dynamic>,
      chapters: [],
      totalDuration: 500,
    );
    await SessionCache.save(
      itemId: 'book',
      episodeId: 'mp3',
      audioTracks: [
        {'mimeType': 'audio/mpeg', 'contentUrl': '/audio/track.mp3'},
      ],
      chapters: [],
      totalDuration: 500,
    );
    expect(await SessionCache.load(itemId: 'book', episodeId: 'wma'), isNull);
    expect(
      await SessionCache.load(itemId: 'book', episodeId: 'mp3'),
      isNotNull,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('session_cache_book_wma'), isFalse);
    expect(prefs.containsKey('session_cache_book_mp3'), isTrue);
  });

  test('Android WMA cache is kept', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await SessionCache.save(
      itemId: 'book',
      audioTracks: directSession()['audioTracks'] as List<dynamic>,
      chapters: [],
      totalDuration: 500,
    );
    expect(await SessionCache.load(itemId: 'book'), isNotNull);
  });
}
