import 'dart:convert';
import '../models/openmoney_models.dart';
import 'platform_io.dart';

class CurrencyRateService {
  static const String apiUrl =
      'https://economia.awesomeapi.com.br/last/USD-BRL,EUR-BRL,CAD-BRL,AUD-BRL,GBP-BRL,PYG-BRL,ARS-BRL,UYU-BRL,CHF-BRL,CLP-BRL';

  static DateTime? _lastFetchAttempt;
  static bool _isFetching = false;

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
