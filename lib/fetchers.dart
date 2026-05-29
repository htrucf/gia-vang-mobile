// Cac fetcher gia vang trong nuoc (SJC/PNJ/DOJI/BTMC) + ty gia USD-VND.
// Port tu ban Python (curl_cffi). Chay truc tiep tren dien thoai -> IP Viet Nam.
//
// Chu y: SJC dung sau Cloudflare. Tren PC, httpx bi chan 403 va phai dung
// curl_cffi (gia lap Chrome). Tren dien thoai, client HTTP cua he dieu hanh
// co the qua hoac khong. Neu SJC bao loi ma 3 nguon con lai chay -> can doi
// sang cronet_http cho rieng SJC (xem README/ghi chu).

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:xml/xml.dart';

import 'models.dart';

// Vang 2026 luon > 50tr/luong -> dung lam "san" de suy ra he so don vi.
const double _goldFloor = 50000000;

const Map<String, String> _baseHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/124.0.0.0 Mobile Safari/537.36',
  'Accept': '*/*',
  'Accept-Language': 'vi,en;q=0.9',
};

double? _toNumber(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final s = value.toString().trim().replaceAll(',', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// Chuan hoa moi bao gia vang ve ~VND/luong (nhan 10 den khi vuot san).
double? _normalizeLuong(dynamic value) {
  final parsed = _toNumber(value);
  if (parsed == null || parsed <= 0) return null;
  var n = parsed;
  while (n < _goldFloor) {
    n *= 10;
  }
  return n.roundToDouble();
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Gio Viet Nam (UTC+7) dang ISO, du device o mui gio nao.
String nowVnIso() {
  final vn = DateTime.now().toUtc().add(const Duration(hours: 7));
  return '${vn.year}-${_two(vn.month)}-${_two(vn.day)}'
      'T${_two(vn.hour)}:${_two(vn.minute)}:${_two(vn.second)}+07:00';
}

// ── Gold ─────────────────────────────────────────────────────────────────────

Future<GoldBlock> fetchSjc(http.Client c) async {
  final r = await c.get(
    Uri.parse('https://sjc.com.vn/GoldPrice/Services/PriceService.ashx'),
    headers: _baseHeaders,
  );
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  final payload = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  final items = <GoldItem>[];
  for (final row in (payload['data'] as List? ?? const [])) {
    final m = row as Map<String, dynamic>;
    final buy = _normalizeLuong(m['BuyValue'] ?? m['Buy']);
    final sell = _normalizeLuong(m['SellValue'] ?? m['Sell']);
    if (buy == null && sell == null) continue;
    items.add(GoldItem(
      name: (m['TypeName'] ?? '').toString().trim(),
      branch: (m['BranchName'] ?? '').toString().trim(),
      buy: buy,
      sell: sell,
    ));
  }
  return GoldBlock(
    source: 'SJC',
    ok: true,
    updated: payload['latestDate']?.toString(),
    items: items,
  );
}

Future<GoldBlock> fetchPnj(http.Client c) async {
  final r = await c.get(
    Uri.parse('https://edge-api.pnj.io/ecom-frontend/v1/get-gold-price'),
    headers: _baseHeaders,
  );
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  final payload = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  final items = <GoldItem>[];
  for (final row in (payload['data'] as List? ?? const [])) {
    final m = row as Map<String, dynamic>;
    final buy = _normalizeLuong(m['giamua']);
    final sell = _normalizeLuong(m['giaban']);
    if (buy == null && sell == null) continue;
    items.add(GoldItem(
      name: (m['tensp'] ?? m['masp'] ?? '').toString().trim(),
      branch: (m['khuvuc'] ?? m['diadiem'] ?? '').toString().trim(),
      buy: buy,
      sell: sell,
    ));
  }
  return GoldBlock(
    source: 'PNJ',
    ok: true,
    updated: (payload['date'] ?? payload['updated'])?.toString(),
    items: items,
  );
}

Future<GoldBlock> fetchDoji(http.Client c) async {
  final r = await c.get(
    Uri.parse(
        'http://giavang.doji.vn/api/giavang/?api_key=258fbd2a72ce8481089d88c678e9fe4f'),
    headers: _baseHeaders,
  );
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  final doc = XmlDocument.parse(utf8.decode(r.bodyBytes));
  final items = <GoldItem>[];
  String? updated;
  final dgpList = doc.findAllElements('DGPlist');
  if (dgpList.isNotEmpty) {
    final dgp = dgpList.first;
    final dt = dgp.findElements('DateTime');
    if (dt.isNotEmpty) updated = dt.first.innerText.trim();
    for (final row in dgp.findElements('Row')) {
      final name = (row.getAttribute('Name') ?? '').trim();
      if (name.isEmpty) continue;
      final buy = _normalizeLuong(row.getAttribute('Buy'));
      final sell = _normalizeLuong(row.getAttribute('Sell'));
      if (buy == null && sell == null) continue;
      items.add(GoldItem(name: name, branch: '', buy: buy, sell: sell));
    }
  }
  return GoldBlock(source: 'DOJI', ok: true, updated: updated, items: items);
}

Future<GoldBlock> fetchBtmc(http.Client c) async {
  // BTMC content-negotiate theo Accept: Chrome -> XML, ep JSON cho de parse.
  final r = await c.get(
    Uri.parse(
        'http://api.btmc.vn/api/BTMCAPI/getpricebtmc?key=3kd8ub1llcg9t45hnoh8hmn7t5kpns'),
    headers: {..._baseHeaders, 'Accept': 'application/json'},
  );
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  final payload = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  final data = ((payload['DataList'] as Map<String, dynamic>?)?['Data']
          as List?) ??
      const [];
  final items = <GoldItem>[];
  String? updated;
  for (final row in data) {
    final m = row as Map<String, dynamic>;
    final idx = m['@row'];
    if (idx == null) continue;
    final name = (m['@n_$idx'] ?? '').toString().trim();
    if (name.isEmpty || name.toUpperCase().contains('BẠC')) continue;
    final buy = _normalizeLuong(m['@pb_$idx']);
    final sell = _normalizeLuong(m['@ps_$idx']);
    if (buy == null && sell == null) continue;
    final d = m['@d_$idx'];
    if (d != null && updated == null) updated = d.toString().trim();
    items.add(GoldItem(name: name, branch: '', buy: buy, sell: sell));
  }
  return GoldBlock(source: 'BTMC', ok: true, updated: updated, items: items);
}

// BTMH cau hinh thieu cert trung gian "GlobalSign RSA OV SSL CA 2018":
// server chi gui leaf -> dart:io bao "Handshake error in client".
// Browser/curl tu lap qua AIA; ta nhung cert trung gian de hoan thanh chuoi.
const String _gsRsaOvSslCa2018 = '''-----BEGIN CERTIFICATE-----
MIIETjCCAzagAwIBAgINAe5fIh38YjvUMzqFVzANBgkqhkiG9w0BAQsFADBMMSAw
HgYDVQQLExdHbG9iYWxTaWduIFJvb3QgQ0EgLSBSMzETMBEGA1UEChMKR2xvYmFs
U2lnbjETMBEGA1UEAxMKR2xvYmFsU2lnbjAeFw0xODExMjEwMDAwMDBaFw0yODEx
MjEwMDAwMDBaMFAxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52
LXNhMSYwJAYDVQQDEx1HbG9iYWxTaWduIFJTQSBPViBTU0wgQ0EgMjAxODCCASIw
DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKdaydUMGCEAI9WXD+uu3Vxoa2uP
UGATeoHLl+6OimGUSyZ59gSnKvuk2la77qCk8HuKf1UfR5NhDW5xUTolJAgvjOH3
idaSz6+zpz8w7bXfIa7+9UQX/dhj2S/TgVprX9NHsKzyqzskeU8fxy7quRU6fBhM
abO1IFkJXinDY+YuRluqlJBJDrnw9UqhCS98NE3QvADFBlV5Bs6i0BDxSEPouVq1
lVW9MdIbPYa+oewNEtssmSStR8JvA+Z6cLVwzM0nLKWMjsIYPJLJLnNvBhBWk0Cq
o8VS++XFBdZpaFwGue5RieGKDkFNm5KQConpFmvv73W+eka440eKHRwup08CAwEA
AaOCASkwggElMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMB0G
A1UdDgQWBBT473/yzXhnqN5vjySNiPGHAwKz6zAfBgNVHSMEGDAWgBSP8Et/qC5F
JK5NUPpjmove4t0bvDA+BggrBgEFBQcBAQQyMDAwLgYIKwYBBQUHMAGGImh0dHA6
Ly9vY3NwMi5nbG9iYWxzaWduLmNvbS9yb290cjMwNgYDVR0fBC8wLTAroCmgJ4Yl
aHR0cDovL2NybC5nbG9iYWxzaWduLmNvbS9yb290LXIzLmNybDBHBgNVHSAEQDA+
MDwGBFUdIAAwNDAyBggrBgEFBQcCARYmaHR0cHM6Ly93d3cuZ2xvYmFsc2lnbi5j
b20vcmVwb3NpdG9yeS8wDQYJKoZIhvcNAQELBQADggEBAJmQyC1fQorUC2bbmANz
EdSIhlIoU4r7rd/9c446ZwTbw1MUcBQJfMPg+NccmBqixD7b6QDjynCy8SIwIVbb
0615XoFYC20UgDX1b10d65pHBf9ZjQCxQNqQmJYaumxtf4z1s4DfjGRzNpZ5eWl0
6r/4ngGPoJVpjemEuunl1Ig423g7mNA2eymw0lIYkN5SQwCuaifIFJ6GlazhgDEw
fpolu4usBCOmmQDo8dIm7A9+O4orkjgTHY+GzYZSR+Y0fFukAj6KYXwidlNalFMz
hriSqHKvoflShx8xpfywgVcvzfTO3PYkz6fiNJBonf6q8amaEsybwMbDqKWwIX7e
SPY=
-----END CERTIFICATE-----''';

http.Client _btmhClient() {
  final ctx = SecurityContext(withTrustedRoots: true)
    ..setTrustedCertificatesBytes(utf8.encode(_gsRsaOvSslCa2018));
  final hc = HttpClient(context: ctx)
    // Du phong: chi bo qua verify cho dung host BTMH va cert do GlobalSign cap.
    ..badCertificateCallback = (cert, host, port) =>
        host == 'baotinmanhhai.vn' && cert.issuer.contains('GlobalSign');
  return IOClient(hc);
}

Future<GoldBlock> fetchBtmh(http.Client _) async {
  // Bao Tin Manh Hai khong co API JSON: gia render san trong HTML (SSR).
  // Quet cap span: ten san pham (font-body) roi 2 gia ke tiep [ban ra, mua vao].
  final c = _btmhClient();
  late final String html;
  try {
    final r = await c.get(
      Uri.parse('https://baotinmanhhai.vn/vi/bang-gia-vang'),
      // 'identity' -> ep server tra HTML khong nen (dart:io khong giai duoc brotli).
      headers: {..._baseHeaders, 'Accept-Encoding': 'identity'},
    );
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    html = utf8.decode(r.bodyBytes);
  } finally {
    c.close();
  }
  final token = RegExp(r'<span class="font-body[^"]*">([^<]+)</span>'
      r'|text-text-dark font-semibold text-sm md:text-lg">([0-9.]+)');
  final items = <GoldItem>[];
  String? name;
  final prices = <double>[];
  void flush() {
    final n = name;
    if (n != null && prices.isNotEmpty && !n.toLowerCase().contains('bạc')) {
      final sell = _normalizeLuong(prices[0]);
      final buy = prices.length > 1 ? _normalizeLuong(prices[1]) : null;
      if (sell != null || buy != null) {
        items.add(GoldItem(name: n.trim(), branch: '', buy: buy, sell: sell));
      }
    }
    prices.clear();
  }

  for (final m in token.allMatches(html)) {
    final nm = m.group(1);
    final pr = m.group(2);
    if (nm != null) {
      flush();
      name = nm;
    } else if (pr != null) {
      final v = double.tryParse(pr.replaceAll('.', ''));
      if (v != null) prices.add(v);
    }
  }
  flush();
  if (items.isEmpty) throw Exception('khong parse duoc gia BTMH');
  return GoldBlock(source: 'BTMH', ok: true, items: items);
}

// ── USD ────────────────────────────────────────────────────────────────────────

const _googleUsd = 'https://www.google.com/finance/quote/USD-VND';
final _usdBlock = RegExp(r'"USD-VND","USD ?/ ?VND",');
final _usdLast = RegExp(r'\[(\d[\d.]*),-?\d');
final _usdClose = RegExp(r'"USD-VND","USD ?/ ?VND",(\d[\d.]*)');

double _parseGoogleUsd(String html) {
  final m = _usdBlock.firstMatch(html);
  if (m != null) {
    final end = (m.start + 400).clamp(0, html.length);
    final window = html.substring(m.start, end);
    final mLast = _usdLast.firstMatch(window);
    if (mLast != null) return double.parse(mLast.group(1)!);
    final mClose = _usdClose.firstMatch(window);
    if (mClose != null) return double.parse(mClose.group(1)!);
  }
  throw Exception('khong tim thay gia USD-VND trong HTML Google Finance');
}

Future<UsdRate> fetchUsd(http.Client c) async {
  try {
    final r = await c.get(Uri.parse(_googleUsd), headers: _baseHeaders);
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final rate = _parseGoogleUsd(utf8.decode(r.bodyBytes));
    return UsdRate(
      source: 'Google Finance',
      ok: true,
      rate: double.parse(rate.toStringAsFixed(2)),
    );
  } catch (eGoogle) {
    try {
      final r = await c.get(
        Uri.parse('https://open.er-api.com/v6/latest/USD'),
        headers: _baseHeaders,
      );
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final rate = (j['rates'] as Map?)?['VND'];
      if (rate == null) throw Exception('thieu VND trong response open.er-api');
      return UsdRate(
        source: 'open.er-api (fallback)',
        ok: true,
        rate: double.parse((rate as num).toStringAsFixed(2)),
        error: 'google loi: $eGoogle',
      );
    } catch (eFallback) {
      return UsdRate(
        source: 'USD',
        ok: false,
        rate: null,
        error: 'google: $eGoogle; erapi: $eFallback',
      );
    }
  }
}

// ── Orchestration ──────────────────────────────────────────────────────────────

Future<GoldBlock> _safe(
  String name,
  Future<GoldBlock> Function(http.Client) fn,
  http.Client c,
) async {
  try {
    return await fn(c);
  } catch (e) {
    return GoldBlock(source: name, ok: false, items: const [], error: e.toString());
  }
}

/// Lay tat ca nguon song song; loi 1 nguon khong lam hong cac nguon khac.
Future<Snapshot> fetchAll() async {
  final c = http.Client();
  try {
    final goldFut = Future.wait<GoldBlock>([
      _safe('SJC', fetchSjc, c),
      _safe('PNJ', fetchPnj, c),
      _safe('DOJI', fetchDoji, c),
      _safe('BTMC', fetchBtmc, c),
      _safe('BTMH', fetchBtmh, c),
    ]);
    final usdFut = fetchUsd(c);
    final gold = await goldFut;
    final usd = await usdFut;
    return Snapshot(fetchedAt: nowVnIso(), gold: gold, usd: usd);
  } finally {
    c.close();
  }
}

// ── Gia ban vang mieng SJC (cho thong bao giam) ─────────────────────────────────

double? _pickMiengSjcSell(GoldBlock b) {
  for (final it in b.items) {
    if (it.sell != null && isMiengSjcName(it.name.toLowerCase(), b.source)) {
      return it.sell;
    }
  }
  return null;
}

/// Trich gia ban vang mieng SJC tu snapshot da co (uu tien PNJ -> DOJI -> BTMC).
double? sjcMiengSellFrom(List<GoldBlock> gold) {
  for (final src in const ['PNJ', 'DOJI', 'BTMC']) {
    for (final b in gold) {
      if (b.ok && b.source == src) {
        final v = _pickMiengSjcSell(b);
        if (v != null) return v;
      }
    }
  }
  return null;
}

/// Fetch nhe chi de lay gia ban SJC mieng (cho task chay nen). PNJ ~2KB di truoc.
Future<double?> fetchSjcMiengSell(http.Client c) async {
  for (final fn in <Future<GoldBlock> Function(http.Client)>[
    fetchPnj,
    fetchDoji,
    fetchBtmc,
  ]) {
    try {
      final v = _pickMiengSjcSell(await fn(c));
      if (v != null) return v;
    } catch (_) {}
  }
  return null;
}
