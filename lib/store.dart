// Cache gia trong RAM + luu xuong shared_preferences (latest + history).
// Tinh % thay doi so voi 1 ngay truoc (~24h). Port tu app/store.py.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'fetchers.dart';
import 'models.dart';

const int _maxHistory = 1000; // ~13 ngay neu cap nhat moi 20 phut
const String _kLatest = 'latest';
const String _kHistory = 'history';

double? _representative(GoldBlock b) {
  // Uu tien gia ban mieng SJC (chi so headline + moc thong bao) -> on dinh.
  for (final it in b.items) {
    if (it.sell != null && isMiengSjcName(it.name.toLowerCase(), b.source)) {
      return it.sell;
    }
  }
  for (final it in b.items) {
    if (it.sell != null) return it.sell;
  }
  for (final it in b.items) {
    if (it.buy != null) return it.buy;
  }
  return null;
}

HistoryPoint _makePoint(Snapshot s) {
  final gold = <String, double>{};
  for (final g in s.gold) {
    if (g.ok) {
      final v = _representative(g);
      if (v != null) gold[g.source] = v;
    }
  }
  return HistoryPoint(t: s.fetchedAt, usd: s.usd.rate, gold: gold);
}

double? _pct(double? cur, double? base) {
  if (cur == null || base == null || base == 0) return null;
  return double.parse(((cur - base) / base * 100).toStringAsFixed(2));
}

/// Diem gan moc 24h truoc nhat (tuoi trong [12h, 48h]) -> moc '1 ngay truoc'.
/// Tra null khi lich su chua du ~1 ngay -> badge hien '—'.
HistoryPoint? _dayAgoBaseline(List<HistoryPoint> history, String nowIso) {
  final now = DateTime.tryParse(nowIso);
  if (now == null) return null;
  final target = now.subtract(const Duration(hours: 24));
  HistoryPoint? best;
  Duration? bestGap;
  for (final p in history) {
    final t = DateTime.tryParse(p.t);
    if (t == null) continue;
    final age = now.difference(t);
    if (age < const Duration(hours: 12) || age > const Duration(hours: 48)) {
      continue;
    }
    final gap = (t.difference(target)).abs();
    if (bestGap == null || gap < bestGap) {
      bestGap = gap;
      best = p;
    }
  }
  return best;
}

void _annotateChanges(Snapshot s, List<HistoryPoint> history, String nowIso) {
  final base = _dayAgoBaseline(history, nowIso);
  final baseUsd = base?.usd;
  final baseGold = base?.gold ?? const {};

  s.usd.changePct = _pct(s.usd.rate, baseUsd);
  for (final g in s.gold) {
    final cur = _representative(g);
    g.representative = cur;
    g.changePct = _pct(cur, baseGold[g.source]);
  }
}

class Store {
  Snapshot? latest;
  List<HistoryPoint> history = [];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final l = p.getString(_kLatest);
    if (l != null) {
      try {
        latest = Snapshot.fromJson(jsonDecode(l) as Map<String, dynamic>);
      } catch (_) {}
    }
    final h = p.getString(_kHistory);
    if (h != null) {
      try {
        history = (jsonDecode(h) as List)
            .map((e) => HistoryPoint.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        history = [];
      }
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    if (latest != null) {
      await p.setString(_kLatest, jsonEncode(latest!.toJson()));
    }
    await p.setString(
      _kHistory,
      jsonEncode(history.map((e) => e.toJson()).toList()),
    );
  }

  /// Fetch tat ca nguon, ghi lich su, tinh %, cache RAM + ghi dia.
  Future<Snapshot> refresh() async {
    final snap = await fetchAll();
    final now = snap.fetchedAt;
    history.add(_makePoint(snap));
    if (history.length > _maxHistory) {
      history = history.sublist(history.length - _maxHistory);
    }
    _annotateChanges(snap, history, now);
    latest = snap;
    await _save();
    return snap;
  }

  List<HistoryPoint> recent({int limit = 300}) {
    if (history.length <= limit) return List.of(history);
    return history.sublist(history.length - limit);
  }
}
