import 'package:absorb/services/native_ios_audio_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const events = MethodChannel('com.absorb.audio_engine.events');
  const methods = MethodChannel('com.absorb.audio_engine');

  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      events,
      (_) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      methods,
      (_) async => null,
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(events, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(methods, null);
  });

  for (final code in <String?>['AVFoundationErrorDomain:-11850', null]) {
    test('native failure stops playing and forwards error ($code)', () async {
      final player = NativeIosAudioPlayer();
      final states = <ja.PlayerState>[];
      final processing = <ja.ProcessingState>[];
      final errors = <Object>[];
      final subscriptions = [
        player.playerStateStream.listen(states.add),
        player.processingStateStream.listen(processing.add),
        player.playbackEventStream.listen((_) {}, onError: errors.add),
      ];
      Future<void> send(Map<String, Object?> event) async {
        binding.defaultBinaryMessenger.handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope(event),
          (_) {},
        );
        await Future<void>.delayed(Duration.zero);
      }

      try {
        await Future<void>.delayed(Duration.zero);
        await send({'type': 'state', 'playing': true, 'processingState': 3});
        expect(player.playing, isTrue);
        await send({'type': 'error', 'message': 'URL not found', 'code': code});
        expect(player.playing, isFalse);
        expect(player.processingState, ja.ProcessingState.idle);
        expect(states.last.playing, isFalse);
        expect(processing.last, ja.ProcessingState.idle);
        expect(errors.single, isA<PlatformException>());
        final error = errors.single as PlatformException;
        expect(error.code, code ?? 'ios_audio_error');
        expect(error.message, 'URL not found');
        await send({'type': 'state', 'playing': true, 'processingState': 3});
        expect(player.playing, isTrue);
        expect(player.processingState, ja.ProcessingState.ready);
      } finally {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        await player.dispose();
      }
    });
  }
}
