import 'dart:convert';
import '../models/openmoney_models.dart';
import 'platform_io.dart';

class HistoricalRateResult {
  final double rateToBrl;
  final String quoteDateIso;
  final String source;

  const HistoricalRateResult({
    required this.rateToBrl,
    required this.quoteDateIso,
    required this.source,
  });
}

class CurrencyRateService {
  static const String apiUrl =
      'https://economia.awesomeapi.com.br/last/USD-BRL,EUR-BRL,CAD-BRL,AUD-BRL,GBP-BRL,PYG-BRL,ARS-BRL,UYU-BRL,CHF-BRL,CLP-BRL';

  static DateTime? _lastFetchAttempt;
  static bool _isFetching = false;
  static final Map<String, HistoricalRateResult> _historicalCache = {};
  static final Map<String, Future<HistoricalRateResult?>> _inFlightHistorical =
      {};

  static String _histCacheKey(String currency, String dateIso) =>
      '${currency.trim().toUpperCase()}|${dateIso.trim()}';

  static HistoricalRateResult? cachedHistoricalRate(
    String currency,
    String dateIso,
  ) {
    final code = currency.trim().toUpperCase();
    if (code == 'BRL') {
      return HistoricalRateResult(
        rateToBrl: 1.0,
        quoteDateIso: dateIso,
        source: 'Base BRL',
      );
    }
    return _historicalCache[_histCacheKey(code, dateIso)];
  }

  /// Faz parse do JSON retornado pela API OData PTAX (`CotacaoMoedaPeriodo`) do BCB.
  static HistoricalRateResult? parseBcbHistoricalJson(
    String body, {
    String fallbackDateIso = '',
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final list = decoded['value'];
      if (list is! List || list.isEmpty) return null;

      final entries = <({double rate, String dt, String dateIso, bool isClose})>[];
      for (final item in list) {
        if (item is! Map) continue;
        final venda = (item['cotacaoVenda'] as num?)?.toDouble();
        final compra = (item['cotacaoCompra'] as num?)?.toDouble();
        final rate = (venda != null && venda > 0)
            ? venda
            : ((compra != null && compra > 0) ? compra : null);
        if (rate == null || rate <= 0) continue;

        final dtStr = item['dataHoraCotacao']?.toString() ?? '';
        final dateIso = dtStr.length >= 10
            ? dtStr.substring(0, 10)
            : fallbackDateIso;
        final tipo = (item['tipoBoletim']?.toString() ?? '').toLowerCase();
        final isClose = tipo.contains('fechamento');
        entries.add((rate: rate, dt: dtStr, dateIso: dateIso, isClose: isClose));
      }

      if (entries.isEmpty) return null;

      // Ordena por data/hora ascendente para pegar o boletim mais recente do período
      entries.sort((a, b) => a.dt.compareTo(b.dt));
      final latestDate = entries.last.dateIso;
      final sameDay = entries.where((e) => e.dateIso == latestDate).toList();
      final chosen = sameDay.lastWhere(
        (e) => e.isClose,
        orElse: () => sameDay.last,
      );

      return HistoricalRateResult(
        rateToBrl: chosen.rate,
        quoteDateIso: chosen.dateIso.isNotEmpty ? chosen.dateIso : fallbackDateIso,
        source: 'BCB PTAX',
      );
    } catch (_) {
      return null;
    }
  }

  /// Faz parse do JSON retornado pelo endpoint `/json/daily/...` da AwesomeAPI.
  static HistoricalRateResult? parseAwesomeHistoricalJson(
    String body, {
    String fallbackDateIso = '',
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List || decoded.isEmpty) return null;
      for (final item in decoded) {
        if (item is! Map) continue;
        final bid = double.tryParse(item['bid']?.toString() ?? '');
        if (bid == null || bid <= 0) continue;
        var qDate = item['create_date']?.toString() ?? '';
        if (qDate.length >= 10) {
          qDate = qDate.substring(0, 10);
        } else {
          final ts = int.tryParse(item['timestamp']?.toString() ?? '');
          if (ts != null && ts > 0) {
            final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
            qDate =
                '${d.year.toString().padLeft(4, '0')}-${pad2(d.month)}-${pad2(d.day)}';
          } else {
            qDate = fallbackDateIso;
          }
        }
        return HistoricalRateResult(
          rateToBrl: bid,
          quoteDateIso: qDate,
          source: 'AwesomeAPI',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Consulta cotação histórica `currency -> BRL` na data `dateIso` (`yyyy-MM-dd`).
  /// Usa janela de 7 dias anteriores para cobrir fins de semana e feriados.
  static Future<HistoricalRateResult?> fetchHistoricalRateToBrl(
    String currency,
    String dateIso,
  ) async {
    final code = currency.trim().toUpperCase();
    final trimmedDate = dateIso.trim();
    if (code.isEmpty || code == 'BRL') {
      return HistoricalRateResult(
        rateToBrl: 1.0,
        quoteDateIso: trimmedDate,
        source: 'Base BRL',
      );
    }
    final key = _histCacheKey(code, trimmedDate);
    final cached = _historicalCache[key];
    if (cached != null) return cached;

    final existingFuture = _inFlightHistorical[key];
    if (existingFuture != null) return existingFuture;

    final fut = _performHistoricalFetch(code, trimmedDate);
    _inFlightHistorical[key] = fut;
    try {
      final res = await fut;
      if (res != null && res.rateToBrl > 0) {
        _historicalCache[key] = res;
      }
      return res;
    } finally {
      _inFlightHistorical.remove(key);
    }
  }

  static Future<HistoricalRateResult?> _performHistoricalFetch(
    String code,
    String dateIso,
  ) async {
    final parts = dateIso.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;

    final endDt = DateTime(y, m, d);
    final startDt = endDt.subtract(const Duration(days: 7));

    final bcbStart =
        '${pad2(startDt.month)}-${pad2(startDt.day)}-${startDt.year.toString().padLeft(4, '0')}';
    final bcbEnd =
        '${pad2(endDt.month)}-${pad2(endDt.day)}-${endDt.year.toString().padLeft(4, '0')}';

    // 1) Tenta PTAX oficial do Banco Central do Brasil (cobre décadas históricas)
    final bcbUri = Uri.parse(
      "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/CotacaoMoedaPeriodo(moeda=@moeda,dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)?@moeda='$code'&@dataInicial='$bcbStart'&@dataFinalCotacao='$bcbEnd'&\$format=json",
    );
    final bcbBody = await _httpGetText(bcbUri);
    if (bcbBody != null) {
      final parsed = parseBcbHistoricalJson(bcbBody, fallbackDateIso: dateIso);
      if (parsed != null) return parsed;
    }

    // 2) Fallback AwesomeAPI diária (útil para moedas regionais como PYG, ARS, UYU, CLP)
    final awStart =
        '${startDt.year.toString().padLeft(4, '0')}${pad2(startDt.month)}${pad2(startDt.day)}';
    final awEnd =
        '${endDt.year.toString().padLeft(4, '0')}${pad2(endDt.month)}${pad2(endDt.day)}';
    final awUri = Uri.parse(
      'https://economia.awesomeapi.com.br/json/daily/$code-BRL/10?start_date=$awStart&end_date=$awEnd',
    );
    final awBody = await _httpGetText(awUri);
    if (awBody != null) {
      final parsed =
          parseAwesomeHistoricalJson(awBody, fallbackDateIso: dateIso);
      if (parsed != null) return parsed;
    }

    return null;
  }

  static Future<String?> _httpGetText(Uri uri) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'OpenMoney-App');
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }
      return await res.transform(utf8.decoder).join();
    } catch (_) {
      return null;
    }
  }

  /// Verifica se o app deve consultar as cotações online (máx 1x ao dia / a cada 24h)
  /// e apenas se existirem contas em moeda diferente da moeda base.
  static bool shouldRefreshOnline(Database db) {
    final base = db.effectiveBaseCurrency;
    final hasForeignAccount =
        db.accounts.any((a) => a.isActive && a.effectiveCurrency != base);

    // Se todas as contas ativas estiverem na moeda base, não gasta requisição
    if (!hasForeignAccount) return false;

    // Se alguma moeda ativa sequer tem cotação registrada, deve buscar
    for (final acc in db.accounts) {
      if (acc.isActive && acc.effectiveCurrency != 'BRL') {
        final existing = db.rates[acc.effectiveCurrency];
        if (existing == null || existing.rate <= 0) return true;
        if (existing.updatedAt.isEmpty) return true;
        try {
          final lastDate = DateTime.parse(existing.updatedAt);
          final diff = DateTime.now().difference(lastDate);
          if (diff.inHours >= 24) return true;
          // Ou se já virou o dia civil
          final now = DateTime.now();
          if (lastDate.year != now.year ||
              lastDate.month != now.month ||
              lastDate.day != now.day) {
            return true;
          }
        } catch (_) {
          return true;
        }
      }
    }
    return false;
  }

  /// Busca as cotações online via AwesomeAPI de forma silenciosa ou forçada
  static Future<Map<String, CurrencyRateInfo>?> fetchOnlineRates({
    bool force = false,
  }) async {
    if (_isFetching) return null;

    final now = DateTime.now();
    if (!force && _lastFetchAttempt != null) {
      // Debounce de 30 segundos mesmo em falha para não bombardear API
      if (now.difference(_lastFetchAttempt!).inSeconds < 30) {
        return null;
      }
    }
    _lastFetchAttempt = now;
    _isFetching = true;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final uri = Uri.parse(apiUrl);
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'OpenMoney-App');
      final res = await req.close();

      if (res.statusCode != 200) {
        return null;
      }

      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final Map<String, CurrencyRateInfo> updatedRates = {};
      final nowIso = now.toIso8601String();

      // AwesomeAPI devolve chaves como "USDBRL", "EURBRL", etc.
      json.forEach((key, val) {
        if (val is Map) {
          final code = (val['code'] as String?)?.toUpperCase() ?? '';
          final codeIn = (val['codein'] as String?)?.toUpperCase() ?? '';
          final bidStr = val['bid']?.toString() ?? '';
          final rateVal = double.tryParse(bidStr);

          if (code.isNotEmpty && codeIn == 'BRL' && rateVal != null && rateVal > 0) {
            updatedRates[code] = CurrencyRateInfo(
              rate: rateVal,
              manual: false,
              updatedAt: nowIso,
              source: 'AwesomeAPI',
            );
          }
        }
      });

      return updatedRates;
    } catch (_) {
      return null;
    } finally {
      _isFetching = false;
    }
  }
}
