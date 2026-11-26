import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../models/openmoney_models.dart';

class B3ImportItem {
  final String ticker;
  final String name;
  final InvestAssetClass assetClass;
  final String? subType;
  final InvestOpType opType;
  final String dateIso;
  final double quantity;
  final int unitPriceCents;
  final int totalCents;
  final int? currentPriceCents;
  final String institution;
  final bool isDuplicate;
  bool selected;

  B3ImportItem({
    required this.ticker,
    required this.name,
    required this.assetClass,
    this.subType,
    required this.opType,
    required this.dateIso,
    required this.quantity,
    required this.unitPriceCents,
    required this.totalCents,
    this.currentPriceCents,
    this.institution = '',
    this.isDuplicate = false,
    bool? selected,
  }) : selected = selected ?? !isDuplicate;
}

class B3ParseResult {
  final String mode; // 'position' | 'operations'
  final List<B3ImportItem> items;
  final String? warning;

  const B3ParseResult({
    required this.mode,
    required this.items,
    this.warning,
  });
}

class B3ImportService {
  /// Faz parse de arquivo `.xlsx` ou `.csv` exportado da Área do Investidor B3.
  static B3ParseResult parseBytes(
    Uint8List bytes,
    String fileName, {
    List<InvestOperation> existingOps = const [],
    List<InvestAsset> existingAssets = const [],
  }) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.xlsx')) {
      final sheets = _parseXlsxSheets(bytes);
      if (sheets.isEmpty) {
        return const B3ParseResult(
          mode: 'position',
          items: [],
          warning: 'Nenhuma linha válida encontrada no arquivo.',
        );
      }
      final combinedItems = <B3ImportItem>[];
      String detectedMode = 'position';
      for (final s in sheets) {
        final res = _interpretB3Rows(
          s.rows,
          sheetNameHint: s.name,
          existingOps: existingOps,
          existingAssets: existingAssets,
        );
        if (res.items.isNotEmpty) {
          combinedItems.addAll(res.items);
          if (res.mode == 'operations') detectedMode = 'operations';
        }
      }
      if (combinedItems.isEmpty) {
        return const B3ParseResult(
          mode: 'position',
          items: [],
          warning:
              'Cabeçalho B3 não reconhecido. Exporte "Posição" ou "Negociação/Movimentação" da Área do Investidor B3.',
        );
      }
      return B3ParseResult(mode: detectedMode, items: combinedItems);
    }

    final text = _decodeText(bytes);
    final rows = _parseCsvRows(text);
    if (rows.isEmpty) {
      return const B3ParseResult(
        mode: 'position',
        items: [],
        warning: 'Nenhuma linha válida encontrada no arquivo.',
      );
    }

    return _interpretB3Rows(
      rows,
      existingOps: existingOps,
      existingAssets: existingAssets,
    );
  }

  static String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static List<List<String>> _parseCsvRows(String text) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];
    final sep = lines.first.contains(';') ? ';' : ',';
    return lines.map((line) {
      final cols = <String>[];
      final buf = StringBuffer();
      bool inQuotes = false;
      for (int i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') {
          inQuotes = !inQuotes;
        } else if (ch == sep && !inQuotes) {
          cols.add(buf.toString().trim());
          buf.clear();
        } else {
          buf.write(ch);
        }
      }
      cols.add(buf.toString().trim());
      return cols;
    }).toList();
  }

  static List<({String name, List<List<String>> rows})> _parseXlsxSheets(
      Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final filesByName = <String, ArchiveFile>{
      for (final f in archive.files) f.name: f,
    };

    // 1. Ler sharedStrings.xml
    final sharedStrings = <String>[];
    final ssFile = filesByName['xl/sharedStrings.xml'];
    if (ssFile != null) {
      final xml = utf8.decode(ssFile.content as List<int>, allowMalformed: true);
      final siRegex = RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true);
      final tRegex = RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true);
      for (final m in siRegex.allMatches(xml)) {
        final inner = m.group(1) ?? '';
        final buf = StringBuffer();
        for (final tm in tRegex.allMatches(inner)) {
          buf.write(_unescapeXml(tm.group(1) ?? ''));
        }
        sharedStrings.add(buf.toString());
      }
    }

    // 2. Ler nomes das abas em xl/workbook.xml (ex: "Tesouro Direto", "Acoes", "FII")
    final sheetDisplayNames = <String>[];
    final wbFile = filesByName['xl/workbook.xml'];
    if (wbFile != null) {
      final wbXml =
          utf8.decode(wbFile.content as List<int>, allowMalformed: true);
      final sheetTagRegex = RegExp(r'<sheet\b[^>]*\bname="([^"]+)"', dotAll: true);
      for (final m in sheetTagRegex.allMatches(wbXml)) {
        sheetDisplayNames.add(_unescapeXml(m.group(1) ?? ''));
      }
    }

    // 3. Ler worksheets em ordem preservando cada aba separada
    final sheetFiles = filesByName.keys
        .where((k) => k.startsWith('xl/worksheets/sheet') && k.endsWith('.xml'))
        .toList()
      ..sort((a, b) {
        final na = int.tryParse(RegExp(r'sheet(\d+)\.xml').firstMatch(a)?.group(1) ?? '') ?? 0;
        final nb = int.tryParse(RegExp(r'sheet(\d+)\.xml').firstMatch(b)?.group(1) ?? '') ?? 0;
        return na.compareTo(nb);
      });

    final result = <({String name, List<List<String>> rows})>[];
    for (int i = 0; i < sheetFiles.length; i++) {
      final sheetFile = filesByName[sheetFiles[i]]!;
      final xml =
          utf8.decode(sheetFile.content as List<int>, allowMalformed: true);
      final rows = _extractRowsFromSheetXml(xml, sharedStrings);
      if (rows.length > 1) {
        final name = i < sheetDisplayNames.length
            ? sheetDisplayNames[i]
            : sheetFiles[i];
        result.add((name: name, rows: rows));
      }
    }
    return result;
  }

  static List<List<String>> _extractRowsFromSheetXml(
    String xml,
    List<String> sharedStrings,
  ) {
    final rows = <List<String>>[];
    final rowRegex = RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true);
    final cellRegex = RegExp(
      r'<c\b([^>]*)>(.*?)</c>',
      dotAll: true,
    );
    final valRegex = RegExp(r'<v\b[^>]*>(.*?)</v>', dotAll: true);
    final inlineRegex = RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true);

    for (final rm in rowRegex.allMatches(xml)) {
      final rowBody = rm.group(1) ?? '';
      final cells = <int, String>{};
      int maxCol = -1;
      int fallbackCol = 0;

      for (final cm in cellRegex.allMatches(rowBody)) {
        final attrs = cm.group(1) ?? '';
        final body = cm.group(2) ?? '';
        final refMatch = RegExp(r'r="([A-Z]+)\d+"').firstMatch(attrs);
        final colIdx = refMatch != null
            ? _colLettersToIndex(refMatch.group(1)!)
            : fallbackCol;
        fallbackCol = colIdx + 1;
        if (colIdx > maxCol) maxCol = colIdx;

        final typeMatch = RegExp(r't="([^"]+)"').firstMatch(attrs);
        final cellType = typeMatch?.group(1) ?? '';

        String value = '';
        if (cellType == 'inlineStr') {
          final tm = inlineRegex.firstMatch(body);
          value = _unescapeXml(tm?.group(1) ?? '');
        } else {
          final vm = valRegex.firstMatch(body);
          final rawV = _unescapeXml(vm?.group(1) ?? '');
          if (cellType == 's') {
            final idx = int.tryParse(rawV);
            if (idx != null && idx >= 0 && idx < sharedStrings.length) {
              value = sharedStrings[idx];
            }
          } else {
            value = rawV;
          }
        }
        cells[colIdx] = value.trim();
      }

      if (maxCol >= 0) {
        final rowList = List<String>.generate(
          maxCol + 1,
          (i) => cells[i] ?? '',
        );
        if (rowList.any((c) => c.isNotEmpty)) {
          rows.add(rowList);
        }
      }
    }
    return rows;
  }

  static int _colLettersToIndex(String letters) {
    int idx = 0;
    for (int i = 0; i < letters.length; i++) {
      idx = idx * 26 + (letters.codeUnitAt(i) - 64);
    }
    return idx - 1;
  }

  static String _unescapeXml(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  static B3ParseResult _interpretB3Rows(
    List<List<String>> rows, {
    String sheetNameHint = '',
    required List<InvestOperation> existingOps,
    required List<InvestAsset> existingAssets,
  }) {
    final assetById = {for (final a in existingAssets) a.id: a};
    int headerIdx = -1;
    bool isOperations = false;

    for (int i = 0; i < rows.length && i < 20; i++) {
      final joined = removeDiacritics(rows[i].join(' ')).toLowerCase();
      if ((joined.contains('codigo') ||
              joined.contains('produto') ||
              joined.contains('titulo')) &&
          (joined.contains('quantidade') || joined.contains('qtde'))) {
        headerIdx = i;
        isOperations = joined.contains('data') &&
            (joined.contains('movimentacao') ||
                joined.contains('negocio') ||
                joined.contains('operacao') ||
                joined.contains('entrada/saida') ||
                joined.contains('tipo de movimentacao'));
        break;
      }
    }

    if (headerIdx < 0) {
      return const B3ParseResult(
        mode: 'position',
        items: [],
        warning:
            'Cabeçalho B3 não reconhecido. Exporte "Posição" ou "Negociação/Movimentação" da Área do Investidor B3.',
      );
    }

    final headers = rows[headerIdx]
        .map((h) => removeDiacritics(h).trim().toLowerCase())
        .toList();

    int colOf(List<String> candidates) {
      for (final c in candidates) {
        for (int i = 0; i < headers.length; i++) {
          if (headers[i].contains(c)) return i;
        }
      }
      return -1;
    }

    final cCode = colOf(['codigo de negociacao', 'codigo', 'ticker']);
    final cProd = colOf(['produto', 'ativo', 'titulo']);
    final cQty = colOf(['quantidade', 'qtde']);
    final cPrice = colOf([
      'preco de fechamento',
      'preco unitario',
      'preco medio',
      'preco',
      'valor unitario',
    ]);
    final cTotal = colOf([
      'valor atualizado',
      'valor da operacao',
      'valor aplicado',
      'valor liquido',
      'valor',
    ]);
    final cInst = colOf(['instituicao', 'corretora']);
    final cDate = colOf([
      'data do negocio',
      'data da movimentacao',
      'data da operacao',
      'data de aplicacao',
      'data de compra',
      'data',
    ]);
    final cMove = colOf([
      'tipo de movimentacao',
      'movimentacao',
      'entrada/saida',
      'operacao',
    ]);
    final cTipo = colOf(['tipo', 'categoria', 'classe']);

    final items = <B3ImportItem>[];
    final today = todayISO();

    for (int r = headerIdx + 1; r < rows.length; r++) {
      final row = rows[r];
      String cell(int idx) => (idx >= 0 && idx < row.length) ? row[idx].trim() : '';

      final rawCode = cell(cCode);
      final rawProd = cell(cProd);
      if (rawCode.isEmpty && rawProd.isEmpty) continue;

      final prodNorm = removeDiacritics(rawProd).toLowerCase();
      if (prodNorm.startsWith('total')) continue;

      final ticker = rawCode.isNotEmpty
          ? rawCode.toUpperCase()
          : _extractTickerFromProduct(rawProd);
      final name = rawProd.isNotEmpty ? rawProd : ticker;
      final qty = _parseDoubleBr(cell(cQty));
      if (qty <= 0) continue;

      var unitPriceCents = _parseCentsBr(cell(cPrice));
      var totalCents = _parseCentsBr(cell(cTotal));
      if (unitPriceCents == 0 && totalCents > 0) {
        unitPriceCents = (totalCents / qty).round();
      }
      if (totalCents == 0 && unitPriceCents > 0) {
        totalCents = (qty * unitPriceCents).round();
      }
      if (totalCents <= 0 && unitPriceCents <= 0) continue;

      final cls = _inferAssetClass(
        ticker: ticker,
        product: rawProd,
        tipoHint: cell(cTipo),
        sheetNameHint: sheetNameHint,
      );

      final rawDateCell = cell(cDate);
      final dateIso = rawDateCell.isNotEmpty
          ? _parseDateBr(rawDateCell, today)
          : today;
      final opType = isOperations
          ? _inferOpType(cell(cMove))
          : InvestOpType.initialPosition;

      final isDup = existingOps.any((op) {
        final asset = assetById[op.assetId];
        if (asset == null) return false;
        return asset.displayCode == ticker.toUpperCase() &&
            op.date == dateIso &&
            op.type == opType &&
            (op.quantity - qty).abs() < 1e-6 &&
            (op.totalCents - totalCents).abs() <= 5;
      });

      items.add(B3ImportItem(
        ticker: ticker,
        name: name,
        assetClass: cls,
        subType: cls == InvestAssetClass.tesouro
            ? 'Tesouro Direto'
            : (cls == InvestAssetClass.fixedIncome ? 'CDB' : null),
        opType: opType,
        dateIso: dateIso,
        quantity: qty,
        unitPriceCents: unitPriceCents,
        totalCents: totalCents,
        currentPriceCents: isOperations ? null : unitPriceCents,
        institution: cell(cInst),
        isDuplicate: isDup,
      ));
    }

    return B3ParseResult(
      mode: isOperations ? 'operations' : 'position',
      items: items,
    );
  }

  static String _extractTickerFromProduct(String prod) {
    final m = RegExp(r'\b([A-Z]{4}\d{1,2})\b').firstMatch(prod.toUpperCase());
    if (m != null) return m.group(1)!;
    final parts = prod.split(' - ');
    return parts.first.trim().toUpperCase();
  }

  static InvestAssetClass _inferAssetClass({
    required String ticker,
    required String product,
    required String tipoHint,
    String sheetNameHint = '',
  }) {
    final p = removeDiacritics('$sheetNameHint $product $tipoHint').toLowerCase();
    final t = ticker.toUpperCase();
    if (p.contains('tesouro') ||
        p.contains('lft') ||
        p.contains('ntn-b') ||
        p.contains('ntn-f') ||
        RegExp(r'\b(selic|ipca\+?|prefixado)\s+20\d{2}\b').hasMatch(p)) {
      return InvestAssetClass.tesouro;
    }
    if (p.contains('cdb') ||
        p.contains('rdb') ||
        p.contains('lci') ||
        p.contains('lca') ||
        p.contains('cri') ||
        p.contains('cra') ||
        p.contains('renda fixa') ||
        p.contains('debenture')) {
      return InvestAssetClass.fixedIncome;
    }
    if (p.contains('fii') || p.contains('imobiliario')) {
      return InvestAssetClass.fii;
    }
    if (p.contains('etf')) return InvestAssetClass.etf;
    if (p.contains('bdr') || RegExp(r'^[A-Z]{4}3[245]$').hasMatch(t)) {
      return InvestAssetClass.bdr;
    }
    if (RegExp(r'^[A-Z]{4}11$').hasMatch(t)) {
      return InvestAssetClass.fii;
    }
    if (RegExp(r'^[A-Z]{4}[3456]$').hasMatch(t)) {
      return InvestAssetClass.stock;
    }
    return InvestAssetClass.other;
  }

  static InvestOpType _inferOpType(String raw) {
    final s = removeDiacritics(raw).toLowerCase();
    if (s.contains('venda') || s.contains('resgate')) return InvestOpType.sell;
    if (s.contains('dividendo')) return InvestOpType.dividend;
    if (s.contains('juros') || s.contains('jcp')) return InvestOpType.jcp;
    if (s.contains('rendimento')) return InvestOpType.fiiYield;
    if (s.contains('amortiza')) return InvestOpType.amortization;
    if (s.contains('desdobramento')) return InvestOpType.split;
    if (s.contains('grupamento')) return InvestOpType.inplit;
    if (s.contains('bonifica')) return InvestOpType.bonus;
    return InvestOpType.buy;
  }

  static double _parseDoubleBr(String raw) {
    var clean = raw.trim().replaceAll(' ', '');
    if (clean.isEmpty) return 0.0;
    if (clean.contains(',')) {
      clean = clean.replaceAll('.', '').replaceAll(',', '.');
    }
    clean = clean.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(clean) ?? 0.0;
  }

  static int _parseCentsBr(String raw) {
    final d = _parseDoubleBr(raw);
    return (d * 100.0).round();
  }

  static String _parseDateBr(String raw, String fallback) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return fallback;

    final isoMatch = RegExp(r'^(\d{4})[-/](\d{2})[-/](\d{2})').firstMatch(trimmed);
    if (isoMatch != null) {
      return '${isoMatch.group(1)}-${isoMatch.group(2)}-${isoMatch.group(3)}';
    }

    final brMatch = RegExp(r'^(\d{2})[-/](\d{2})[-/](\d{4})').firstMatch(trimmed);
    if (brMatch != null) {
      return '${brMatch.group(3)}-${brMatch.group(2)}-${brMatch.group(1)}';
    }

    // Número serial de data do Excel (ex: 45730 -> 2025-03-14)
    final serial = double.tryParse(trimmed.replaceAll(',', '.'));
    if (serial != null && serial >= 25000 && serial <= 75000) {
      final dt = DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
      return '${dt.year.toString().padLeft(4, '0')}-${pad2(dt.month)}-${pad2(dt.day)}';
    }

    return fallback;
  }
}
