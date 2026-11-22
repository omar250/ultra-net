import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class _Dns {
  const _Dns(this.name, this.host, this.url);

  final String name;
  final String host;
  final String url;
}

const _providers = [
  _Dns('Cloudflare', 'one.one.one.one',
      'https://cloudflare-dns.com/dns-query?name=example.com&type=A'),
  _Dns('Google', 'dns.google',
      'https://dns.google/resolve?name=example.com&type=A'),
  _Dns('Quad9', 'dns.quad9.net',
      'https://dns.quad9.net:5053/dns-query?name=example.com&type=A'),
];

class BoostPage extends StatefulWidget {
  const BoostPage({
    super.key,
    required this.network,
    this.pingMs,
    this.downloadMbps,
  });

  final String network;
  final int? pingMs;
  final double? downloadMbps;

  @override
  State<BoostPage> createState() => _BoostPageState();
}

class _BoostPageState extends State<BoostPage> {
  final Map<String, int?> results = {};
  bool testing = false;
  _Dns? best;

  Future<int?> _measure(_Dns p) async {
    final client = http.Client();
    try {
      final uri = Uri.parse(p.url);
      const headers = {'accept': 'application/dns-json'};
      await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 6));
      final samples = <int>[];
      for (var i = 0; i < 4; i++) {
        final watch = Stopwatch()..start();
        try {
          final r = await client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 5));
          watch.stop();
          if (r.statusCode == 200) samples.add(watch.elapsedMilliseconds);
        } catch (_) {}
      }
      if (samples.isEmpty) return null;
      samples.sort();
      return samples[samples.length ~/ 2];
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> _benchmark() async {
    if (testing) return;
    setState(() {
      testing = true;
      results.clear();
      best = null;
    });
    _Dns? winner;
    int? winnerMs;
    for (final p in _providers) {
      final ms = await _measure(p);
      if (!mounted) return;
      setState(() => results[p.name] = ms);
      if (ms != null && (winnerMs == null || ms < winnerMs)) {
        winner = p;
        winnerMs = ms;
      }
    }
    if (!mounted) return;
    setState(() {
      best = winner;
      testing = false;
    });
  }

  Future<void> _open(String action) async {
    try {
      await AndroidIntent(action: action).launch();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح هذه الصفحة على هاتفك، افتحها يدوياً من الإعدادات')),
      );
    }
  }

  List<String> _diagnosis() {
    final out = <String>[];
    final ping = widget.pingMs;
    final down = widget.downloadMbps;
    if (ping == null || down == null) {
      return ['أجرِ "اختبار السرعة" من الصفحة الرئيسية أولاً لأعطيك تشخيصاً مخصصاً لاتصالك.'];
    }
    if (ping > 150) {
      out.add('زمن الاستجابة مرتفع ($ping ms): الإشارة ضعيفة أو الشبكة مزدحمة. غيّر مكانك أو جرّب في وقت آخر.');
    } else if (ping > 80) {
      out.add('زمن الاستجابة متوسط ($ping ms): قد تلاحظ بطئاً في فتح المواقع.');
    } else {
      out.add('زمن الاستجابة جيد ($ping ms).');
    }
    if (widget.network == 'Wi-Fi') {
      if (down < 10) {
        out.add('سرعة الواي فاي منخفضة (${down.toStringAsFixed(1)} Mbps): اقترب من الراوتر وجرّب شبكة 5GHz. إن بقيت منخفضة قرب الراوتر فالمشكلة من الباقة أو المزود.');
      }
    } else if (widget.network == 'بيانات الهاتف') {
      out.add('أنت على بيانات الهاتف: جرّب الواي فاي إن توفر، أو شغّل وضع الطيران 10 ثوانٍ لإعادة التسجيل على أفضل برج.');
    }
    if (down >= 25 && ping <= 80) {
      out.add('اتصالك جيد؛ إن كان تطبيق معين بطيئاً فالسبب غالباً من خادمه أو من DNS (قارن أدناه).');
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تحسين الهاتف كله',
          style: TextStyle(
              color: Colors.cyanAccent, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'هذه الصفحة تزيل العوائق التي تبطّئ كل التطبيقات والمتصفحات. لا يمكن لأي تطبيق رفع سرعة باقتك نفسها.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          _title('1) تشخيص اتصالك'),
          for (final line in _diagnosis())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('• $line', style: const TextStyle(height: 1.5)),
            ),
          const SizedBox(height: 14),
          _title('2) أسرع DNS لجميع التطبيقات'),
          const Text(
            'الـ DNS يحدد سرعة فتح المواقع والتطبيقات. قارن المزودين ثم فعّل الأسرع في إعدادات الهاتف ليعمل على كل شيء.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: testing ? null : _benchmark,
              icon: testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.dns_rounded),
              label: Text(testing ? 'جارٍ المقارنة...' : 'قارن مزودي DNS'),
            ),
          ),
          const SizedBox(height: 10),
          for (final p in _providers)
            if (results.containsKey(p.name))
              _dnsRow(p, results[p.name], best?.name == p.name),
          if (best != null) ...[
            const SizedBox(height: 10),
            Text(
              'الأسرع لك: ${best!.name}. لتفعيله على الهاتف كله:\n'
              'الإعدادات ← الشبكة والإنترنت (أو الاتصال والمشاركة) ← DNS الخاص (Private DNS) ← اسم مضيف مزود DNS الخاص ← الصق الاسم واحفظ.',
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: best!.host));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم نسخ ${best!.host}')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: Text('نسخ ${best!.host}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _open('android.settings.WIRELESS_SETTINGS'),
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('فتح إعدادات الشبكة'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          _title('3) اختصارات الإعدادات المؤثرة'),
          _shortcut('استهلاك البيانات لكل تطبيق (اعرف من يسحب سرعتك)',
              Icons.data_usage_rounded, 'android.settings.DATA_USAGE_SETTINGS'),
          _shortcut('إعدادات Wi-Fi (اختر شبكة 5GHz)', Icons.wifi_rounded,
              'android.settings.WIFI_SETTINGS'),
          _shortcut('وضع توفير الطاقة (يبطّئ الشبكة، أوقفه عند الحاجة)',
              Icons.battery_saver_rounded,
              'android.settings.BATTERY_SAVER_SETTINGS'),
          const SizedBox(height: 14),
          _title('4) قائمة تحقق سريعة'),
          const Text(
            '• أوقف توفير البيانات (Data Saver) أثناء الحاجة للسرعة.\n'
            '• أوقف التحديثات التلقائية والمزامنة في الخلفية أثناء التنزيل.\n'
            '• ابتعد عن الجدران وقرّب الهاتف من الراوتر.\n'
            '• ابحث في إعدادات هاتفك عن ميزة دمج الواي فاي والبيانات (مثل Download Booster في سامسونج أو تسريع الشبكة المزدوجة في بعض هواتف شاومي) إن كانت متوفرة.\n'
            '• على البيانات: وضع الطيران 10 ثوانٍ يعيد الاتصال بأفضل برج.',
            style: TextStyle(height: 1.7),
          ),
        ],
      ),
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );

  Widget _dnsRow(_Dns p, int? ms, bool isBest) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF14213A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isBest
                ? Colors.greenAccent
                : Colors.cyan.withValues(alpha: 0.24),
          ),
        ),
        child: Row(
          children: [
            Expanded(child: Text(p.name)),
            Text(
              ms == null ? 'غير متاح' : '$ms ms',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (isBest) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
            ],
          ],
        ),
      );

  Widget _shortcut(String title, IconData icon, String action) => Card(
        color: const Color(0xFF14213A),
        child: ListTile(
          leading: Icon(icon, color: Colors.cyanAccent),
          title: Text(title, style: const TextStyle(fontSize: 14)),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: () => _open(action),
        ),
      );
}
