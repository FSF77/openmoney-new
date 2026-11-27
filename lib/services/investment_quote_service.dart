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

class FiiDividendEvent {
  final String ticker;
  final String paymentDateIso;
  final String lastDatePriorIso;
  final double ratePerQuota;
  final String label;
  final String relatedTo;
  final String isinCode;

  const FiiDividendEvent({
    required this.ticker,
    required this.paymentDateIso,
    required this.lastDatePriorIso,
    required this.ratePerQuota,
    required this.label,
    required this.relatedTo,
    required this.isinCode,
  });

  bool get isAmortization => label.toUpperCase().contains('AMORT');
  bool get isJcp =>
      label.toUpperCase().contains('JCP') || label.toUpperCase().contains('JRS');
  bool get isDividend => label.toUpperCase().contains('DIVIDEND');
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

  static const String _tesouroTransparenteCsvUrl =
      'https://www.tesourotransparente.gov.br/ckan/dataset/df56aa42-484a-4a59-8184-7676580c81e3/resource/796d2059-14e9-44e3-80c9-2d9e30b405c1/download/precotaxatesourodireto.csv';

  static String _normalizeAccents(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c');
  }

  /// Gera chave normalizada `<familia>:<ano>` para casar títulos do Tesouro Direto
  /// mesmo quando o usuário inclui a taxa contratada no nome (ex: `TESOURO IPCA+ 2029 / IPCA + 7,89%`).
  static String? tesouroBondKeyFromText(String text, {String? maturityDateIso}) {
    final norm = _normalizeAccents(text);
    final hasJuros = norm.contains('juros') || norm.contains('semestrais');

    String? family;
    if (norm.contains('renda+') ||
        norm.contains('renda mais') ||
        norm.contains('aposentadoria')) {
      family = 'renda_mais';
    } else if (norm.contains('educa+') || norm.contains('educa mais')) {
      family = 'educa_mais';
    } else if (norm.contains('igpm')) {
      family = hasJuros ? 'igpm_juros' : 'igpm';
    } else if (norm.contains('ipca')) {
      family = hasJuros ? 'ipca_juros' : 'ipca';
    } else if (norm.contains('selic')) {
      family = 'selic';
    } else if (norm.contains('prefixado') || norm.contains('pre-fixado') || norm.contains('pre fixado')) {
      family = hasJuros ? 'prefixado_juros' : 'prefixado';
    }
    if (family == null) return null;

    String? year;
    final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(norm);
    if (yearMatch != null) {
      year = yearMatch.group(1);
    } else if (maturityDateIso != null && maturityDateIso.length >= 4) {
      final m = RegExp(r'(20\d{2})').firstMatch(maturityDateIso);
      year = m?.group(1);
    }
    if (year == null) return null;
    return '$family:$year';
  }

  static String? tesouroBondKeyForAsset(InvestAsset asset) {
    return tesouroBondKeyFromText(
      '${asset.ticker} ${asset.name} ${asset.subType ?? ''}',
      maturityDateIso: asset.maturityDate,
    );
  }

  /// Faz parse do CSV oficial do Tesouro Transparente (`PrecoTaxaTesouroDireto.csv`),
  /// retornando o PU de resgate (`PU Venda Manha`) mais recente por chave `<familia>:<ano>`.
  static Map<String, ({double puVenda, String dataBaseIso})>
      parseTesouroTransparenteCsv(String? body) {
    final out = <String, ({double puVenda, String dataBaseIso})>{};
    if (body == null || body.isEmpty) return out;
    final lines = body.split(RegExp(r'\r?\n'));
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || i == 0 && line.toLowerCase().contains('tipo titulo')) {
        continue;
      }
      final cols = line.split(';');
      if (cols.length < 7) continue;

      final tipo = cols[0].trim();
      final vencParts = cols[1].trim().split('/');
      final baseParts = cols[2].trim().split('/');
      if (vencParts.length != 3 || baseParts.length != 3) continue;

      final vencYear = int.tryParse(vencParts[2]);
      if (vencYear == null) continue;
      final dataBaseIso =
          '${baseParts[2].padLeft(4, '0')}-${baseParts[1].padLeft(2, '0')}-${baseParts[0].padLeft(2, '0')}';

      double? pu = double.tryParse(cols[6].trim().replaceAll(',', '.'));
      if ((pu == null || pu <= 0) && cols.length >= 8) {
        pu = double.tryParse(cols[7].trim().replaceAll(',', '.'));
      }
      if (pu == null || pu <= 0) continue;

      final baseKey = tesouroBondKeyFromText(
        tipo,
        maturityDateIso: '$vencYear-01-01',
      );
      if (baseKey == null) continue;

      void putKey(String key) {
        final prev = out[key];
        if (prev == null || dataBaseIso.compareTo(prev.dataBaseIso) > 0) {
          out[key] = (puVenda: pu!, dataBaseIso: dataBaseIso);
        }
      }

      putKey(baseKey);
      final family = baseKey.split(':').first;
      if (family == 'renda_mais' && vencYear > 2020) {
        putKey('renda_mais:${vencYear - 19}');
      } else if (family == 'educa_mais' && vencYear > 2010) {
        putKey('educa_mais:${vencYear - 4}');
      }
    }
    return out;
  }

  static Future<String?> _httpGetText(
    Uri uri, {
    Map<String, String>? headers,
    int? maxBytes,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'OpenMoney-App/1.0');
      req.headers.set('Accept', 'application/json');
      if (headers != null) {
        headers.forEach((k, v) => req.headers.set(k, v));
      }
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }
      if (maxBytes != null) {
        final buf = <int>[];
        await for (final chunk in res) {
          final remaining = maxBytes - buf.length;
          if (remaining <= 0) break;
          if (chunk.length <= remaining) {
            buf.addAll(chunk);
          } else {
            buf.addAll(chunk.sublist(0, remaining));
            break;
          }
        }
        client.close(force: true);
        return utf8.decode(buf, allowMalformed: true);
      }
      return await res.transform(utf8.decoder).join();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Busca cotações atualizadas para ativos de Renda Variável, Criptomoedas e Tesouro Direto.
  /// Respeita ativos com `manualPrice == true` (não são consultados).
  static Future<Map<String, QuoteFetchResult>> fetchQuotes(
    List<InvestAsset> assets,
  ) async {
    final varTargets = assets
        .where((a) => !a.manualPrice && a.assetClass.isVariableIncome)
        .toList();
    final tesouroTargets = assets
        .where((a) => !a.manualPrice && a.assetClass == InvestAssetClass.tesouro)
        .toList();
    if (varTargets.isEmpty && tesouroTargets.isEmpty) return {};

    final symbolToAssetIds = <String, List<String>>{};
    for (final a in varTargets) {
      final sym = yahooSymbolFor(a);
      if (sym.isEmpty) continue;
      symbolToAssetIds.putIfAbsent(sym, () => []).add(a.id);
    }

    final nowIso = DateTime.now().toIso8601String();
    final results = <String, QuoteFetchResult>{};

    if (kIsWeb) {
      if (symbolToAssetIds.isNotEmpty) {
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
                    for (final aid
                        in symbolToAssetIds[sym.toString()] ?? const []) {
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
      }
      if (tesouroTargets.isNotEmpty) {
        final uri = Uri.parse('${_workerBaseUrl()}/api/market/tesouro');
        final body = await _httpGetText(uri);
        if (body != null) {
          try {
            final decoded = jsonDecode(body);
            if (decoded is Map && decoded['bonds'] is Map) {
              final bonds = decoded['bonds'] as Map;
              for (final a in tesouroTargets) {
                final key = tesouroBondKeyForAsset(a);
                if (key == null) continue;
                final entry = bonds[key];
                if (entry is Map) {
                  final pu = (entry['puVenda'] as num?)?.toDouble();
                  if (pu != null && pu > 0) {
                    results[a.id] = QuoteFetchResult(
                      priceCents: (pu * 100.0).round(),
                      source: 'Tesouro Direto',
                      updatedAt: entry['dataBase']?.toString() ?? nowIso,
                    );
                  }
                }
              }
            }
          } catch (_) {}
        }
      }
      return results;
    }

    // Native: 0) Tesouro Direto (PU oficial de resgate do Tesouro Transparente)
    Future<void>? tesouroFuture;
    if (tesouroTargets.isNotEmpty) {
      tesouroFuture = _httpGetText(
        Uri.parse(_tesouroTransparenteCsvUrl),
        maxBytes: 24576,
        headers: const {
          'Range': 'bytes=0-24575',
          'Accept': 'text/csv,text/plain,*/*',
        },
      ).then((csvBody) {
        final bonds = parseTesouroTransparenteCsv(csvBody);
        for (final a in tesouroTargets) {
          final key = tesouroBondKeyForAsset(a);
          if (key == null) continue;
          final entry = bonds[key];
          if (entry != null && entry.puVenda > 0) {
            results[a.id] = QuoteFetchResult(
              priceCents: (entry.puVenda * 100.0).round(),
              source: 'Tesouro Direto',
              updatedAt: entry.dataBaseIso,
            );
          }
        }
      });
    }

    // Native: 1) Criptomoedas via Binance -> CoinGecko -> AwesomeAPI -> Yahoo
    final cryptoTargets = varTargets
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

    if (tesouroFuture != null) {
      await tesouroFuture;
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

  /// Extrai o código base de 4 letras do FII (ex.: `BTLG11` -> `BTLG`).
  static String fiiIdentifierCode(String ticker) {
    final clean = ticker.trim().toUpperCase().split('.').first;
    final m = RegExp(r'^([A-Z]{4})\d{1,2}[A-Z]?$').firstMatch(clean);
    if (m != null) return m.group(1)!;
    return clean.length >= 4 ? clean.substring(0, 4) : clean;
  }

  static String? _parseBrDateToIso(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return s;
    final parts = s.split('/');
    if (parts.length != 3) return null;
    final y = parts[2].trim().padLeft(4, '0');
    final m = parts[1].trim().padLeft(2, '0');
    final d = parts[0].trim().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Faz parse do JSON público de proventos de FIIs da B3 (`GetListedSupplementFunds`).
  static List<FiiDividendEvent> parseB3FiiDividendsJson(
    String ticker,
    String? body,
  ) {
    if (body == null || body.isEmpty) return const [];
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const [];
      final list = decoded['cashDividends'];
      if (list is! List) return const [];

      final out = <FiiDividendEvent>[];
      for (final item in list) {
        if (item is! Map) continue;
        final isin = (item['isinCode'] ?? item['assetIssued'] ?? '').toString().trim().toUpperCase();
        // Ignora recibos de subscrição (ex.: BRBTLGR29M15) mantendo cota principal (CTF)
        if (isin.length >= 9 && !isin.contains('CTF') && isin.contains('R')) {
          continue;
        }
        final payIso = _parseBrDateToIso(item['paymentDate']?.toString());
        final comIso = _parseBrDateToIso(item['lastDatePrior']?.toString()) ??
            _parseBrDateToIso(item['approvedOn']?.toString()) ??
            payIso;
        final rawRate = item['rate']?.toString().replaceAll('.', '').replaceAll(',', '.').trim();
        final rate = double.tryParse(rawRate ?? '');
        if (payIso == null || comIso == null || rate == null || rate <= 0) {
          continue;
        }
        out.add(FiiDividendEvent(
          ticker: ticker.trim().toUpperCase(),
          paymentDateIso: payIso,
          lastDatePriorIso: comIso,
          ratePerQuota: rate,
          label: item['label']?.toString().trim() ?? 'RENDIMENTO',
          relatedTo: item['relatedTo']?.toString().trim() ?? '',
          isinCode: isin,
        ));
      }
      out.sort((a, b) => b.paymentDateIso.compareTo(a.paymentDateIso));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Verifica se o ISIN da B3 corresponde à classe do ticker da ação (`3`=ON, `4/5/6`=PN, `11`=Unit).
  static bool stockIsinMatchesTicker(String ticker, String isin) {
    final normIsin = isin.trim().toUpperCase();
    if (normIsin.isEmpty) return true;
    final clean = ticker.trim().toUpperCase().split('.').first;
    final m = RegExp(r'^[A-Z]{4}(\d{1,2})[A-Z]?$').firstMatch(clean);
    if (m == null) return true;
    final suffix = m.group(1)!;
    if (suffix == '3') return normIsin.contains('ACNOR');
    if (suffix == '4') return normIsin.contains('ACNPR');
    if (suffix == '5') return normIsin.contains('ACNPA') || normIsin.contains('ACNPR');
    if (suffix == '6') return normIsin.contains('ACNPB') || normIsin.contains('ACNPR');
    if (suffix == '11') return normIsin.contains('CDAM') || normIsin.contains('UNT');
    return true;
  }

  /// Faz parse do JSON público de proventos de Ações da B3 (`GetListedSupplementCompany`).
  static List<FiiDividendEvent> parseB3StockDividendsJson(
    String ticker,
    String? body,
  ) {
    if (body == null || body.isEmpty) return const [];
    try {
      final decoded = jsonDecode(body);
      final Map? company = decoded is List && decoded.isNotEmpty && decoded.first is Map
          ? decoded.first as Map
          : (decoded is Map ? decoded : null);
      if (company == null) return const [];
      final list = company['cashDividends'];
      if (list is! List) return const [];

      final out = <FiiDividendEvent>[];
      for (final item in list) {
        if (item is! Map) continue;
        final isin = (item['isinCode'] ?? item['assetIssued'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        if (!stockIsinMatchesTicker(ticker, isin)) continue;

        final payIso = _parseBrDateToIso(item['paymentDate']?.toString());
        final comIso = _parseBrDateToIso(item['lastDatePrior']?.toString()) ??
            _parseBrDateToIso(item['approvedOn']?.toString()) ??
            payIso;
        final rawRate =
            item['rate']?.toString().replaceAll('.', '').replaceAll(',', '.').trim();
        final rate = double.tryParse(rawRate ?? '');
        if (payIso == null || comIso == null || rate == null || rate <= 0) {
          continue;
        }
        out.add(FiiDividendEvent(
          ticker: ticker.trim().toUpperCase(),
          paymentDateIso: payIso,
          lastDatePriorIso: comIso,
          ratePerQuota: rate,
          label: item['label']?.toString().trim() ?? 'DIVIDENDO',
          relatedTo: item['relatedTo']?.toString().trim() ?? '',
          isinCode: isin,
        ));
      }
      out.sort((a, b) => b.paymentDateIso.compareTo(a.paymentDateIso));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Busca dividendos, JCP e rendimentos anunciados na B3 para FIIs e Ações.
  static Future<Map<String, List<FiiDividendEvent>>> fetchFiiDividends(
    List<InvestAsset> assets,
  ) async {
    final fiis = assets
        .where((a) => !a.inactive && a.assetClass == InvestAssetClass.fii)
        .toList();
    final stocks = assets
        .where((a) =>
            !a.inactive &&
            a.assetClass == InvestAssetClass.stock &&
            a.currency.toUpperCase() == 'BRL')
        .toList();
    if (fiis.isEmpty && stocks.isEmpty) return {};

    final results = <String, List<FiiDividendEvent>>{};
    if (kIsWeb) {
      final fiiTickers =
          fiis.map((a) => a.ticker.trim().toUpperCase()).toSet().join(',');
      final stockTickers =
          stocks.map((a) => a.ticker.trim().toUpperCase()).toSet().join(',');
      final uri = Uri.parse(
        '${_workerBaseUrl()}/api/market/fii-dividends'
        '?tickers=${Uri.encodeQueryComponent(fiiTickers)}'
        '&stockTickers=${Uri.encodeQueryComponent(stockTickers)}',
      );
      final body = await _httpGetText(uri);
      if (body != null) {
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map && decoded['dividends'] is Map) {
            final divs = decoded['dividends'] as Map;
            for (final a in [...fiis, ...stocks]) {
              final rawList = divs[a.ticker.trim().toUpperCase()];
              if (rawList is List) {
                results[a.id] = rawList
                    .whereType<Map>()
                    .map((m) => FiiDividendEvent(
                          ticker: a.ticker.trim().toUpperCase(),
                          paymentDateIso: m['paymentDateIso']?.toString() ?? '',
                          lastDatePriorIso: m['lastDatePriorIso']?.toString() ?? '',
                          ratePerQuota: (m['ratePerQuota'] as num?)?.toDouble() ?? 0.0,
                          label: m['label']?.toString() ?? 'RENDIMENTO',
                          relatedTo: m['relatedTo']?.toString() ?? '',
                          isinCode: m['isinCode']?.toString() ?? '',
                        ))
                    .where((e) => e.paymentDateIso.isNotEmpty && e.ratePerQuota > 0)
                    .toList();
              }
            }
          }
        } catch (_) {}
      }
      return results;
    }

    const chunkSize = 5;
    for (var i = 0; i < fiis.length; i += chunkSize) {
      final chunk = fiis.sublist(
        i,
        i + chunkSize > fiis.length ? fiis.length : i + chunkSize,
      );
      await Future.wait(chunk.map((asset) async {
        final code = fiiIdentifierCode(asset.ticker);
        if (code.isEmpty) return;
        final payload = jsonEncode({'typeFund': 7, 'identifierFund': code});
        final b64 = base64Encode(utf8.encode(payload));
        final uri = Uri.parse(
          'https://sistemaswebb3-listados.b3.com.br/fundsProxy/fundsCall/GetListedSupplementFunds/$b64',
        );
        final body = await _httpGetText(uri);
        final events = parseB3FiiDividendsJson(asset.ticker, body);
        if (events.isNotEmpty) {
          results[asset.id] = events;
        }
      }));
    }

    for (var i = 0; i < stocks.length; i += chunkSize) {
      final chunk = stocks.sublist(
        i,
        i + chunkSize > stocks.length ? stocks.length : i + chunkSize,
      );
      await Future.wait(chunk.map((asset) async {
        final code = fiiIdentifierCode(asset.ticker);
        if (code.isEmpty) return;
        final payload = jsonEncode({'issuingCompany': code, 'language': 'pt-br'});
        final b64 = base64Encode(utf8.encode(payload));
        final uri = Uri.parse(
          'https://sistemaswebb3-listados.b3.com.br/listedCompaniesProxy/CompanyCall/GetListedSupplementCompany/$b64',
        );
        final body = await _httpGetText(uri);
        final events = parseB3StockDividendsJson(asset.ticker, body);
        if (events.isNotEmpty) {
          results[asset.id] = events;
        }
      }));
    }
    return results;
  }
}
