import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class SpeedResult {
  const SpeedResult({required this.average, required this.peak});

  final double average;
  final double peak;
}

/// محرك قياس السرعة: اتصالات متوازية لاستغلال كامل عرض النطاق.
class SpeedEngine {
  static const _trace = 'https://www.cloudflare.com/cdn-cgi/trace';
  static const _down = 'https://speed.cloudflare.com/__down';
  static const _up = 'https://speed.cloudflare.com/__up';

  /// زمن الاستجابة: اتصال واحد مُسخَّن (بدون احتساب مصافحة TLS) والوسيط من 5 عينات.
  static Future<int> measurePing() async {
    final client = http.Client();
    try {
      await client
          .get(Uri.parse(_trace))
          .timeout(const Duration(seconds: 10));
      final samples = <int>[];
      for (var i = 0; i < 5; i++) {
        final watch = Stopwatch()..start();
        try {
          final response = await client
              .get(Uri.parse(_trace))
              .timeout(const Duration(seconds: 8));
          watch.stop();
          if (response.statusCode == 200) {
            samples.add(watch.elapsedMilliseconds);
          }
        } catch (_) {
          // تجاهل العينة الفاشلة وإكمال البقية
        }
      }
      if (samples.isEmpty) throw Exception('فشل قياس زمن الاستجابة');
      samples.sort();
      return samples[samples.length ~/ 2];
    } finally {
      client.close();
    }
  }

  /// تنزيل بعدة اتصالات متوازية لمدة محددة، مع سرعة حية.
  static Future<SpeedResult> measureDownload({
    int streams = 6,
    Duration duration = const Duration(seconds: 10),
    void Function(double mbps)? onSpeed,
  }) async {
    final client = http.Client();
    var running = true;
    var total = 0;
    var peak = 0.0;
    var lastBytes = 0;
    var lastMs = 0;
    var markBytes = 0;
    var markMs = -1;
    final watch = Stopwatch()..start();

    final timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final ms = watch.elapsedMilliseconds;
      final dt = ms - lastMs;
      if (dt <= 0) return;
      final mbps = (total - lastBytes) * 8 / dt / 1000;
      lastBytes = total;
      lastMs = ms;
      // نتجاهل أول ثانيتين (تسخين الاتصال) عند حساب المتوسط
      if (markMs < 0 && ms >= 2000) {
        markBytes = total;
        markMs = ms;
      }
      if (mbps > peak) peak = mbps;
      onSpeed?.call(mbps);
    });

    Future<void> worker() async {
      while (running) {
        try {
          final request =
              http.Request('GET', Uri.parse('$_down?bytes=50000000'));
          final response =
              await client.send(request).timeout(const Duration(seconds: 15));
          if (response.statusCode != 200) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            continue;
          }
          await for (final chunk in response.stream) {
            total += chunk.length;
            if (!running) break;
          }
        } catch (_) {
          if (running) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
        }
      }
    }

    var finalBytes = 0;
    try {
      for (var i = 0; i < streams; i++) {
        unawaited(worker());
      }
      await Future<void>.delayed(duration);
    } finally {
      running = false;
      finalBytes = total;
      timer.cancel();
      watch.stop();
      client.close();
    }

    if (finalBytes == 0) throw Exception('فشل اختبار التنزيل');
    final elapsed = watch.elapsedMilliseconds;
    final average = markMs >= 0 && elapsed > markMs
        ? (finalBytes - markBytes) * 8 / (elapsed - markMs) / 1000
        : finalBytes * 8 / elapsed / 1000;
    return SpeedResult(average: average, peak: peak < average ? average : peak);
  }

  /// رفع بعدة اتصالات متوازية لمدة محددة.
  static Future<SpeedResult> measureUpload({
    int streams = 4,
    Duration duration = const Duration(seconds: 8),
    void Function(double mbps)? onSpeed,
  }) async {
    final client = http.Client();
    final payload = Uint8List(1000000);
    var running = true;
    var total = 0;
    var peak = 0.0;
    var lastBytes = 0;
    var lastMs = 0;
    final watch = Stopwatch()..start();

    final timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final ms = watch.elapsedMilliseconds;
      final dt = ms - lastMs;
      if (dt <= 0) return;
      final mbps = (total - lastBytes) * 8 / dt / 1000;
      lastBytes = total;
      lastMs = ms;
      if (mbps > peak) peak = mbps;
      onSpeed?.call(mbps);
    });

    Future<void> worker() async {
      while (running) {
        try {
          final response = await client
              .post(
                Uri.parse(_up),
                headers: {'Content-Type': 'application/octet-stream'},
                body: payload,
              )
              .timeout(const Duration(seconds: 20));
          if (running &&
              response.statusCode >= 200 &&
              response.statusCode < 300) {
            total += payload.length;
          } else if (running) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
        } catch (_) {
          if (running) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
        }
      }
    }

    var finalBytes = 0;
    try {
      for (var i = 0; i < streams; i++) {
        unawaited(worker());
      }
      await Future<void>.delayed(duration);
    } finally {
      running = false;
      finalBytes = total;
      timer.cancel();
      watch.stop();
      client.close();
    }

    if (finalBytes == 0) throw Exception('فشل اختبار الرفع');
    final elapsed = watch.elapsedMilliseconds;
    final average = finalBytes * 8 / elapsed / 1000;
    return SpeedResult(average: average, peak: peak < average ? average : peak);
  }
}
