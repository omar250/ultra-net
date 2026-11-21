import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const UltraNetApp());

class UltraNetApp extends StatelessWidget {
  const UltraNetApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ULTRA NET',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF080D1C),
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.cyan,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  String network = 'جارٍ الفحص';
  String ping = '--';
  String downloadSpeed = '--';
  String uploadSpeed = '--';
  String preferredNetwork = 'auto';
  String status = 'جاهز لفحص اتصالك';
  bool loading = false;

  @override
  void initState() {
    super.initState();
    checkNetwork();
    _subscription =
        _connectivity.onConnectivityChanged.listen(_updateNetwork);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> checkNetwork() async {
    try {
      _updateNetwork(await _connectivity.checkConnectivity());
    } catch (_) {
      if (mounted) setState(() => network = 'تعذر تحديد الاتصال');
    }
  }

  void _updateNetwork(List<ConnectivityResult> result) {
    if (!mounted) return;
    setState(() {
      if (result.contains(ConnectivityResult.wifi)) {
        network = 'Wi-Fi';
      } else if (result.contains(ConnectivityResult.mobile)) {
        network = 'بيانات الهاتف';
      } else if (result.contains(ConnectivityResult.ethernet)) {
        network = 'اتصال سلكي';
      } else {
        network = 'غير متصل';
      }
    });
  }

  String get selectedNetworkLabel {
    switch (preferredNetwork) {
      case 'wifi':
        return 'Wi-Fi';
      case 'mobile':
        return 'بيانات الهاتف';
      default:
        return 'تلقائي';
    }
  }

  Future<int> _measurePing() async {
    final samples = <int>[];
    for (var i = 0; i < 3; i++) {
      final watch = Stopwatch()..start();
      final response = await http
          .get(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'))
          .timeout(const Duration(seconds: 12));
      watch.stop();
      if (response.statusCode == 200) {
        samples.add(watch.elapsedMilliseconds);
      }
    }
    if (samples.isEmpty) throw Exception('Ping test failed');
    samples.sort();
    return samples[samples.length ~/ 2];
  }

  Future<double> _measureDownload() async {
    const bytes = 5000000;
    final watch = Stopwatch()..start();
    final response = await http
        .get(Uri.parse('https://speed.cloudflare.com/__down?bytes=$bytes'))
        .timeout(const Duration(seconds: 40));
    watch.stop();
    if (response.statusCode != 200 || watch.elapsedMilliseconds == 0) {
      throw Exception('Download test failed');
    }
    return response.bodyBytes.length *
        8 /
        1000000 /
        (watch.elapsedMilliseconds / 1000);
  }

  Future<double> _measureUpload() async {
    const bytes = 500000;
    final watch = Stopwatch()..start();
    final response = await http
        .post(
          Uri.parse('https://speed.cloudflare.com/__up'),
          headers: {'Content-Type': 'application/octet-stream'},
          body: Uint8List(bytes),
        )
        .timeout(const Duration(seconds: 40));
    watch.stop();
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        watch.elapsedMilliseconds == 0) {
      throw Exception('Upload test failed');
    }
    return bytes * 8 / 1000000 / (watch.elapsedMilliseconds / 1000);
  }

  Future<void> testSpeed() async {
    if (loading) return;
    setState(() {
      loading = true;
      ping = '...';
      downloadSpeed = '...';
      uploadSpeed = '...';
      status = 'جارٍ قياس زمن الاستجابة';
    });

    try {
      final measuredPing = await _measurePing();
      if (!mounted) return;
      setState(() => status = 'جارٍ قياس سرعة التنزيل');

      final measuredDownload = await _measureDownload();
      if (!mounted) return;
      setState(() => status = 'جارٍ قياس سرعة الرفع');

      final measuredUpload = await _measureUpload();
      if (!mounted) return;

      setState(() {
        ping = '$measuredPing ms';
        downloadSpeed = measuredDownload.toStringAsFixed(2) + ' Mbps';
        uploadSpeed = measuredUpload.toStringAsFixed(2) + ' Mbps';
        status = 'اكتمل اختبار السرعة';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        status = 'تعذر إكمال الاختبار. تحقق من الإنترنت وحاول مجدداً.';
        if (ping == '...') ping = '--';
        if (downloadSpeed == '...') downloadSpeed = '--';
        if (uploadSpeed == '...') uploadSpeed = '--';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text(
            'ULTRA NET',
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
            const SizedBox(height: 12),
            const Icon(Icons.speed_rounded,
                color: Colors.cyanAccent, size: 82),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'اختبار وتحليل الإنترنت',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 22),
            _infoCard('الاتصال الحالي', network, Icons.network_check),
            _infoCard('زمن الاستجابة (Ping)', ping, Icons.timer_outlined),
            _infoCard('سرعة التنزيل', downloadSpeed, Icons.download_rounded),
            _infoCard('سرعة الرفع', uploadSpeed, Icons.upload_rounded),
            const SizedBox(height: 14),
            _sectionTitle('إعدادات الاتصال'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF14213A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.cyan.withOpacity(0.25)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: preferredNetwork,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'auto', child: Text('اختيار تلقائي')),
                    DropdownMenuItem(value: 'wifi', child: Text('Wi-Fi')),
                    DropdownMenuItem(
                        value: 'mobile', child: Text('بيانات الهاتف')),
                  ],
                  onChanged: loading
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => preferredNetwork = value);
                          }
                        },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'الوضع المحدد: $selectedNetworkLabel. تغيير الشبكة الفعلية يتم من إعدادات Android أو لوحة الاتصال السريع.',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 14),
            _infoCard('VPN', 'متوقف — لا يستخدم التطبيق VPN',
                Icons.shield_outlined),
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: loading ? null : testSpeed,
                icon: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bolt),
                label: Text(
                  loading ? 'جارٍ الاختبار...' : 'ابدأ اختبار السرعة',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.cyanAccent),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'تنبيه: التطبيق يقيس أداء الاتصال ولا يستطيع تجاوز السرعة التي توفرها شركة الإنترنت أو تقوية إشارة الشبكة من تلقاء نفسه.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white54, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      );

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      );

  Widget _infoCard(String title, String value, IconData icon) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF14213A),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.cyan.withOpacity(0.24)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.cyanAccent, size: 28),
            const SizedBox(width: 13),
            Expanded(
                child: Text(title, style: const TextStyle(fontSize: 15))),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
}
