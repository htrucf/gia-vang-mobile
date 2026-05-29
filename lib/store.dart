// Cache gia trong RAM + luu xuong shared_preferences (latest + history).
// Tinh % thay doi so voi dau ngay (gio VN). Port tu app/store.py.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'fetchers.dart';
import 'models.dart';

const int _maxHistory = 1000; // ~13 ngay neu cap nhat moi 20 phut
const String _kLatest = 'latest';
const String _kHistory = 'history';

double? _representative(GoldBlock b) {
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

/// Diem som nhat trong cung ngay (gio VN) -> moc 'dau ngay'.
HistoryPoint? _todayBaseline(List<HistoryPoint> history, String nowIso) {
  final today = nowIso.length >= 10 ? nowIso.substring(0, 10) : nowIso;
  for (final p in history) {
    if (p.t.length >= 10 && p.t.substring(0, 10) == today) return p;
  }
  return null;
}

void _annotateChanges(Snapshot s, List<HistoryPoint> history, String nowIso) {
  final base = _todayBaseline(history, nowIso);
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
