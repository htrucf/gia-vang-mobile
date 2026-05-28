import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'history_api.dart';
import 'models.dart';
import 'store.dart';

const Duration kRefreshEvery = Duration(minutes: 20);

const Map<String, Color> kSourceColors = {
  'SJC': Color(0xFFF5B301),
  'PNJ': Color(0xFF58A6FF),
  'DOJI': Color(0xFFF85149),
  'BTMC': Color(0xFF3FB950),
};

const Color kPanel = Color(0xFF161B22);
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
      theme: base.copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
      ),
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
  // iso: 2026-05-29T01:23:45+07:00 -> "01:23 29/05"
  if (iso.length < 16) return iso;
  final date = iso.substring(0, 10).split('-'); // [y,m,d]
  final hm = iso.substring(11, 16);
  return '$hm ${date[2]}/${date[1]}';
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
      // bieu do loi khong chan phan gia hien tai
    } finally {
      if (mounted) setState(() => _chartLoading = false);
    }
  }

  void _selectRange(ChartRange r) {
    if (r == _range) return;
    setState(() => _range = r);
    _loadCharts();
  }

  @override
  Widget build(BuildContext context) {
    final latest = _store.latest;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
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
      ),
      body: _booting
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  if (_error != null) _ErrorBanner(_error!),
                  if (latest == null && _error == null)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Đang tải dữ liệu…')),
                    ),
                  if (latest != null) ...[
                    _HeaderLine(latest),
                    const SizedBox(height: 8),
                    _UsdCard(latest.usd),
                    const SizedBox(height: 12),
                    for (final g in latest.gold) ...[
                      _GoldCard(g),
                      const SizedBox(height: 12),
                    ],
                    _RangeSelector(range: _range, onChanged: _selectRange),
                    const SizedBox(height: 12),
                    _ChartCard(
                      title: 'Vàng theo thời gian (triệu đ/lượng)',
                      child: _chartLoading && !_chartCache.containsKey(_range)
                          ? const _ChartLoading()
                          : _GoldChart(
                              _chartCache[_range]?.gold ?? const {},
                              note: _range == ChartRange.year
                                  ? 'Vàng: nguồn miễn phí chỉ có 30 ngày gần nhất'
                                  : null,
                            ),
                    ),
                    const SizedBox(height: 12),
                    _ChartCard(
                      title: 'USD/VND theo thời gian',
                      child: _chartLoading && !_chartCache.containsKey(_range)
                          ? const _ChartLoading()
                          : _UsdChart(_chartCache[_range]?.usd ?? const []),
                    ),
                  ],
                ],
              ),
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

class _GoldCard extends StatelessWidget {
  final GoldBlock g;
  const _GoldCard(this.g);

  @override
  Widget build(BuildContext context) {
    final color = kSourceColors[g.source] ?? Colors.white;
    return Card(
      elevation: 0,
      color: kPanel,
      shape: kCardShape,
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: g.source == 'SJC',
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(g.source,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              const Spacer(),
              chgBadge(g.changePct),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4, left: 18),
            child: g.ok
                ? Text(
                    g.representative != null
                        ? 'Bán: ${groupVnd(g.representative)} đ/lượng'
                        : '${g.items.length} dòng',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  )
                : Text('Lỗi: ${g.error ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFF85149))),
          ),
          children: [
            if (g.ok && g.items.isNotEmpty) _goldTable(g),
          ],
        ),
      ),
    );
  }

  Widget _goldTable(GoldBlock g) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          const _GoldRow(name: 'Loại', buy: 'Mua', sell: 'Bán', header: true),
          const Divider(height: 8, color: Color(0xFF21262D)),
          for (final it in g.items)
            _GoldRow(
              name: it.name.isEmpty ? '—' : it.name,
              buy: groupVnd(it.buy),
              sell: groupVnd(it.sell),
            ),
        ],
      ),
    );
  }
}

class _GoldRow extends StatelessWidget {
  final String name;
  final String buy;
  final String sell;
  final bool header;
  const _GoldRow({
    required this.name,
    required this.buy,
    required this.sell,
    this.header = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12.5,
      color: header ? Colors.grey : Colors.white,
      fontWeight: header ? FontWeight.w700 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(name, style: style)),
          Expanded(
              flex: 3,
              child: Text(buy, textAlign: TextAlign.right, style: style)),
          Expanded(
              flex: 3,
              child: Text(sell, textAlign: TextAlign.right, style: style)),
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
            SizedBox(height: 210, child: child),
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
    final allY = <double>[];
    double? minX, maxX;
    DateTime? minT, maxT;
    kSourceColors.forEach((source, color) {
      final series = gold[source] ?? const [];
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
            lineTouchData: LineTouchData(enabled: false),
          )),
        ),
        const SizedBox(height: 6),
        _ChartFooter(minT: minT, maxT: maxT),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          children: [
            for (final e in kSourceColors.entries) _legendDot(e.key, e.value),
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
            lineTouchData: LineTouchData(enabled: false),
          )),
        ),
        const SizedBox(height: 6),
        _ChartFooter(minT: points.first.t, maxT: points.last.t),
      ],
    );
  }
}
