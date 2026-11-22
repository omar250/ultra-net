import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class TurboCancelled implements Exception {
  const TurboCancelled();

  @override
  String toString() => 'تم إلغاء التنزيل';
}

class TurboUpdate {
  const TurboUpdate({
    required this.received,
    required this.total,
    required this.mbps,
    required this.peakMbps,
  });

  final int received;
  final int total;
  final double mbps;
  final double peakMbps;
}

class TurboResult {
  const TurboResult({
    required this.path,
    required this.bytes,
    required this.seconds,
    required this.averageMbps,
    required this.peakMbps,
  });

  final String path;
  final int bytes;
  final double seconds;
  final double averageMbps;
  final double peakMbps;
}

/// منزّل متعدد الاتصالات: يقسم الملف إلى أجزاء ويحمّلها بالتوازي (HTTP Range).
class TurboDownloader {
  TurboDownloader({required this.url, this.connections = 8});

  final Uri url;
  final int connections;

  static const _headers = {'User-Agent': 'UltraNet/1.1'};

  bool _cancelled = false;
  bool _stop = false;
  http.Client? _client;

  void cancel() {
    _cancelled = true;
    _stop = true;
    _client?.close();
  }

  String _fileName() {
    var name = url.pathSegments.isNotEmpty ? url.pathSegments.last : '';
    try {
      name = Uri.decodeComponent(name);
    } catch (_) {}
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (name.isEmpty) {
      name = 'download_${DateTime.now().millisecondsSinceEpoch}';
    }
    return name;
  }

  Future<String> _targetPath() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/UltraNet');
    await dir.create(recursive: true);
    final name = _fileName();
    var path = '${dir.path}/$name';
    if (await File(path).exists()) {
      path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$name';
    }
    return path;
  }

  int? _parseTotal(String? contentRange) {
    if (contentRange == null) return null;
    final slash = contentRange.lastIndexOf('/');
    if (slash < 0) return null;
    return int.tryParse(contentRange.substring(slash + 1).trim());
  }

  int _chunkSize(int total) {
    final target = (total / (connections * 4)).ceil();
    return max(512 * 1024, min(4 * 1024 * 1024, target));
  }

  Future<TurboResult> run(void Function(TurboUpdate update) onUpdate) async {
    final client = http.Client();
    _client = client;
    File? file;
    RandomAccessFile? opened;
    Timer? timer;
    var received = 0;
    var totalSize = 0;
    var peak = 0.0;
    final watch = Stopwatch()..start();

    try {
      // 1) فحص دعم Range ومعرفة حجم الملف
      final probe = http.Request('GET', url)
        ..headers.addAll({..._headers, 'Range': 'bytes=0-0'});
      final probeRes =
          await client.send(probe).timeout(const Duration(seconds: 20));
      if (_cancelled) throw const TurboCancelled();
      if (probeRes.statusCode != 200 && probeRes.statusCode != 206) {
        throw Exception('الخادم رد بالرمز ${probeRes.statusCode}');
      }
      final ranged = probeRes.statusCode == 206;
      if (ranged) {
        totalSize = _parseTotal(probeRes.headers['content-range']) ?? 0;
        if (totalSize <= 0) throw Exception('تعذر معرفة حجم الملف');
        await probeRes.stream.drain<void>();
      } else {
        totalSize = probeRes.contentLength ?? 0;
      }

      // 2) تجهيز الملف
      final path = await _targetPath();
      file = File(path);
      final raf = await file.open(mode: FileMode.write);
      opened = raf;
      if (ranged) await raf.truncate(totalSize);

      var lastBytes = 0;
      var lastMs = 0;
      timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        final ms = watch.elapsedMilliseconds;
        final dt = ms - lastMs;
        if (dt <= 0) return;
        final mbps = (received - lastBytes) * 8 / dt / 1000;
        lastBytes = received;
        lastMs = ms;
        if (mbps > peak) peak = mbps;
        onUpdate(TurboUpdate(
          received: received,
          total: totalSize,
          mbps: mbps,
          peakMbps: peak,
        ));
      });

      if (!ranged) {
        // الخادم لا يدعم Range: اتصال واحد
        await for (final chunk in probeRes.stream) {
          if (_cancelled) throw const TurboCancelled();
          await raf.writeFrom(chunk);
          received += chunk.length;
        }
      } else {
        // 3) تنزيل الأجزاء بالتوازي
        var chain = Future<void>.value();
        Future<void> writeAt(int pos, List<int> data) {
          chain = chain.then((_) async {
            await raf.setPosition(pos);
            await raf.writeFrom(data);
          });
          return chain;
        }

        final chunkSize = _chunkSize(totalSize);
        final queue = <List<int>>[];
        for (var s = 0; s < totalSize; s += chunkSize) {
          queue.add([s, min(s + chunkSize - 1, totalSize - 1)]);
        }

        Future<void> worker() async {
          while (queue.isNotEmpty) {
            if (_stop) throw const TurboCancelled();
            final part = queue.removeAt(0);
            var pos = part[0];
            final end = part[1];
            var attempts = 0;
            while (pos <= end) {
              if (_stop) throw const TurboCancelled();
              final before = pos;
              try {
                final req = http.Request('GET', url)
                  ..headers.addAll({..._headers, 'Range': 'bytes=$pos-$end'});
                final res =
                    await client.send(req).timeout(const Duration(seconds: 20));
                if (res.statusCode != 206) {
                  throw Exception('الخادم رد بالرمز ${res.statusCode}');
                }
                await for (final data
                    in res.stream.timeout(const Duration(seconds: 20))) {
                  if (_stop) throw const TurboCancelled();
                  final remaining = end - pos + 1;
                  final piece =
                      data.length > remaining ? data.sublist(0, remaining) : data;
                  await writeAt(pos, piece);
                  pos += piece.length;
                  received += piece.length;
                  if (pos > end) break;
                }
                if (pos <= end && pos == before) {
                  throw Exception('رد فارغ من الخادم');
                }
              } on TurboCancelled {
                rethrow;
              } catch (_) {
                if (_stop) throw const TurboCancelled();
                attempts++;
                if (attempts >= 4) rethrow;
                await Future<void>.delayed(Duration(milliseconds: 400 * attempts));
              }
            }
          }
        }

        Future<void> guarded() async {
          try {
            await worker();
          } catch (_) {
            _stop = true;
            rethrow;
          }
        }

        final n = min(connections, queue.length);
        await Future.wait(
          [for (var i = 0; i < n; i++) guarded()],
          eagerError: true,
        );
        await chain;
        if (received < totalSize) throw Exception('التنزيل غير مكتمل');
      }

      await raf.flush();
      await raf.close();
      opened = null;
      timer.cancel();
      watch.stop();

      final seconds = max(watch.elapsedMilliseconds / 1000, 0.001);
      final bytes = received;
      final average = bytes * 8 / 1000000 / seconds;
      return TurboResult(
        path: path,
        bytes: bytes,
        seconds: seconds,
        averageMbps: average,
        peakMbps: max(peak, average),
      );
    } catch (_) {
      try {
        await opened?.close();
      } catch (_) {}
      try {
        await file?.delete();
      } catch (_) {}
      if (_cancelled) throw const TurboCancelled();
      rethrow;
    } finally {
      timer?.cancel();
      client.close();
      _client = null;
    }
  }
}
