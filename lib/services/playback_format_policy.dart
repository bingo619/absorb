import 'package:flutter/foundation.dart';

/// WMA needs server transcoding on iOS. Keep all other formats/platforms on
/// their existing playback path, including Android's native WMA decoder.
class PlaybackFormatPolicy {
  PlaybackFormatPolicy._();

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool needsWmaTranscode(Map<String, dynamic> session) {
    // ABS: 0 = direct play, 1 = direct stream, 2 = transcode. A transcoded
    // session may retain original-file metadata; do not transcode it again.
    if (!isIOS || session['playMethod'] == 2) return false;
    final tracks = session['audioTracks'] as List<dynamic>? ?? const [];
    return tracks.whereType<Map>().any(_isWmaTrack);
  }

  static bool _isWmaTrack(Map track) {
    final contentUrl = track['contentUrl'] as String? ?? '';
    final path = Uri.tryParse(contentUrl)?.path.toLowerCase() ?? '';
    // An HLS URL is already playable output, even if its metadata mentions
    // the source codec. Cached sessions do not include playMethod.
    if (path.endsWith('.m3u8')) return false;
    final mime = (track['mimeType'] as String? ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    final codec = (track['codec'] as String? ?? '').trim().toLowerCase();
    final metadata = track['metadata'];
    final filename = metadata is Map
        ? (metadata['filename'] as String? ?? '').toLowerCase()
        : '';
    final extension = metadata is Map
        ? (metadata['ext'] as String? ?? '').toLowerCase()
        : '';
    return const {
          'audio/x-ms-wma',
          'audio/wma',
          'audio/x-wma',
        }.contains(mime) ||
        const {
          'wmav1',
          'wmav2',
          'wmapro',
          'wmalossless',
          'wmavoice',
        }.contains(codec) ||
        path.endsWith('.wma') ||
        filename.endsWith('.wma') ||
        extension == '.wma' ||
        extension == 'wma';
  }
}
