// Mo hinh du lieu gia vang + USD. Co toJson/fromJson de luu vao shared_preferences.

class GoldItem {
  final String name;
  final String branch;
  final double? buy;
  final double? sell;

  GoldItem({required this.name, required this.branch, this.buy, this.sell});

  Map<String, dynamic> toJson() =>
      {'name': name, 'branch': branch, 'buy': buy, 'sell': sell};

  factory GoldItem.fromJson(Map<String, dynamic> j) => GoldItem(
        name: (j['name'] ?? '').toString(),
        branch: (j['branch'] ?? '').toString(),
        buy: (j['buy'] as num?)?.toDouble(),
        sell: (j['sell'] as num?)?.toDouble(),
      );
}

class GoldBlock {
  final String source;
  final bool ok;
  final String? updated;
  final List<GoldItem> items;
  final String? error;
  double? representative;
  double? changePct;

  GoldBlock({
    required this.source,
    required this.ok,
    this.updated,
    this.items = const [],
    this.error,
    this.representative,
    this.changePct,
  });

  Map<String, dynamic> toJson() => {
        'source': source,
        'ok': ok,
        'updated': updated,
        'items': items.map((e) => e.toJson()).toList(),
        'error': error,
        'representative': representative,
        'change_pct': changePct,
      };

  factory GoldBlock.fromJson(Map<String, dynamic> j) => GoldBlock(
        source: (j['source'] ?? '').toString(),
        ok: j['ok'] == true,
        updated: j['updated']?.toString(),
        items: ((j['items'] as List?) ?? [])
            .map((e) => GoldItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        error: j['error']?.toString(),
        representative: (j['representative'] as num?)?.toDouble(),
        changePct: (j['change_pct'] as num?)?.toDouble(),
      );
}

class UsdRate {
  final String source;
  final bool ok;
  final double? rate;
  final String? error;
  double? changePct;

  UsdRate({
    required this.source,
    required this.ok,
    this.rate,
    this.error,
    this.changePct,
  });

  Map<String, dynamic> toJson() => {
        'source': source,
        'ok': ok,
        'rate': rate,
        'error': error,
        'change_pct': changePct,
      };

  factory UsdRate.fromJson(Map<String, dynamic> j) => UsdRate(
        source: (j['source'] ?? '').toString(),
        ok: j['ok'] == true,
        rate: (j['rate'] as num?)?.toDouble(),
        error: j['error']?.toString(),
        changePct: (j['change_pct'] as num?)?.toDouble(),
      );
}

class Snapshot {
  final String fetchedAt;
  final List<GoldBlock> gold;
  final UsdRate usd;

  Snapshot({required this.fetchedAt, required this.gold, required this.usd});

  Map<String, dynamic> toJson() => {
        'fetched_at': fetchedAt,
        'gold': gold.map((e) => e.toJson()).toList(),
        'usd': usd.toJson(),
      };

  factory Snapshot.fromJson(Map<String, dynamic> j) => Snapshot(
        fetchedAt: (j['fetched_at'] ?? '').toString(),
        gold: ((j['gold'] as List?) ?? [])
            .map((e) => GoldBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
        usd: UsdRate.fromJson((j['usd'] as Map<String, dynamic>?) ?? {}),
      );
}

class HistoryPoint {
  final String t;
  final double? usd;
  final Map<String, double> gold;

  HistoryPoint({required this.t, this.usd, this.gold = const {}});

  Map<String, dynamic> toJson() => {'t': t, 'usd': usd, 'gold': gold};

  factory HistoryPoint.fromJson(Map<String, dynamic> j) => HistoryPoint(
        t: (j['t'] ?? '').toString(),
        usd: (j['usd'] as num?)?.toDouble(),
        gold: ((j['gold'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        ),
      );
}
