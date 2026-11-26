import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/investment_models.dart';
import 'cloud_sync_service.dart';
import 'platform_io.dart';

class QuoteFetchResult {
  final int priceCents;
  final String source;
  final String updatedAt;

  const QuoteFetchResult({
    required this.priceCents,
    required this.source,
    required this.updatedAt,
  });
}

class InvestmentQuoteService {
  static String _workerBaseUrl() {
    final base = CloudSyncService.instance.apiBaseUrl.trim();
    if (base.isNotEmpty) {
      return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    }
    return '';
  }

  static const Map<String, String> _cryptoNameAliases = {
    'BITCOIN': 'BTC',
    'ETHEREUM': 'ETH',
    'SOLANA': 'SOL',
    'CARDANO': 'ADA',
    'RIPPLE': 'XRP',
    'DOGECOIN': 'DOGE',
    'LITECOIN': 'LTC',
    'CHAINLINK': 'LINK',
    'POLKADOT': 'DOT',
    'TETHER': 'USDT',
    'USD COIN': 'USDC',
    'USDCOIN': 'USDC',
  };

  static const Map<String, String> _coinGeckoIds = {
    'BTC': 'bitcoin',
    'USDC': 'usd-coin',
    'USDT': 'tether',
    'ETH': 'ethereum',
    'SOL': 'solana',
    'BNB': 'binancecoin',
    'XRP': 'ripple',
    'ADA': 'cardano',
    'DOGE': 'dogecoin',
    'LTC': 'litecoin',
    'LINK': 'chainlink',
    'AVAX': 'avalanche-2',
    'DOT': 'polkadot',
    'TRX': 'tron',
    'SHIB': 'shiba-inu',
    'UNI': 'uniswap',
    'ARB': 'arbitrum',
    'OP': 'optimism',
    'NEAR': 'near',
    'SUI': 'sui',
    'TON': 'the-open-network',
  };

  static String normalizedCryptoBase(String rawTicker) {
    var t = rawTicker.trim().toUpperCase();
    if (_cryptoNameAliases.containsKey(t)) {
      return _cryptoNameAliases[t]!;
    }
    if (t.contains('-')) {
      t = t.split('-').first.trim();
    } else if (t.contains('/')) {
      t = t.split('/').first.trim();
    }
    return _cryptoNameAliases[t] ?? t;
  }

  /// Converte o ticker do ativo para o símbolo compatível com Yahoo Finance.
  static String yahooSymbolFor(InvestAsset asset) {
    final raw = asset.ticker.trim().toUpperCase();
    if (raw.isEmpty) return '';
    if (asset.assetClass == InvestAssetClass.crypto) {
      final base = normalizedCryptoBase(raw);
      final cur = asset.currency.toUpperCase() == 'USD' ? 'USD' : 'BRL';
      return '$base-$cur';
    }
    if (raw.contains('.')) return raw;
    if (asset.currency.toUpperCase() == 'BRL' &&
        (asset.assetClass == InvestAssetClass.stock ||
            asset.assetClass == InvestAssetClass.fii ||
            asset.assetClass == InvestAssetClass.etf ||
            asset.assetClass == InvestAssetClass.bdr)) {
      return '$raw.SA';
    }
    return raw;
  }

  static Future<String?> _httpGetText(Uri uri) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'OpenMoney-App/1.0');
      req.headers.set('Accept', 'application/json');
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }
      return await res.transform(utf8.decoder).join();
    } catch (_) {
      return null;
    }
  }

  /// Busca cotações atualizadas para ativos de Renda Variável e Criptomoedas.
  /// Respeita ativos com `manualPrice == true` (não são consultados).
  static Future<Map<String, QuoteFetchResult>> fetchQuotes(
    List<InvestAsset> assets,
  ) async {
    final targets = assets
        .where((a) => !a.manualPrice && a.assetClass.isVariableIncome)
        .toList();
    if (targets.isEmpty) return {};

    final symbolToAssetIds = <String, List<String>>{};
    for (final a in targets) {
      final sym = yahooSymbolFor(a);
      if (sym.isEmpty) continue;
      symbolToAssetIds.putIfAbsent(sym, () => []).add(a.id);
    }
    if (symbolToAssetIds.isEmpty) return {};

    final nowIso = DateTime.now().toIso8601String();
    final results = <String, QuoteFetchResult>{};

    if (kIsWeb) {
      final syms = symbolToAssetIds.keys.join(',');
      final uri = Uri.parse(
        '${_workerBaseUrl()}/api/market/quotes?symbols=${Uri.encodeQueryComponent(syms)}',
      );
      final body = await _httpGetText(uri);
      if (body != null) {
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map && decoded['quotes'] is Map) {
            final quotes = decoded['quotes'] as Map;
            quotes.forEach((sym, val) {
              if (val is Map) {
                final price = (val['price'] as num?)?.toDouble();
                if (price != null && price > 0) {
                  final cents = (price * 100.0).round();
                  final src = val['source']?.toString() ?? 'Yahoo Finance';
                  final upd = val['updatedAt']?.toString() ?? nowIso;
                  for (final aid in symbolToAssetIds[sym.toString()] ?? const []) {
                    results[aid] = QuoteFetchResult(
                      priceCents: cents,
                      source: src,
                      updatedAt: upd,
                    );
                  }
                }
              }
            });
          }
        } catch (_) {}
      }
      return results;
    }

    // Native: 1) Criptomoedas via Binance -> CoinGecko -> AwesomeAPI -> Yahoo
    final cryptoTargets = targets
        .where((a) => a.assetClass == InvestAssetClass.crypto)
        .toList();
    if (cryptoTargets.isNotEmpty) {
      await _fetchCryptoQuotesNative(cryptoTargets, results, nowIso);
    }

    // Native: 2) Demais ativos (ou criptos ainda sem cotação) via Yahoo Finance
    final remainingEntries = <MapEntry<String, List<String>>>[];
    for (final entry in symbolToAssetIds.entries) {
      final missingIds =
          entry.value.where((id) => !results.containsKey(id)).toList();
      if (missingIds.isNotEmpty) {
        remainingEntries.add(MapEntry(entry.key, missingIds));
      }
    }

    const chunkSize = 5;
    for (var i = 0; i < remainingEntries.length; i += chunkSize) {
      final chunk = remainingEntries.sublist(
        i,
        i + chunkSize > remainingEntries.length
            ? remainingEntries.length
            : i + chunkSize,
      );
      await Future.wait(chunk.map((entry) async {
        final sym = entry.key;
        final uri = Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(sym)}?range=1d&interval=1d',
        );
        final body = await _httpGetText(uri);
        final price = _parseYahooChartPrice(body);
        if (price != null && price > 0) {
          final cents = (price * 100.0).round();
          for (final aid in entry.value) {
            results[aid] = QuoteFetchResult(
              priceCents: cents,
              source: 'Yahoo Finance',
              updatedAt: nowIso,
            );
          }
        }
      }));
    }

    return results;
  }

  static double? parseBinancePriceJson(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final p = double.tryParse(decoded['price']?.toString() ?? '');
        if (p != null && p > 0) return p;
      }
    } catch (_) {}
    return null;
  }

  static double? parseCoinbasePriceJson(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['data'] is Map) {
        final p = double.tryParse(decoded['data']['amount']?.toString() ?? '');
        if (p != null && p > 0) return p;
      }
    } catch (_) {}
    return null;
  }

  static double? parseMercadoBitcoinPriceJson(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['ticker'] is Map) {
        final p = double.tryParse(decoded['ticker']['last']?.toString() ?? '');
        if (p != null && p > 0) return p;
      }
    } catch (_) {}
    return null;
  }

  static Map<String, Map<String, double>> parseCoinGeckoPricesJson(String? body) {
    final out = <String, Map<String, double>>{};
    if (body == null || body.isEmpty) return out;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        decoded.forEach((coinId, currencies) {
          if (currencies is Map) {
            final curMap = <String, double>{};
            currencies.forEach((cur, val) {
              final d = (val as num?)?.toDouble();
              if (d != null && d > 0) {
                curMap[cur.toString().toLowerCase()] = d;
              }
            });
            if (curMap.isNotEmpty) {
              out[coinId.toString().toLowerCase()] = curMap;
            }
          }
        });
      }
    } catch (_) {}
    return out;
  }

  static Future<void> _fetchCryptoQuotesNative(
    List<InvestAsset> cryptoAssets,
    Map<String, QuoteFetchResult> results,
    String nowIso,
  ) async {
    // 1. Binance API pública (suporta BTCBRL, USDCBRL, ETHBRL, SOLBRL, BTCUSDT, etc.)
    await Future.wait(cryptoAssets.map((asset) async {
      final base = normalizedCryptoBase(asset.ticker);
      final cur = asset.currency.toUpperCase() == 'USD' ? 'USD' : 'BRL';
      if (cur == 'USD' && (base == 'USDC' || base == 'USDT')) {
        results[asset.id] = QuoteFetchResult(
          priceCents: 100,
          source: 'USD Paridade',
          updatedAt: nowIso,
        );
        return;
      }
      final binancePair = cur == 'USD' ? '${base}USDT' : '${base}BRL';
      final uri = Uri.parse(
        'https://api.binance.com/api/v3/ticker/price?symbol=${Uri.encodeQueryComponent(binancePair)}',
      );
      final price = parseBinancePriceJson(await _httpGetText(uri));
      if (price != null && price > 0) {
        results[asset.id] = QuoteFetchResult(
          priceCents: (price * 100.0).round(),
          source: 'Binance',
          updatedAt: nowIso,
        );
        return;
      }

      // Fallback rápido 1: Coinbase Spot (suporta BTC-BRL, USDC-BRL, ETH-BRL, BTC-USD)
      final cbUri = Uri.parse(
        'https://api.coinbase.com/v2/prices/${Uri.encodeComponent(base)}-${Uri.encodeComponent(cur)}/spot',
      );
      final cbPrice = parseCoinbasePriceJson(await _httpGetText(cbUri));
      if (cbPrice != null && cbPrice > 0) {
        results[asset.id] = QuoteFetchResult(
          priceCents: (cbPrice * 100.0).round(),
          source: 'Coinbase',
          updatedAt: nowIso,
        );
        return;
      }

      // Fallback rápido 2: Mercado Bitcoin (BRL)
      if (cur == 'BRL') {
        final mbUri = Uri.parse(
          'https://www.mercadobitcoin.net/api/${Uri.encodeComponent(base)}/ticker/',
        );
        final mbPrice = parseMercadoBitcoinPriceJson(await _httpGetText(mbUri));
        if (mbPrice != null && mbPrice > 0) {
          results[asset.id] = QuoteFetchResult(
            priceCents: (mbPrice * 100.0).round(),
            source: 'Mercado Bitcoin',
            updatedAt: nowIso,
          );
        }
      }
    }));

    // 2. Fallback CoinGecko para criptos ainda sem cotação
    final missingCg = cryptoAssets
        .where((a) => !results.containsKey(a.id))
        .toList();
    if (missingCg.isNotEmpty) {
      final idsToFetch = <String>{};
      for (final a in missingCg) {
        final base = normalizedCryptoBase(a.ticker);
        final cgId = _coinGeckoIds[base];
        if (cgId != null) idsToFetch.add(cgId);
      }
      if (idsToFetch.isNotEmpty) {
        final uri = Uri.parse(
          'https://api.coingecko.com/api/v3/simple/price?ids=${idsToFetch.join(",")}&vs_currencies=brl,usd',
        );
        final cgMap = parseCoinGeckoPricesJson(await _httpGetText(uri));
        for (final a in missingCg) {
          final base = normalizedCryptoBase(a.ticker);
          final cgId = _coinGeckoIds[base];
          if (cgId == null) continue;
          final curKey = a.currency.toUpperCase() == 'USD' ? 'usd' : 'brl';
          final price = cgMap[cgId]?[curKey];
          if (price != null && price > 0) {
            results[a.id] = QuoteFetchResult(
              priceCents: (price * 100.0).round(),
              source: 'CoinGecko',
              updatedAt: nowIso,
            );
          }
        }
      }
    }

    // 3. Fallback AwesomeAPI (BTC-BRL, ETH-BRL e USD-BRL para USDC/USDT)
    final missingAw = cryptoAssets
        .where((a) =>
            !results.containsKey(a.id) &&
            a.currency.toUpperCase() != 'USD')
        .toList();
    if (missingAw.isNotEmpty) {
      final body = await _httpGetText(
        Uri.parse(
          'https://economia.awesomeapi.com.br/last/BTC-BRL,ETH-BRL,USD-BRL',
        ),
      );
      if (body != null) {
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map) {
            for (final a in missingAw) {
              final base = normalizedCryptoBase(a.ticker);
              final key = (base == 'USDC' || base == 'USDT')
                  ? 'USDBRL'
                  : '${base}BRL';
              final entry = decoded[key];
              if (entry is Map) {
                final bid = double.tryParse(entry['bid']?.toString() ?? '');
                if (bid != null && bid > 0) {
                  results[a.id] = QuoteFetchResult(
                    priceCents: (bid * 100.0).round(),
                    source: 'AwesomeAPI',
                    updatedAt: nowIso,
                  );
                }
              }
            }
          }
        } catch (_) {}
      }
    }
  }

  static double? _parseYahooChartPrice(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final chart = decoded['chart'];
      if (chart is! Map) return null;
      final resultList = chart['result'];
      if (resultList is! List || resultList.isEmpty) return null;
      final first = resultList.first;
      if (first is! Map) return null;
      final meta = first['meta'];
      if (meta is! Map) return null;
      final reg = (meta['regularMarketPrice'] as num?)?.toDouble();
      if (reg != null && reg > 0) return reg;
      final prev = (meta['chartPreviousClose'] as num?)?.toDouble();
      if (prev != null && prev > 0) return prev;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Faz parse da série diária SGS 12 do Banco Central (`dd/MM/yyyy` -> `YYYY-MM-DD`).
  static Map<String, double> parseBcbDailySeriesJson(String? body) {
    if (body == null || body.isEmpty) return {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) return {};
      final out = <String, double>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final rawDate = item['data']?.toString().trim() ?? '';
        final parts = rawDate.split('/');
        if (parts.length != 3) continue;
        final iso =
            '${parts[2].padLeft(4, '0')}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
        final rawVal = item['valor']?.toString().replaceAll(',', '.').trim();
        final val = double.tryParse(rawVal ?? '');
        if (val != null) {
          out[iso] = val;
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Busca indicadores oficiais do BCB (Selic, CDI, IPCA 12m e série diária do CDI).
  static Future<MarketIndicators?> fetchIndicators({String? cdiFromIso}) async {
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final minDate = DateTime(now.year - 9, now.month, now.day);
    var startDate = DateTime(now.year - 3, now.month, now.day);
    if (cdiFromIso != null && cdiFromIso.length >= 10) {
      final parsed = DateTime.tryParse(cdiFromIso.substring(0, 10));
      if (parsed != null) {
        startDate = parsed.isBefore(minDate) ? minDate : parsed;
      }
    }
    if (startDate.isAfter(now)) startDate = now;
    final startIso =
        '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';

    if (kIsWeb) {
      final uri = Uri.parse(
        '${_workerBaseUrl()}/api/market/indicators?cdiFrom=$startIso',
      );
      final body = await _httpGetText(uri);
      if (body == null) return null;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          final rawSeries = decoded['cdiDailySeries'];
          final parsedSeries = <String, double>{};
          if (rawSeries is Map) {
            for (final e in rawSeries.entries) {
              final v = (e.value as num?)?.toDouble();
              if (v != null && e.key != null) {
                parsedSeries[e.key.toString()] = v;
              }
            }
          }
          return MarketIndicators(
            cdiAnnual: (decoded['cdiAnnual'] as num?)?.toDouble() ?? 11.15,
            selicAnnual: (decoded['selicAnnual'] as num?)?.toDouble() ?? 11.25,
            ipca12m: (decoded['ipca12m'] as num?)?.toDouble() ?? 4.50,
            updatedAt: decoded['updatedAt']?.toString() ?? nowIso,
            manual: false,
            cdiDailySeries: parsedSeries,
          );
        }
      } catch (_) {}
      return null;
    }

    Future<double?> fetchSgs(int serie) async {
      final uri = Uri.parse(
        'https://api.bcb.gov.br/dados/serie/bcdata.sgs.$serie/dados/ultimos/1?formato=json',
      );
      final body = await _httpGetText(uri);
      if (body == null) return null;
      try {
        final list = jsonDecode(body);
        if (list is List && list.isNotEmpty && list.first is Map) {
          final rawVal = list.first['valor']?.toString().replaceAll(',', '.');
          return double.tryParse(rawVal ?? '');
        }
      } catch (_) {}
      return null;
    }

    String fmtBr(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    final cdiSeriesFuture = _httpGetText(
      Uri.parse(
        'https://api.bcb.gov.br/dados/serie/bcdata.sgs.12/dados?formato=json&dataInicial=${fmtBr(startDate)}&dataFinal=${fmtBr(now)}',
      ),
    ).then(parseBcbDailySeriesJson);

    final results = await Future.wait([
      fetchSgs(4389), // CDI anualizado
      fetchSgs(432), // Meta Selic
      fetchSgs(13522), // IPCA 12 meses
    ]);
    final cdiSeries = await cdiSeriesFuture;

    if (results[0] == null &&
        results[1] == null &&
        results[2] == null &&
        cdiSeries.isEmpty) {
      return null;
    }

    return MarketIndicators(
      cdiAnnual: results[0] ?? 11.15,
      selicAnnual: results[1] ?? 11.25,
      ipca12m: results[2] ?? 4.50,
      updatedAt: nowIso,
      manual: false,
      cdiDailySeries: cdiSeries,
    );
  }
}
