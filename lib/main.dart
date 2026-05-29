import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'history_api.dart';
import 'models.dart';
import 'store.dart';

const Duration kRefreshEvery = Duration(minutes: 20);

// Mau cham theo thuong hieu (bang gia hien tai).
const Map<String, Color> kSourceColors = {
  'SJC': Color(0xFFF5B301),
  'PNJ': Color(0xFF58A6FF),
  'DOJI': Color(0xFFF85149),
  'BTMC': Color(0xFF3FB950),
  'BTMH': Color(0xFFA371F7),
};

// Mau 2 duong tren bieu do (khop ten voi kGoldTypeCode).
const Map<String, Color> kGoldLineColors = {
  'Vàng miếng SJC': Color(0xFFF5B301),
  'Nhẫn trơn 9999': Color(0xFF58A6FF),
};

const Color kPanel = Color(0xFF161B22);
const Color kBg = Color(0xFF0D1117);
final RoundedRectangleBorder kCardShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(14),
  side: const BorderSide(color: Color(0xFF21262D)),
);

void main() => runApp(const GiaVangApp());

class GiaVangApp extends StatelessWidget {
  const GiaVangApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'Giá vàng & USD',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(scaffoldBackgroundColor: kBg),
      home: const HomePage(),
    );
  }
}

String groupVnd(num? v) {
  if (v == null) return '—';
  final neg = v < 0;
  final s = v.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${neg ? '-' : ''}$buf';
}

String prettyTime(String iso) {
  if (iso.length < 16) return iso;
  final date = iso.substring(0, 10).split('-');
  final hm = iso.substring(11, 16);
  return '$hm ${date[2]}/${date[1]}';
}

// ── Loc san pham vang ────────────────────────────────────────────────────────

bool _isMiengSjc(String n, String src) {
  if (n.contains('miếng sjc')) return true;
  if (n.contains('sjc') &&
      (n.contains('1l') || n.contains('10l') || n.contains('1kg'))) {
    return true;
  }
  if (src == 'DOJI' && n.contains('hn lẻ')) return true; // DOJI niem yet mieng SJC
  return false;
}

bool _isNhanTron(String n, String src) {
  if (!n.contains('nhẫn')) return false;
  return n.contains('trơn') ||
      n.contains('99,99') ||
      n.contains('999.9') ||
      n.contains('99.99') ||
      n.contains('9999');
}

class BrandQuote {
  final String brand;
  final double? buy;
  final double? sell;
  final bool ok;
  final String? msg; // thong bao loi (khi !ok) de chan doan tren may that
  const BrandQuote(this.brand, {this.buy, this.sell, this.ok = true, this.msg});
}

/// Gom 1 san pham (miENG SJC / nhan tron) tu tat ca nguon -> 1 dong moi thuong hieu.
List<BrandQuote> _category(
    List<GoldBlock> blocks, bool Function(String name, String src) match) {
  final out = <BrandQuote>[];
  for (final b in blocks) {
    if (!b.ok) {
      // SJC bi Cloudflare chan tren may that; gia mieng SJC da co tu PNJ/DOJI/BTMC
      // nen bo qua dong loi SJC cho gon. Cac nguon khac van hien loi de chan doan.
      if (b.source == 'SJC') continue;
      out.add(BrandQuote(b.source,
          ok: false, msg: b.error?.replaceFirst('Exception: ', '')));
      continue;
    }
    for (final it in b.items) {
      if (match(it.name.toLowerCase(), b.source)) {
        out.add(BrandQuote(b.source, buy: it.buy, sell: it.sell));
        break;
      }
    }
  }
  return out;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _store = Store();
  Timer? _timer;
  bool _booting = true;
  bool _refreshing = false;
  String? _error;

  ChartRange _range = ChartRange.month;
  final Map<ChartRange, ChartData> _chartCache = {};
  bool _chartLoading = false;

  @override
  void initState() {
    super.initState();
    _boot();
    _timer = Timer.periodic(kRefreshEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    await _store.load();
    if (mounted) setState(() => _booting = false);
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await _store.refresh();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
    await _loadCharts(force: true);
  }

  Future<void> _loadCharts({bool force = false}) async {
    if (!force && _chartCache.containsKey(_range)) {
      if (mounted) setState(() {});
      return;
    }
    setState(() => _chartLoading = true);
    try {
      _chartCache[_range] = await fetchChartData(_range);
    } catch (_) {
      // loi bieu do khong chan gia hien tai
    } finally {
      if (mounted) setState(() => _chartLoading = false);
    }
  }

  void _selectRange(ChartRange r) {
    if (r == _range) return;
    setState(() => _range = r);
    _loadCharts();
  }

  bool get _chartBusy => _chartLoading && !_chartCache.containsKey(_range);

  @override
  Widget build(BuildContext context) {
    final latest = _store.latest;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: kBg,
          title: const Text('Giá vàng & USD',
              style: TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFF1F6FEB),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
            labelStyle: TextStyle(fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'Giá vàng'),
              Tab(text: 'USD'),
            ],
          ),
        ),
        body: _booting
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _goldTab(latest),
                  _usdTab(latest),
                ],
              ),
      ),
    );
  }

  Widget _goldTab(Snapshot? latest) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (_error != null) _ErrorBanner(_error!),
          if (latest == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Đang tải dữ liệu…')),
            )
          else ...[
            _HeaderLine(latest),
            const SizedBox(height: 12),
            _RangeSelector(range: _range, onChanged: _selectRange),
            const SizedBox(height: 12),
            _ChartCard(
              title: 'Giá vàng theo thời gian (triệu đ/lượng)',
              child: _chartBusy
                  ? const _ChartLoading()
                  : _GoldChart(
                      _chartCache[_range]?.gold ?? const {},
                      note: _range == ChartRange.year
                          ? 'Vàng: nguồn miễn phí chỉ có 30 ngày gần nhất'
                          : null,
                    ),
            ),
            const SizedBox(height: 12),
            _GoldSection(
              title: 'Vàng miếng SJC',
              accent: const Color(0xFFF5B301),
              quotes: _category(latest.gold, _isMiengSjc),
            ),
            const SizedBox(height: 12),
            _GoldSection(
              title: 'Nhẫn trơn 9999',
              accent: const Color(0xFF58A6FF),
              quotes: _category(latest.gold, _isNhanTron),
            ),
          ],
        ],
      ),
    );
  }

  Widget _usdTab(Snapshot? latest) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (_error != null) _ErrorBanner(_error!),
          if (latest == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Đang tải dữ liệu…')),
            )
          else ...[
            _HeaderLine(latest),
            const SizedBox(height: 8),
            _UsdCard(latest.usd),
            const SizedBox(height: 12),
            _RangeSelector(range: _range, onChanged: _selectRange),
            const SizedBox(height: 12),
            _ChartCard(
              title: 'USD/VND theo thời gian',
              child: _chartBusy
                  ? const _ChartLoading()
                  : _UsdChart(_chartCache[_range]?.usd ?? const []),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderLine extends StatelessWidget {
  final Snapshot snap;
  const _HeaderLine(this.snap);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.schedule, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        Text('Cập nhật ${prettyTime(snap.fetchedAt)}',
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String msg;
  const _ErrorBanner(this.msg);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x33F85149),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF85149)),
      ),
      child: Text('Lỗi cập nhật: $msg',
          style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 12)),
    );
  }
}

Widget chgBadge(double? pct) {
  if (pct == null) {
    return const Text('—', style: TextStyle(color: Colors.grey, fontSize: 12));
  }
  final flat = pct == 0;
  final up = pct > 0;
  final color = flat
      ? Colors.grey
      : (up ? const Color(0xFF3FB950) : const Color(0xFFF85149));
  final arrow = flat ? '▬' : (up ? '▲' : '▼');
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.16),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      '$arrow ${pct.abs().toStringAsFixed(2)}%',
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

class _UsdCard extends StatelessWidget {
  final UsdRate usd;
  const _UsdCard(this.usd);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: kPanel,
      shape: kCardShape,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('USD / VND',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    usd.ok ? groupVnd(usd.rate) : 'Lỗi',
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(usd.source,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            chgBadge(usd.changePct),
          ],
        ),
      ),
    );
  }
}

class _GoldSection extends StatelessWidget {
  final String title;
  final Color accent;
  final List<BrandQuote> quotes;
  const _GoldSection(
      {required this.title, required this.accent, required this.quotes});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: kPanel,
      shape: kCardShape,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            const _BrandRow(
                brand: 'Thương hiệu', buy: 'Mua', sell: 'Bán', header: true),
            const Divider(height: 10, color: Color(0xFF21262D)),
            if (quotes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Không có dữ liệu',
                    style: TextStyle(color: Colors.grey, fontSize: 12.5)),
              )
            else
              for (final q in quotes)
                _BrandRow(
                  brand: q.brand,
                  buy: q.ok ? groupVnd(q.buy) : (q.msg ?? 'nguồn lỗi'),
                  sell: q.ok ? groupVnd(q.sell) : '',
                  error: !q.ok,
                ),
          ],
        ),
      ),
    );
  }
}

class _BrandRow extends StatelessWidget {
  final String brand;
  final String buy;
  final String sell;
  final bool header;
  final bool error;
  const _BrandRow({
    required this.brand,
    required this.buy,
    required this.sell,
    this.header = false,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: 13,
      color: header
          ? Colors.grey
          : (error ? const Color(0xFFF85149) : Colors.white),
      fontWeight: header ? FontWeight.w700 : FontWeight.w500,
    );
    final dot = kSourceColors[brand];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                if (!header && dot != null) ...[
                  Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: dot, shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                ],
                Flexible(child: Text(brand, style: base)),
              ],
            ),
          ),
          if (error)
            Expanded(
              flex: 6,
              child: Text(buy,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: base),
            )
          else ...[
            Expanded(
                flex: 3,
                child: Text(buy, textAlign: TextAlign.right, style: base)),
            Expanded(
                flex: 3,
                child: Text(sell, textAlign: TextAlign.right, style: base)),
          ],
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: kPanel,
      shape: kCardShape,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey)),
            const SizedBox(height: 16),
            SizedBox(height: 220, child: child),
          ],
        ),
      ),
    );
  }
}

({double min, double max}) _yRange(Iterable<double> ys) {
  if (ys.isEmpty) return (min: 0.0, max: 1.0);
  var lo = ys.first, hi = ys.first;
  for (final y in ys) {
    if (y < lo) lo = y;
    if (y > hi) hi = y;
  }
  if (lo == hi) {
    final pad = lo == 0 ? 1 : lo.abs() * 0.01;
    return (min: lo - pad, max: hi + pad);
  }
  final pad = (hi - lo) * 0.08;
  return (min: lo - pad, max: hi + pad);
}

LineChartBarData _bar(List<FlSpot> spots, Color color) => LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.2,
      color: color,
      barWidth: 2,
      dotData: FlDotData(show: false),
    );

FlTitlesData _titles(String Function(double) fmtY) => FlTitlesData(
      rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 46,
          getTitlesWidget: (v, meta) => Text(
            fmtY(v),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ),
      ),
    );

FlGridData get _grid => FlGridData(
      show: true,
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) =>
          const FlLine(color: Color(0xFF21262D), strokeWidth: 1),
    );

// Tooltip khi cham vao bieu do: hien ngay + gia.
LineTouchData _touch({required bool millions}) => LineTouchData(
      enabled: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => const Color(0xFF010409),
        getTooltipItems: (spots) => List.generate(spots.length, (i) {
          final s = spots[i];
          final dt = DateTime.fromMillisecondsSinceEpoch(s.x.toInt());
          final val = millions ? '${s.y.toStringAsFixed(2)} tr' : groupVnd(s.y);
          final head = i == 0 ? '${_dm(dt)}  ' : '';
          return LineTooltipItem(
            '$head$val',
            TextStyle(
                color: s.bar.color ?? Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700),
          );
        }),
      ),
    );

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();
  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Chưa có dữ liệu cho khoảng này',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
}

class _ChartLoading extends StatelessWidget {
  const _ChartLoading();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(strokeWidth: 2));
}

class _RangeSelector extends StatelessWidget {
  final ChartRange range;
  final ValueChanged<ChartRange> onChanged;
  const _RangeSelector({required this.range, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final items = ChartRange.values;
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(child: _chip(items[i])),
          if (i != items.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _chip(ChartRange r) {
    final sel = r == range;
    return GestureDetector(
      onTap: () => onChanged(r),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF1F6FEB) : kPanel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: sel ? const Color(0xFF1F6FEB) : const Color(0xFF21262D)),
        ),
        child: Text(r.label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : Colors.grey)),
      ),
    );
  }
}

String _dm(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';

class _ChartFooter extends StatelessWidget {
  final DateTime? minT;
  final DateTime? maxT;
  const _ChartFooter({this.minT, this.maxT});

  @override
  Widget build(BuildContext context) {
    if (minT == null || maxT == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: Text('${_dm(minT!)} → ${_dm(maxT!)}',
          style: const TextStyle(fontSize: 10, color: Colors.grey)),
    );
  }
}

class _GoldChart extends StatelessWidget {
  final Map<String, List<SeriesPoint>> gold;
  final String? note;
  const _GoldChart(this.gold, {this.note});

  @override
  Widget build(BuildContext context) {
    final bars = <LineChartBarData>[];
    final present = <String, Color>{};
    final allY = <double>[];
    double? minX, maxX;
    DateTime? minT, maxT;
    kGoldLineColors.forEach((label, color) {
      final series = gold[label] ?? const [];
      if (series.length < 2) return;
      final spots = <FlSpot>[];
      for (final p in series) {
        final x = p.t.millisecondsSinceEpoch.toDouble();
        final y = p.v / 1e6;
        spots.add(FlSpot(x, y));
        allY.add(y);
        if (minX == null || x < minX!) minX = x;
        if (maxX == null || x > maxX!) maxX = x;
        if (minT == null || p.t.isBefore(minT!)) minT = p.t;
        if (maxT == null || p.t.isAfter(maxT!)) maxT = p.t;
      }
      bars.add(_bar(spots, color));
      present[label] = color;
    });
    if (bars.isEmpty) return const _EmptyChart();
    final r = _yRange(allY);
    return Column(
      children: [
        Expanded(
          child: LineChart(LineChartData(
            minY: r.min,
            maxY: r.max,
            minX: minX,
            maxX: maxX,
            lineBarsData: bars,
            titlesData: _titles((v) => v.toStringAsFixed(1)),
            gridData: _grid,
            borderData: FlBorderData(show: false),
            lineTouchData: _touch(millions: true),
          )),
        ),
        const SizedBox(height: 6),
        _ChartFooter(minT: minT, maxT: maxT),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final e in present.entries) _legendDot(e.key, e.value),
          ],
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(note!,
                style: const TextStyle(fontSize: 11, color: Color(0xFFD29922))),
          ),
      ],
    );
  }

  Widget _legendDot(String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 9,
              height: 9,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );
}

class _UsdChart extends StatelessWidget {
  final List<SeriesPoint> points;
  const _UsdChart(this.points);

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const _EmptyChart();
    final spots = <FlSpot>[];
    final allY = <double>[];
    for (final p in points) {
      spots.add(FlSpot(p.t.millisecondsSinceEpoch.toDouble(), p.v));
      allY.add(p.v);
    }
    final r = _yRange(allY);
    return Column(
      children: [
        Expanded(
          child: LineChart(LineChartData(
            minY: r.min,
            maxY: r.max,
            minX: points.first.t.millisecondsSinceEpoch.toDouble(),
            maxX: points.last.t.millisecondsSinceEpoch.toDouble(),
            lineBarsData: [_bar(spots, const Color(0xFF58A6FF))],
            titlesData: _titles((v) => v.toStringAsFixed(0)),
            gridData: _grid,
            borderData: FlBorderData(show: false),
            lineTouchData: _touch(millions: false),
          )),
        ),
        const SizedBox(height: 6),
        _ChartFooter(minT: points.first.t, maxT: points.last.t),
      ],
    );
  }
}
