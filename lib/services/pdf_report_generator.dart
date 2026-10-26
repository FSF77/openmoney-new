import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/openmoney_models.dart';
import '../services/native_file_picker.dart';
import '../store/money_store.dart';

/// Construtor nativo de documentos PDF 1.4 vetoriais em página A4 (595.28 x 841.89 pt)
class _SimpleA4PdfDocument {
  static const double pageWidth = 595.28;
  static const double pageHeight = 841.89;

  final List<StringBuffer> _pages = [];
  late StringBuffer _current;

  _SimpleA4PdfDocument() {
    newPage();
  }

  void newPage() {
    _current = StringBuffer();
    _pages.add(_current);
  }

  int get pageCount => _pages.length;

  static const Map<int, int> _unicodeToWinAnsi = {
    0x20AC: 0x80, // €
    0x201A: 0x82, // ‚
    0x0192: 0x83, // ƒ
    0x201E: 0x84, // „
    0x2026: 0x85, // …
    0x2020: 0x86, // †
    0x2021: 0x87, // ‡
    0x02C6: 0x88, // ˆ
    0x2030: 0x89, // ‰
    0x0160: 0x8A, // Š
    0x2039: 0x8B, // ‹
    0x0152: 0x8C, // Œ
    0x017D: 0x8E, // Ž
    0x2018: 0x91, // ‘
    0x2019: 0x92, // ’
    0x201C: 0x93, // “
    0x201D: 0x94, // ”
    0x2022: 0x95, // •
    0x2013: 0x96, // –
    0x2014: 0x97, // —
    0x02DC: 0x98, // ˜
    0x2122: 0x99, // ™
    0x0161: 0x9A, // š
    0x203A: 0x9B, // ›
    0x0153: 0x9C, // œ
    0x017E: 0x9E, // ž
    0x0178: 0x9F, // Ÿ
  };

  /// Converte string UTF-8 para literal PDF em WinAnsiEncoding (CP1252 / Latin-1)
  static String _pdfStr(String input) {
    final sanitized = input
        .replaceAll('↳', '›')
        .replaceAll('☑', '[x]')
        .replaceAll('☐', '[ ]')
        .replaceAll('✓', 'OK');

    final sb = StringBuffer('(');
    for (final rune in sanitized.runes) {
      final winAnsiByte = _unicodeToWinAnsi[rune];
      if (winAnsiByte != null) {
        final oct = winAnsiByte.toRadixString(8).padLeft(3, '0');
        sb.write('\\$oct');
      } else if (rune >= 0x20 && rune <= 0x7E) {
        if (rune == 0x28 || rune == 0x29 || rune == 0x5C) {
          sb.write('\\');
        }
        sb.writeCharCode(rune);
      } else if (rune >= 0xA0 && rune <= 0xFF) {
        final oct = rune.toRadixString(8).padLeft(3, '0');
        sb.write('\\$oct');
      } else {
        sb.write('?');
      }
    }
    sb.write(')');
    return sb.toString();
  }

  /// Coordenada Y de topo (0 no topo da página A4) para coordenada PDF (0 na base)
  double _y(double topY) => pageHeight - topY;

  void fillRect(
    double x,
    double topY,
    double w,
    double h, {
    required double r,
    required double g,
    required double b,
  }) {
    final pdfY = _y(topY + h);
    _current.writeln(
      '${r.toStringAsFixed(3)} ${g.toStringAsFixed(3)} ${b.toStringAsFixed(3)} rg',
    );
    _current.writeln(
      '${x.toStringAsFixed(2)} ${pdfY.toStringAsFixed(2)} ${w.toStringAsFixed(2)} ${h.toStringAsFixed(2)} re f',
    );
  }

  void strokeRect(
    double x,
    double topY,
    double w,
    double h, {
    required double r,
    required double g,
    required double b,
    double lineWidth = 0.6,
  }) {
    final pdfY = _y(topY + h);
    _current.writeln('${lineWidth.toStringAsFixed(2)} w');
    _current.writeln(
      '${r.toStringAsFixed(3)} ${g.toStringAsFixed(3)} ${b.toStringAsFixed(3)} RG',
    );
    _current.writeln(
      '${x.toStringAsFixed(2)} ${pdfY.toStringAsFixed(2)} ${w.toStringAsFixed(2)} ${h.toStringAsFixed(2)} re S',
    );
  }

  void drawLine(
    double x1,
    double topY1,
    double x2,
    double topY2, {
    required double r,
    required double g,
    required double b,
    double lineWidth = 0.6,
  }) {
    _current.writeln('${lineWidth.toStringAsFixed(2)} w');
    _current.writeln(
      '${r.toStringAsFixed(3)} ${g.toStringAsFixed(3)} ${b.toStringAsFixed(3)} RG',
    );
    _current.writeln(
      '${x1.toStringAsFixed(2)} ${_y(topY1).toStringAsFixed(2)} m ${x2.toStringAsFixed(2)} ${_y(topY2).toStringAsFixed(2)} l S',
    );
  }

  void drawText(
    String text,
    double x,
    double topY, {
    double fontSize = 9,
    bool bold = false,
    double r = 0.06,
    double g = 0.09,
    double b = 0.16,
    int? maxChars,
  }) {
    var t = text;
    if (maxChars != null && t.length > maxChars) {
      t = '${t.substring(0, maxChars - 1)}...';
    }
    final fontRef = bold ? '/F2' : '/F1';
    final pdfY = _y(topY);
    _current.writeln('BT');
    _current.writeln(
      '${r.toStringAsFixed(3)} ${g.toStringAsFixed(3)} ${b.toStringAsFixed(3)} rg',
    );
    _current.writeln('$fontRef ${fontSize.toStringAsFixed(2)} Tf');
    _current.writeln('${x.toStringAsFixed(2)} ${pdfY.toStringAsFixed(2)} Td');
    _current.writeln('${_pdfStr(t)} Tj');
    _current.writeln('ET');
  }

  void drawTextRight(
    String text,
    double rightX,
    double topY, {
    double fontSize = 9,
    bool bold = false,
    double r = 0.06,
    double g = 0.09,
    double b = 0.16,
  }) {
    final approxWidth = text.length * fontSize * (bold ? 0.54 : 0.50);
    drawText(
      text,
      rightX - approxWidth,
      topY,
      fontSize: fontSize,
      bold: bold,
      r: r,
      g: g,
      b: b,
    );
  }

  Uint8List buildBytes() {
    // Object 1: Catalog
    // Object 2: Pages
    // Object 3: Font Regular (/F1 = Helvetica)
    // Object 4: Font Bold (/F2 = Helvetica-Bold)
    // Objects 5..: Page + Contents pairs
    final objects = <int, String>{};
    final pageIds = <int>[];

    objects[3] =
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>';
    objects[4] =
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>';

    int nextId = 5;
    for (final pageBuf in _pages) {
      final pageObjId = nextId++;
      final contentObjId = nextId++;
      pageIds.add(pageObjId);

      final streamStr = pageBuf.toString();
      final streamLen = latin1.encode(streamStr).length;
      objects[contentObjId] =
          '<< /Length $streamLen >>\nstream\n$streamStr\nendstream';

      objects[pageObjId] = '<< /Type /Page /Parent 2 0 R '
          '/MediaBox [0 0 ${pageWidth.toStringAsFixed(2)} ${pageHeight.toStringAsFixed(2)}] '
          '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
          '/Contents $contentObjId 0 R >>';
    }

    final kidsRefs = pageIds.map((id) => '$id 0 R').join(' ');
    objects[2] =
        '<< /Type /Pages /Kids [$kidsRefs] /Count ${pageIds.length} >>';
    objects[1] = '<< /Type /Catalog /Pages 2 0 R >>';

    final totalObjs = nextId - 1;
    final out = StringBuffer();
    out.write('%PDF-1.4\n');

    final offsets = List<int>.filled(totalObjs + 1, 0);
    for (int id = 1; id <= totalObjs; id++) {
      offsets[id] = latin1.encode(out.toString()).length;
      out.write('$id 0 obj\n${objects[id]}\nendobj\n');
    }

    final xrefOffset = latin1.encode(out.toString()).length;
    out.write('xref\n0 ${totalObjs + 1}\n');
    out.write('0000000000 65535 f \n');
    for (int id = 1; id <= totalObjs; id++) {
      out.write('${offsets[id].toString().padLeft(10, "0")} 00000 n \n');
    }
    out.write(
      'trailer\n<< /Size ${totalObjs + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
    );

    return Uint8List.fromList(latin1.encode(out.toString()));
  }
}

class PdfReportGenerator {
  /// Gera bytes PDF nativos do Relatório Mensal em Página Única A4
  static Uint8List buildMonthlyReportPdfBytes({
    required MoneyStore store,
    required String monthYM,
    required MonthlyReportData data,
  }) {
    final doc = _SimpleA4PdfDocument();
    final now = DateTime.now();
    final emission =
        '${now.day.toString().padLeft(2, "0")}/${now.month.toString().padLeft(2, "0")}/${now.year} ${now.hour.toString().padLeft(2, "0")}:${now.minute.toString().padLeft(2, "0")}';

    const margin = 32.0;
    const contentWidth = _SimpleA4PdfDocument.pageWidth - margin * 2;

    // Header
    doc.drawText(
      'OpenMoney',
      margin,
      36,
      fontSize: 16,
      bold: true,
      r: 0.01,
      g: 0.52,
      b: 0.78,
    );
    doc.drawText(
      'Relatório Analítico Mensal — ${fmtMonth(monthYM)}',
      margin,
      52,
      fontSize: 11,
      bold: true,
      r: 0.20,
      g: 0.25,
      b: 0.33,
    );
    doc.drawTextRight(
      'Base: ${store.databaseDisplayName}',
      margin + contentWidth,
      38,
      fontSize: 8.5,
      r: 0.40,
      g: 0.45,
      b: 0.55,
    );
    doc.drawTextRight(
      'Emissão: $emission',
      margin + contentWidth,
      50,
      fontSize: 8.5,
      r: 0.40,
      g: 0.45,
      b: 0.55,
    );
    doc.drawLine(
      margin,
      60,
      margin + contentWidth,
      60,
      r: 0.01,
      g: 0.52,
      b: 0.78,
      lineWidth: 1.5,
    );

    // 4 KPI Cards
    const kpiTop = 70.0;
    const kpiGap = 8.0;
    const kpiWidth = (contentWidth - kpiGap * 3) / 4;
    const kpiHeight = 42.0;

    void drawKpi(
      int index,
      String title,
      String val,
      double vr,
      double vg,
      double vb,
    ) {
      final x = margin + index * (kpiWidth + kpiGap);
      doc.fillRect(x, kpiTop, kpiWidth, kpiHeight, r: 0.97, g: 0.98, b: 0.99);
      doc.strokeRect(x, kpiTop, kpiWidth, kpiHeight, r: 0.85, g: 0.88, b: 0.92);
      doc.drawText(
        title.toUpperCase(),
        x + 8,
        kpiTop + 14,
        fontSize: 7.5,
        bold: true,
        r: 0.40,
        g: 0.45,
        b: 0.55,
      );
      doc.drawText(
        val,
        x + 8,
        kpiTop + 31,
        fontSize: 11.5,
        bold: true,
        r: vr,
        g: vg,
        b: vb,
      );
    }

    drawKpi(0, 'Receitas do Mês', brl(data.totalIncome), 0.02, 0.59, 0.40);
    drawKpi(1, 'Despesas do Mês', brl(data.totalExpense), 0.88, 0.11, 0.28);
    drawKpi(
      2,
      'Resultado Líquido',
      brl(data.netTotal),
      data.netTotal >= 0 ? 0.02 : 0.88,
      data.netTotal >= 0 ? 0.59 : 0.11,
      data.netTotal >= 0 ? 0.40 : 0.28,
    );
    drawKpi(3, 'Taxa de Poupança', '${data.savingsRate}%', 0.01, 0.52, 0.78);

    // Duas Colunas: Despesas (esquerda) e Receitas (direita)
    // Escalonamento dinâmico para garantir 100% em 1 única página A4
    int countLines(List<CategoryGroupStat> groups) {
      int n = 0;
      for (final g in groups) {
        n += 1 + g.subs.length;
      }
      return n == 0 ? 1 : n;
    }

    final maxLines = [
      countLines(data.expenseGroups),
      countLines(data.incomeGroups),
    ].reduce((a, b) => a > b ? a : b);

    const tableTop = 126.0;
    const footerY = _SimpleA4PdfDocument.pageHeight - 28.0;
    const availableHeight = footerY - tableTop - 28.0;
    final rowH = (availableHeight / maxLines).clamp(9.5, 15.5);
    final fontSize = (rowH * 0.62).clamp(6.8, 8.8);

    const colGap = 16.0;
    const colWidth = (contentWidth - colGap) / 2;

    void drawColumn({
      required double x,
      required String title,
      required int total,
      required List<CategoryGroupStat> groups,
      required double cr,
      required double cg,
      required double cb,
    }) {
      doc.drawText(
        '$title (${brl(total)})',
        x,
        tableTop,
        fontSize: 9.5,
        bold: true,
        r: cr,
        g: cg,
        b: cb,
      );
      doc.drawLine(
        x,
        tableTop + 5,
        x + colWidth,
        tableTop + 5,
        r: cr,
        g: cg,
        b: cb,
        lineWidth: 1.0,
      );

      double y = tableTop + 18;
      if (groups.isEmpty) {
        doc.drawText(
          'Sem movimentações neste período.',
          x + 4,
          y,
          fontSize: 8.5,
          r: 0.45,
          g: 0.50,
          b: 0.58,
        );
        return;
      }

      for (final g in groups) {
        if (y + rowH > footerY - 6) break;
        doc.fillRect(
          x,
          y - rowH * 0.72,
          colWidth,
          rowH,
          r: 0.96,
          g: 0.97,
          b: 0.99,
        );
        doc.drawText(
          g.name,
          x + 4,
          y,
          fontSize: fontSize,
          bold: true,
          maxChars: 28,
        );
        doc.drawTextRight(
          '${brl(g.total)} (${g.percentage}%)',
          x + colWidth - 4,
          y,
          fontSize: fontSize,
          bold: true,
          r: cr,
          g: cg,
          b: cb,
        );
        y += rowH;

        for (final sub in g.subs) {
          if (y + rowH > footerY - 6) break;
          doc.drawText(
            '  › ${sub.name}',
            x + 8,
            y,
            fontSize: fontSize * 0.92,
            r: 0.30,
            g: 0.35,
            b: 0.43,
            maxChars: 30,
          );
          doc.drawTextRight(
            '${brl(sub.amount)} (${sub.percentage}%)',
            x + colWidth - 4,
            y,
            fontSize: fontSize * 0.92,
            r: 0.35,
            g: 0.40,
            b: 0.48,
          );
          y += rowH * 0.92;
        }
      }
    }

    drawColumn(
      x: margin,
      title: 'RECEITAS POR CATEGORIA',
      total: data.totalIncome,
      groups: data.incomeGroups,
      cr: 0.02,
      cg: 0.59,
      cb: 0.40,
    );

    drawColumn(
      x: margin + colWidth + colGap,
      title: 'DESPESAS POR CATEGORIA',
      total: data.totalExpense,
      groups: data.expenseGroups,
      cr: 0.88,
      cg: 0.11,
      cb: 0.28,
    );

    // Footer
    doc.drawLine(
      margin,
      footerY - 10,
      margin + contentWidth,
      footerY - 10,
      r: 0.85,
      g: 0.88,
      b: 0.92,
    );
    doc.drawText(
      'OpenMoney — Relatório Analítico Mensal (A4 Página Única)',
      margin,
      footerY,
      fontSize: 7.5,
      r: 0.50,
      g: 0.55,
      b: 0.62,
    );
    doc.drawTextRight(
      'Exclui rigorosamente transferências entre contas',
      margin + contentWidth,
      footerY,
      fontSize: 7.5,
      r: 0.50,
      g: 0.55,
      b: 0.62,
    );

    return doc.buildBytes();
  }

  /// Gera bytes PDF nativos da Fatura de Cartão ou Extrato Mensal de Conta em A4
  static Uint8List buildStatementOrInvoicePdfBytes({
    required MoneyStore store,
    required Account account,
    required String monthYM,
    required List<Transaction> transactions,
    InvoiceSummary? invoiceSummary,
  }) {
    final doc = _SimpleA4PdfDocument();
    final isCard = account.type == kCardType;
    final title = isCard
        ? 'Fatura de Cartão de Crédito — ${account.name} (${fmtMonth(monthYM)})'
        : 'Extrato Mensal de Conta — ${account.name} (${fmtMonth(monthYM)})';
    final now = DateTime.now();
    final emission =
        '${now.day.toString().padLeft(2, "0")}/${now.month.toString().padLeft(2, "0")}/${now.year} ${now.hour.toString().padLeft(2, "0")}:${now.minute.toString().padLeft(2, "0")}';

    const margin = 32.0;
    const contentWidth = _SimpleA4PdfDocument.pageWidth - margin * 2;
    const footerY = _SimpleA4PdfDocument.pageHeight - 28.0;

    void drawPageHeader(int pageNum) {
      doc.drawText(
        'OpenMoney',
        margin,
        36,
        fontSize: 16,
        bold: true,
        r: 0.01,
        g: 0.52,
        b: 0.78,
      );
      doc.drawText(
        title,
        margin,
        52,
        fontSize: 10.5,
        bold: true,
        r: 0.20,
        g: 0.25,
        b: 0.33,
      );
      doc.drawTextRight(
        'Conta: ${account.name} (${account.type}) • Pág. $pageNum',
        margin + contentWidth,
        38,
        fontSize: 8.5,
        r: 0.40,
        g: 0.45,
        b: 0.55,
      );
      doc.drawTextRight(
        'Emissão: $emission',
        margin + contentWidth,
        50,
        fontSize: 8.5,
        r: 0.40,
        g: 0.45,
        b: 0.55,
      );
      doc.drawLine(
        margin,
        60,
        margin + contentWidth,
        60,
        r: 0.01,
        g: 0.52,
        b: 0.78,
        lineWidth: 1.5,
      );
    }

    int pageNum = 1;
    drawPageHeader(pageNum);
    double y = 72;

    final monthData = !isCard ? store.accountMonthData(account.id, monthYM) : null;
    final openingReal = monthData?.openingReal ?? 0;
    final openingPred = monthData?.openingPred ?? 0;

    int totalCredits = 0;
    int totalDebits = 0;
    int finalReal = openingReal;
    int finalPred = openingPred;
    for (final t in transactions) {
      if (t.amt >= 0) {
        totalCredits += t.amt;
      } else {
        totalDebits += t.amt.abs();
      }
      if (t.rec) finalReal += t.amt;
      finalPred += t.amt;
    }

    if (isCard && invoiceSummary != null) {
      doc.fillRect(margin, y, contentWidth, 38, r: 0.96, g: 0.97, b: 0.99);
      doc.strokeRect(margin, y, contentWidth, 38, r: 0.85, g: 0.88, b: 0.92);
      doc.drawText(
        'Fechamento: ${fmtDate(invoiceSummary.closeDate)}   |   Vencimento: ${fmtDate(invoiceSummary.dueDate)}   |   Conta Débito: ${invoiceSummary.payAccountName}',
        margin + 8,
        y + 14,
        fontSize: 8.5,
        bold: true,
      );
      final statusTag = invoiceSummary.isFullyPaid ? ' [LIQUIDADA]' : '';
      doc.drawText(
        'Total Fatura: ${brl(invoiceSummary.chargesCents)}   |   Pago: ${brl(invoiceSummary.paymentsCents)}   |   Em Aberto: ${brl(invoiceSummary.remainingCents)}$statusTag',
        margin + 8,
        y + 29,
        fontSize: 8.5,
        bold: true,
        r: 0.01,
        g: 0.52,
        b: 0.78,
      );
      y += 48;
    } else if (!isCard) {
      // Cabeçalho de Saldos do Extrato de Conta (Saldo Inicial, Entradas, Saídas, Saldo Final Real e Previsto)
      doc.fillRect(margin, y, contentWidth, 38, r: 0.96, g: 0.97, b: 0.99);
      doc.strokeRect(margin, y, contentWidth, 38, r: 0.85, g: 0.88, b: 0.92);
      doc.drawText(
        'Saldo Inicial do Período: Real ${brl(openingReal)}${openingPred != openingReal ? " (Previsto: ${brl(openingPred)})" : ""}   |   Entradas (+): ${brl(totalCredits)}   |   Saídas (-): ${brl(totalDebits)}',
        margin + 8,
        y + 14,
        fontSize: 8.2,
        bold: true,
      );
      doc.drawText(
        'Saldo Final Real: ${brl(finalReal)}   |   Saldo Final Previsto: ${brl(finalPred)}',
        margin + 8,
        y + 29,
        fontSize: 8.5,
        bold: true,
        r: finalReal >= 0 ? 0.02 : 0.88,
        g: finalReal >= 0 ? 0.59 : 0.11,
        b: finalReal >= 0 ? 0.40 : 0.28,
      );
      y += 48;
    }

    void drawTableHeader(double topY) {
      doc.fillRect(margin, topY, contentWidth, 16, r: 0.94, g: 0.96, b: 0.98);
      doc.drawText('St', margin + 4, topY + 11, fontSize: 8, bold: true);
      doc.drawText('Data', margin + 28, topY + 11, fontSize: 8, bold: true);
      doc.drawText(
        'Favorecido / Notas',
        margin + 86,
        topY + 11,
        fontSize: 8,
        bold: true,
      );
      doc.drawText(
        'Categoria',
        margin + 305,
        topY + 11,
        fontSize: 8,
        bold: true,
      );
      doc.drawTextRight(
        'Valor (R\$)',
        margin + contentWidth - 4,
        topY + 11,
        fontSize: 8,
        bold: true,
      );
      doc.drawLine(
        margin,
        topY + 16,
        margin + contentWidth,
        topY + 16,
        r: 0.75,
        g: 0.80,
        b: 0.86,
      );
    }

    drawTableHeader(y);
    y += 26;

    void drawTxRow(Transaction t) {
      final cleanMemo = t.memo.trim();
      final hasMemo = cleanMemo.isNotEmpty;
      final neededHeight = hasMemo ? 22.0 : 14.0;

      if (y + neededHeight > footerY - 36) {
        doc.newPage();
        pageNum++;
        drawPageHeader(pageNum);
        y = 72;
        drawTableHeader(y);
        y += 26;
      }

      final isIncome = t.amt >= 0;
      doc.drawText(
        t.rec ? '[x]' : '[ ]',
        margin + 4,
        y,
        fontSize: 7.5,
        r: t.rec ? 0.02 : 0.55,
        g: t.rec ? 0.59 : 0.60,
        b: t.rec ? 0.40 : 0.65,
      );
      doc.drawText(fmtDate(t.date), margin + 28, y, fontSize: 8);
      // 1ª linha: Favorecido / Descrição
      doc.drawText(
        t.payee,
        margin + 86,
        y,
        fontSize: 8,
        bold: true,
        maxChars: 42,
      );
      // 2ª linha: Campo Notas (se preenchido)
      if (hasMemo) {
        doc.drawText(
          cleanMemo,
          margin + 86,
          y + 8.5,
          fontSize: 7.0,
          r: 0.42,
          g: 0.47,
          b: 0.55,
          maxChars: 52,
        );
      }
      doc.drawText(
        t.cat,
        margin + 305,
        y,
        fontSize: 7.8,
        r: 0.30,
        g: 0.35,
        b: 0.43,
        maxChars: 30,
      );
      doc.drawTextRight(
        brl(t.amt),
        margin + contentWidth - 4,
        y,
        fontSize: 8.2,
        bold: true,
        r: isIncome ? 0.02 : 0.88,
        g: isIncome ? 0.59 : 0.11,
        b: isIncome ? 0.40 : 0.28,
      );
      final sepY = hasMemo ? (y + 12.5) : (y + 4.0);
      doc.drawLine(
        margin,
        sepY,
        margin + contentWidth,
        sepY,
        r: 0.93,
        g: 0.95,
        b: 0.97,
      );
      y += neededHeight;
    }

    if (isCard) {
      for (final t in transactions) {
        drawTxRow(t);
      }
      final totalPeriod = transactions.fold<int>(0, (s, t) => s + t.amt);
      y += 6;
      doc.drawLine(
        margin,
        y - 8,
        margin + contentWidth,
        y - 8,
        r: 0.10,
        g: 0.15,
        b: 0.25,
        lineWidth: 1.2,
      );
      doc.drawTextRight(
        'Total da Fatura (${transactions.length} lanç.): ${brl(totalPeriod)}',
        margin + contentWidth - 4,
        y + 4,
        fontSize: 10,
        bold: true,
        r: totalPeriod >= 0 ? 0.02 : 0.88,
        g: totalPeriod >= 0 ? 0.59 : 0.11,
        b: totalPeriod >= 0 ? 0.40 : 0.28,
      );
    } else {
      // Extrato de Conta: agrupar por dia e exibir o Saldo no fim de cada dia
      int runningReal = openingReal;
      int runningPred = openingPred;

      for (int i = 0; i < transactions.length; i++) {
        final t = transactions[i];
        if (t.rec) runningReal += t.amt;
        runningPred += t.amt;

        drawTxRow(t);

        final isLastOfDay = (i == transactions.length - 1) ||
            (transactions[i + 1].date != t.date);
        if (isLastOfDay) {
          if (y + 16 > footerY - 36) {
            doc.newPage();
            pageNum++;
            drawPageHeader(pageNum);
            y = 72;
            drawTableHeader(y);
            y += 26;
          }
          // Faixa de Saldo do Dia
          doc.fillRect(
            margin,
            y - 9,
            contentWidth,
            14,
            r: 0.94,
            g: 0.96,
            b: 0.98,
          );
          doc.drawText(
            '${fmtDate(t.date)} · ${weekdayShort(t.date).toUpperCase()} — Saldo no fim do dia',
            margin + 6,
            y + 1,
            fontSize: 7.5,
            bold: true,
            r: 0.25,
            g: 0.30,
            b: 0.40,
          );
          doc.drawTextRight(
            'Saldo Real: ${brl(runningReal)}   |   Previsto: ${brl(runningPred)}',
            margin + contentWidth - 6,
            y + 1,
            fontSize: 7.8,
            bold: true,
            r: runningReal >= 0 ? 0.02 : 0.88,
            g: runningReal >= 0 ? 0.59 : 0.11,
            b: runningReal >= 0 ? 0.40 : 0.28,
          );
          y += 16;
        }
      }

      // Bloco Final com Saldo Inicial, Entradas/Saídas e Saldo Final Real e Previsto
      if (y + 44 > footerY - 12) {
        doc.newPage();
        pageNum++;
        drawPageHeader(pageNum);
        y = 72;
      }
      y += 4;
      doc.fillRect(margin, y, contentWidth, 38, r: 0.95, g: 0.97, b: 0.99);
      doc.strokeRect(margin, y, contentWidth, 38, r: 0.78, g: 0.83, b: 0.90);
      doc.drawText(
        'Saldo Inicial: Real ${brl(openingReal)} (Previsto: ${brl(openingPred)})   |   Entradas: +${brl(totalCredits)}   |   Saídas: -${brl(totalDebits)}',
        margin + 8,
        y + 14,
        fontSize: 8.0,
        bold: true,
        r: 0.25,
        g: 0.30,
        b: 0.38,
      );
      doc.drawText(
        'SALDO FINAL REAL: ${brl(finalReal)}     |     SALDO FINAL PREVISTO: ${brl(finalPred)}',
        margin + 8,
        y + 29,
        fontSize: 9.2,
        bold: true,
        r: finalReal >= 0 ? 0.02 : 0.88,
        g: finalReal >= 0 ? 0.59 : 0.11,
        b: finalReal >= 0 ? 0.40 : 0.28,
      );
    }

    return doc.buildBytes();
  }

  /// Exporta bytes PDF para arquivo escolhido pelo usuário e abre no visualizador do sistema
  static Future<void> saveAndOpenPdfBytes(
    BuildContext context, {
    required Uint8List pdfBytes,
    required String defaultFileName,
  }) async {
    try {
      final cleanName = defaultFileName
          .replaceAll(RegExp(r'\.html$', caseSensitive: false), '.pdf');
      final finalDefault =
          cleanName.toLowerCase().endsWith('.pdf') ? cleanName : '$cleanName.pdf';

      final savePath = await NativeFilePicker.saveFile(
        title: 'Salvar Documento PDF A4',
        defaultName: finalDefault,
        allowedExtensions: ['pdf'],
      );

      if (savePath != null && savePath.isNotEmpty) {
        final f = File(savePath);
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(pdfBytes, flush: true);

        if (Platform.isMacOS) {
          await Process.run('open', [savePath]);
        } else if (Platform.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', savePath]);
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ PDF exportado com sucesso em:\n$savePath'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exportar PDF: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
