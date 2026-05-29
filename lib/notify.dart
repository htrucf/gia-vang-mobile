// Thong bao chay nen khi gia ban vang mieng SJC giam >= 1% so voi lan truoc.
// foreground chi cap nhat moc (setLastSjcSell); task chay nen so sanh + bao.
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'fetchers.dart';

const String _kTask = 'sjc_drop_check';
const String _kPrefLastSell = 'notif_last_sjc_sell';
const double kDropThreshold = 0.01; // bao khi giam >= 1%

final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
bool _flnReady = false;

Future<void> _ensureFln() async {
  if (_flnReady) return;
  const init = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await _fln.initialize(init);
  _flnReady = true;
}

/// Goi 1 lan khi mo app: khoi tao plugin + xin quyen thong bao (Android 13+).
Future<void> initNotifications() async {
  await _ensureFln();
  await _fln
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

/// Dang ky task chay nen. Android gioi han toi thieu 15 phut; ta dat 30 phut.
Future<void> registerDropCheck() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _kTask,
    _kTask,
    frequency: const Duration(minutes: 30),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

String _fmt(double v) {
  final s = v.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

Future<void> _showDrop(double oldSell, double newSell) async {
  await _ensureFln();
  final pct = (oldSell - newSell) / oldSell * 100;
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'gold_drop',
      'Giá vàng giảm',
      channelDescription: 'Báo khi giá bán vàng miếng SJC giảm',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
  await _fln.show(
    1001,
    'Vàng SJC giảm ${pct.toStringAsFixed(2)}%',
    'Giá bán ${_fmt(newSell)} đ/lượng (trước ${_fmt(oldSell)})',
    details,
  );
}

/// Cap nhat moc 'lan truoc' (goi o foreground, khong thong bao).
Future<void> setLastSjcSell(double? sell) async {
  if (sell == null || sell <= 0) return;
  final p = await SharedPreferences.getInstance();
  await p.setDouble(_kPrefLastSell, sell);
}

/// So sanh voi lan truoc; neu giam >= nguong -> thong bao. Sau do luu moc moi.
Future<void> checkSjcDrop(double? sell) async {
  if (sell == null || sell <= 0) return;
  final p = await SharedPreferences.getInstance();
  final last = p.getDouble(_kPrefLastSell);
  if (last != null && last > 0 && sell <= last * (1 - kDropThreshold)) {
    await _showDrop(last, sell);
  }
  await p.setDouble(_kPrefLastSell, sell);
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    final c = http.Client();
    try {
      await checkSjcDrop(await fetchSjcMiengSell(c));
    } catch (_) {
    } finally {
      c.close();
    }
    return true;
  });
}
