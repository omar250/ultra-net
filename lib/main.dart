import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import 'boost_page.dart';
import 'speed_engine.dart';
import 'turbo_page.dart';

void main() => runApp(const UltraNetApp());

class UltraNetApp extends StatelessWidget {
  const UltraNetApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ULTRA NET',
        debugShowCheckedModeBanner: false,
        // التطبيق عربي: اتجاه من اليمين لليسار
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
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
  String peakSpeed = '--';
  String liveSpeed = '--';
  String status = 'جاهز لفحص اتصالك';
  String hint = '';
  bool loading = false;
  int? lastPing;
  double? lastDownload;

  @override
  void initState() {
    super.initState();
    checkNetwork();
    _subscription = _connectivity.onConnectivityChanged.listen(_updateNetwork);
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

  String _usageHint(double mbps) {
    if (mbps >= 100) {
      return 'ممتاز: يكفي لبث 4K وتنزيل الملفات الكبيرة بسرعة وعدة أجهزة معاً.';
    }
    if (mbps >= 25) {
      return 'جيد جداً: بث 4K ومكالمات فيديو وألعاب أونلاين بلا مشاكل.';
    }
    if (mbps >= 8) {
      return 'جيد: بث HD ومكالمات فيديو وتصفح سلس.';
    }
    if (mbps >= 3) {
      return 'متوسط: بث بجودة عادية وتصفح، وقد تتأثر مكالمات الفيديو.';
    }
    return 'ضعيف: يصلح للتصفح الخفيف والرسائل فقط. اقترب من الراوتر أو بدّل الشبكة.';
  }

  Future<void> testSpeed() async {
    if (loading) return;
    setState(() {
      loading = true;
      ping = '...';
      downloadSpeed = '...';
      uploadSpeed = '...';
      peakSpeed = '--';
      liveSpeed = '--';
      hint = '';
      status = 'جارٍ قياس زمن الاستجابة';
    });

    try {
      final measuredPing = await SpeedEngine.measurePing();
      if (!mounted) return;
      setState(() {
        ping = '$measuredPing ms';
        lastPing = measuredPing;
        status = 'جارٍ قياس سرعة التنزيل (اتصالات متوازية)';
      });

      final download = await SpeedEngine.measureDownload(
        onSpeed: (mbps) {
          if (mounted) {
            setState(() => liveSpeed = '${mbps.toStringAsFixed(1)} Mbps');
          }
        },
      );
      if (!mounted) return;
      setState(() {
        downloadSpeed = '${download.average.toStringAsFixed(2)} Mbps';
        peakSpeed = '${download.peak.toStringAsFixed(2)} Mbps';
        lastDownload = download.average;
        status = 'جارٍ قياس سرعة الرفع';
        liveSpeed = '--';
      });

      final upload = await SpeedEngine.measureUpload(
        onSpeed: (mbps) {
          if (mounted) {
            setState(() => liveSpeed = '${mbps.toStringAsFixed(1)} Mbps');
          }
        },
      );
      if (!mounted) return;
      setState(() {
        uploadSpeed = '${upload.average.toStringAsFixed(2)} Mbps';
        liveSpeed = '--';
        status = 'اكتمل اختبار السرعة';
        hint = _usageHint(download.average);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        status = 'تعذر إكمال الاختبار. تحقق من الإنترنت وحاول مجدداً.';
        if (ping == '...') ping = '--';
        if (downloadSpeed == '...') downloadSpeed = '--';
        if (uploadSpeed == '...') uploadSpeed = '--';
        liveSpeed = '--';
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
            const Icon(Icons.speed_rounded, color: Colors.cyanAccent, size: 82),
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
            _infoCard('أعلى سرعة وصلت لها', peakSpeed, Icons.trending_up),
            _infoCard('سرعة الرفع', uploadSpeed, Icons.upload_rounded),
            if (loading)
              _infoCard('السرعة اللحظية', liveSpeed, Icons.flash_on_rounded),
            const SizedBox(height: 10),
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
                  style:
                      const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: loading
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BoostPage(
                              network: network,
                              pingMs: lastPing,
                              downloadMbps: lastDownload,
                            ),
                          ),
                        ),
                icon: const Icon(Icons.phone_android_rounded),
                label: const Text(
                  'تحسين الهاتف كله',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: loading
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const TurboPage()),
                        ),
                icon: const Icon(Icons.rocket_launch_rounded),
                label: const Text(
                  'Turbo: تنزيل سريع لملف',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
            if (hint.isNotEmpty) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.5),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'تنبيه: التطبيق يقيس أداء الاتصال ولا يستطيع تجاوز السرعة التي توفرها شركة الإنترنت أو تقوية إشارة الشبكة من تلقاء نفسه. الاختبار يستهلك بيانات، فانتبه عند استخدام بيانات الهاتف.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      );

  Widget _infoCard(String title, String value, IconData icon) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF14213A),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.cyan.withValues(alpha: 0.24)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.cyanAccent, size: 28),
            const SizedBox(width: 13),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
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
