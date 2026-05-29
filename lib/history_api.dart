// Nguon lich su that (free, khong can key):
//   - USD/VND: Yahoo Finance chart API (VND=X) -> toi 1 nam+.
//   - Vang VN: vang.today /api/prices?type=..&days=n -> TOI DA 30 ngay.
// Dung cho bieu do theo khoang thoi gian. Khac voi fetchers.dart (gia hien tai).

import 'dart:convert';
import 'package:http/http.dart' as http;

enum ChartRange { week, month, year }

extension ChartRangeX on ChartRange {
  String get label => switch (this) {
        ChartRange.week => '7 ngày',
        ChartRange.month => '30 ngày',
        ChartRange.year => '1 năm',
      };
}

class SeriesPoint {
  final DateTime t;
  final double v;
  const SeriesPoint(this.t, this.v);
}

/// % thay doi giua diem moi nhat va diem gan 24h truoc (cung 1 series bieu do).
/// Lay thang tu nguon (webgia/vang.today/Yahoo) -> co ngay, khong can app chay
/// du 1 ngay nhu lich su tu tich luy. Series phai sort tang dan theo thoi gian.
double? dayChangePct(List<SeriesPoint> series) {
  if (series.length < 2) return null;
  final last = series.last;
  final cutoff = last.t.subtract(const Duration(hours: 24));
  SeriesPoint? base;
  for (final p in series) {
    if (p.t.isAfter(cutoff)) break; // da qua moc 24h truoc
    base = p;
  }
  base ??= series.first;
  if (identical(base, last) || base.v == 0) return null;
  return double.parse(((last.v - base.v) / base.v * 100).toStringAsFixed(2));
}

// San pham -> ma type cua vang.today.
//   SJL1L10  = "SJC 9999"  (vang mieng SJC)
//   PQHN24NTT= "PNJ 24K"   (nhan tron 9999, dai dien)
const Map<String, String> kGoldTypeCode = {
  'Vàng miếng SJC': 'SJL1L10',
  'Nhẫn trơn 9999': 'PQHN24NTT',
};

const Map<String, String> _ua = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/124.0.0.0 Mobile Safari/537.36',
};

// ── USD: Yahoo Finance ────────────────────────────────────────────────────────

String _yahooParams(ChartRange r) => switch (r) {
      ChartRange.week => 'range=5d&interval=60m',
      ChartRange.month => 'range=1mo&interval=1d',
      ChartRange.year => 'range=1y&interval=1d',
    };

Future<List<SeriesPoint>> fetchUsdSeries(http.Client c, ChartRange r) async {
  final url =
      'https://query1.finance.yahoo.com/v8/finance/chart/VND=X?${_yahooParams(r)}';
  final resp = await c.get(Uri.parse(url), headers: _ua);
  if (resp.statusCode != 200) throw Exception('USD HTTP ${resp.statusCode}');
  final j = jsonDecode(resp.body) as Map<String, dynamic>;
  final results = (j['chart'] as Map<String, dynamic>?)?['result'] as List?;
  if (results == null || results.isEmpty) throw Exception('USD: thieu result');
  final result = results.first as Map<String, dynamic>;
  final ts = (result['timestamp'] as List?) ?? const [];
  final quoteList =
      (result['indicators'] as Map<String, dynamic>?)?['quote'] as List?;
  final quote =
      (quoteList != null && quoteList.isNotEmpty) ? quoteList.first as Map<String, dynamic> : null;
  final closes = (quote?['close'] as List?) ?? const [];
  final out = <SeriesPoint>[];
  for (var i = 0; i < ts.length && i < closes.length; i++) {
    final close = closes[i];
    if (close == null) continue;
    out.add(SeriesPoint(
      DateTime.fromMillisecondsSinceEpoch((ts[i] as num).toInt() * 1000),
      (close as num).toDouble(),
    ));
  }
  return out;
}

// ── Gold: vang.today ────────────────────────────────────────────────────────────

int goldMaxDays = 30; // gioi han cua nguon free

int _goldDays(ChartRange r) => r == ChartRange.week ? 7 : goldMaxDays;

// ── Gold SJC: webgia.com (lich su 1 nam, nhung san trong HTML Highcharts) ─────────
// Trang bieu-do-1-nam nhung series "Bán ra" dang [[ms, gia_trieu], ...] ngay trong
// HTML. 1 lan tai (~94KB) du cho ca 7/30/365 ngay -> vuot gioi han 30 ngay cua
// vang.today cho vang mieng SJC.
List<SeriesPoint>? _webgiaSjc;
DateTime? _webgiaSjcAt;

Future<List<SeriesPoint>> _fetchWebgiaSjcYear(http.Client c) async {
  final cached = _webgiaSjc;
  if (cached != null &&
      _webgiaSjcAt != null &&
      DateTime.now().difference(_webgiaSjcAt!).inMinutes < 30) {
    return cached;
  }
  final resp = await c.get(
    Uri.parse('https://webgia.com/gia-vang/sjc/bieu-do-1-nam.html'),
    headers: _ua,
  );
  if (resp.statusCode != 200) throw Exception('webgia HTTP ${resp.statusCode}');
  final html = utf8.decode(resp.bodyBytes);
  final start = html.indexOf('name:"Bán ra"');
  if (start < 0) throw Exception('webgia: khong thay series Ban ra');
  final end = html.indexOf(',tooltip', start);
  final body = end > start ? html.substring(start, end) : html.substring(start);
  final out = <SeriesPoint>[];
  for (final m in RegExp(r'\[(\d{10,}),([0-9.]+)\]').allMatches(body)) {
    final ms = int.tryParse(m.group(1)!);
    final v = double.tryParse(m.group(2)!);
    if (ms == null || v == null) continue;
    // trieu d/luong -> d/luong (khop chart: y = v / 1e6).
    out.add(SeriesPoint(DateTime.fromMillisecondsSinceEpoch(ms), v * 1e6));
  }
  if (out.isEmpty) throw Exception('webgia: khong parse duoc diem nao');
  out.sort((a, b) => a.t.compareTo(b.t));
  _webgiaSjc = out;
  _webgiaSjcAt = DateTime.now();
  return out;
}

List<SeriesPoint> _sliceRange(List<SeriesPoint> all, ChartRange r) {
  if (all.isEmpty) return all;
  final days = switch (r) {
    ChartRange.week => 7,
    ChartRange.month => 30,
    ChartRange.year => 366,
  };
  final from = all.last.t.subtract(Duration(days: days));
  return all.where((p) => !p.t.isBefore(from)).toList();
}

Future<List<SeriesPoint>> fetchGoldSeries(
    http.Client c, String typeKey, ChartRange r) async {
  if (typeKey == 'Vàng miếng SJC') {
    return _sliceRange(await _fetchWebgiaSjcYear(c), r);
  }
  final code = kGoldTypeCode[typeKey];
  if (code == null) return const [];
  final url = 'https://www.vang.today/api/prices?type=$code&days=${_goldDays(r)}';
  final resp = await c.get(Uri.parse(url),
      headers: {..._ua, 'Accept': 'application/json'});
  if (resp.statusCode != 200) throw Exception('$typeKey HTTP ${resp.statusCode}');
  final j = jsonDecode(resp.body) as Map<String, dynamic>;
  final hist = (j['history'] as List?) ?? const [];
  final out = <SeriesPoint>[];
  for (final row in hist) {
    final m = row as Map<String, dynamic>;
    final dateStr = m['date']?.toString();
    if (dateStr == null) continue;
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) continue;
    final prices = m['prices'] as Map<String, dynamic>?;
    if (prices == null || prices.isEmpty) continue;
    final p = (prices[code] ?? prices.values.first) as Map<String, dynamic>?;
    final sell = (p?['sell'] as num?)?.toDouble() ?? (p?['buy'] as num?)?.toDouble();
    if (sell == null) continue;
    out.add(SeriesPoint(dt, sell));
  }
  out.sort((a, b) => a.t.compareTo(b.t));
  return out;
}

/// Tat ca du lieu bieu do cho 1 khoang thoi gian.
class ChartData {
  final List<SeriesPoint> usd;
  final Map<String, List<SeriesPoint>> gold; // san pham -> series
  const ChartData({required this.usd, required this.gold});
}

Future<ChartData> fetchChartData(ChartRange r) async {
  final c = http.Client();
  try {
    final usdFut = fetchUsdSeries(c, r).catchError((_) => <SeriesPoint>[]);
    final goldFuts = <String, Future<List<SeriesPoint>>>{
      for (final s in kGoldTypeCode.keys)
        s: fetchGoldSeries(c, s, r).catchError((_) => <SeriesPoint>[]),
    };
    final usd = await usdFut;
    final gold = <String, List<SeriesPoint>>{};
    for (final e in goldFuts.entries) {
      gold[e.key] = await e.value;
    }
    return ChartData(usd: usd, gold: gold);
  } finally {
    c.close();
  }
}
