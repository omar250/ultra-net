import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'turbo_download.dart';

class TurboPage extends StatefulWidget {
  const TurboPage({super.key});

  @override
  State<TurboPage> createState() => _TurboPageState();
}

class _TurboPageState extends State<TurboPage> {
  final TextEditingController _urlController = TextEditingController();
  TurboDownloader? _downloader;

  int connections = 8;
  bool running = false;
  int received = 0;
  int total = 0;
  double speed = 0;
  double peak = 0;
  String status = 'الصق رابط تنزيل مباشر (https) وابدأ';
  TurboResult? result;

  @override
  void dispose() {
    _downloader?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  Future<void> _start() async {
    if (running) return;
    final uri = Uri.tryParse(_urlController.text.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      setState(() => status = 'أدخل رابط تنزيل مباشر يبدأ بـ https://');
      return;
    }
    setState(() {
      running = true;
      status = 'جارٍ التجهيز...';
      result = null;
      received = 0;
      total = 0;
      speed = 0;
      peak = 0;
    });
    final downloader = TurboDownloader(url: uri, connections: connections);
    _downloader = downloader;
    try {
      final r = await downloader.run((u) {
        if (!mounted) return;
        setState(() {
          received = u.received;
          total = u.total;
          speed = u.mbps;
          peak = u.peakMbps;
          status = 'جارٍ التنزيل عبر $connections اتصالاً متوازياً';
        });
      });
      if (!mounted) return;
      setState(() {
        result = r;
        status = 'اكتمل التنزيل بنجاح';
      });
    } on TurboCancelled {
      if (mounted) setState(() => status = 'تم إلغاء التنزيل');
    } catch (e) {
      if (mounted) {
        setState(() => status =
            'فشل التنزيل: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      _downloader = null;
      if (mounted) setState(() => running = false);
    }
  }

  void _cancel() => _downloader?.cancel();

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TURBO',
          style: TextStyle(
            color: Colors.cyanAccent,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.rocket_launch_rounded,
              color: Colors.cyanAccent, size: 70),
          const SizedBox(height: 10),
          const Text(
            'ينزّل الملف عبر عدة اتصالات متوازية ليستهلك أقصى ما يتيحه خطك. لا يتجاوز سرعة باقتك، لكنه يمنع الاتصال الواحد من أن يكون عنق الزجاجة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _urlController,
            enabled: !running,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'رابط التنزيل المباشر',
              hintText: 'https://example.com/file.zip',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          const Text('عدد الاتصالات المتوازية',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(value: 4, label: Text('4')),
              ButtonSegment<int>(value: 8, label: Text('8')),
              ButtonSegment<int>(value: 16, label: Text('16')),
            ],
            selected: {connections},
            onSelectionChanged: running
                ? null
                : (s) => setState(() => connections = s.first),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: running ? _cancel : _start,
              icon: Icon(running ? Icons.stop_rounded : Icons.bolt),
              label: Text(
                running ? 'إلغاء' : 'ابدأ التنزيل السريع',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (running || received > 0) ...[
            LinearProgressIndicator(
              value: total > 0 ? (received / total).clamp(0.0, 1.0) : null,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 10),
            _row('السرعة الحالية', '${speed.toStringAsFixed(1)} Mbps'),
            _row('أعلى سرعة', '${peak.toStringAsFixed(1)} Mbps'),
            _row('تم تنزيل',
                total > 0 ? '${_mb(received)} / ${_mb(total)} MB' : '${_mb(received)} MB'),
          ],
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.cyanAccent),
              ),
            ),
          ),
          if (r != null) ...[
            const SizedBox(height: 8),
            _row('المتوسط', '${r.averageMbps.toStringAsFixed(1)} Mbps'),
            _row('الزمن', '${r.seconds.toStringAsFixed(1)} ث'),
            const SizedBox(height: 6),
            SelectableText(
              r.path,
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: r.path));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ مسار الملف')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('نسخ مسار الملف'),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'ملاحظات: الرابط يجب أن يكون مباشراً وبصيغة https، والخادم يجب أن يدعم Range لتفعيل التسريع (وإلا يُنزَّل باتصال واحد). الملفات تُحفظ في مجلد التطبيق. بعض المواقع تحدّ من عدد الاتصالات، فإن فشل التنزيل جرّب 4.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _row(String title, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(title)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
