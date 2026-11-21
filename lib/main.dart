
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const UltraNetApp());
}

class UltraNetApp extends StatelessWidget {
  const UltraNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080D1C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String network = 'جارٍ الفحص';
  String ping = '--';
  String speed = '--';
  bool loading = false;

  @override
  void initState() {
    super.initState();
    checkNetwork();
  }

  Future<void> checkNetwork() async {
    final result = await Connectivity().checkConnectivity();

    if (!mounted) return;

    setState(() {
      if (result.contains(ConnectivityResult.wifi)) {
        network = 'Wi-Fi';
      } else if (result.contains(ConnectivityResult.mobile)) {
        network = 'Mobile Data';
      } else {
        network = 'غير متصل';
      }
    });
  }

  Future<void> testSpeed() async {
    setState(() {
      loading = true;
      ping = '...';
      speed = '...';
    });

    try {
      final watch = Stopwatch()..start();

      final response = await http.get(
        Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'),
      ).timeout(const Duration(seconds: 15));

      watch.stop();

      if (response.statusCode != 200) {
        throw Exception('Connection failed');
      }

      final measuredPing = watch.elapsedMilliseconds;

      final downloadWatch = Stopwatch()..start();

      final downloadResponse = await http.get(
        Uri.parse(
          'https://speed.cloudflare.com/__down?bytes=1000000',
        ),
      ).timeout(const Duration(seconds: 30));

      downloadWatch.stop();

      if (downloadResponse.statusCode != 200 ||
          downloadWatch.elapsedMilliseconds == 0) {
        throw Exception('Speed test failed');
      }

      final mbps = downloadResponse.bodyBytes.length *
          8 /
          1000000 /
          (downloadWatch.elapsedMilliseconds / 1000);

      if (!mounted) return;

      setState(() {
        ping = '$measuredPing ms';
        speed = '${mbps.toStringAsFixed(2)} Mbps';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        ping = '--';
        speed = 'تعذر القياس';
      });
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ULTRA NET',
          style: TextStyle(
            color: Colors.cyanAccent,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 25),
          const Icon(
            Icons.speed,
            color: Colors.cyanAccent,
            size: 90,
          ),
          const SizedBox(height: 15),
          const Center(
            child: Text(
              'INTERNET BOOSTER',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 25),
          card('حالة الاتصال', network, Icons.wifi),
          card('زمن الاستجابة', ping, Icons.timer),
          card('سرعة التنزيل', speed, Icons.download),
          const SizedBox(height: 25),
          SizedBox(
            height: 58,
            child: ElevatedButton.icon(
              onPressed: loading ? null : testSpeed,
              icon: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.bolt),
              label: Text(
                loading ? 'جارٍ الاختبار...' : 'اختبار سرعة الإنترنت',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(height: 25),
          const Text(
            'ULTRA NET يساعدك على فحص اتصالك وقياس سرعته.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          const Text(
            'ملاحظة: التطبيق يقيس جودة الاتصال ولا يستطيع تجاوز حدود سرعة شركة الإنترنت.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget card(String title, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF14213A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.cyan.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 30),
          const SizedBox(width: 15),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 16)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
