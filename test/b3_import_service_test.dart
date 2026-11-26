import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/b3_import_service.dart';

void main() {
  group('B3ImportService', () {
    test('Faz parse de CSV de Posição B3 corretamente', () {
      const csv = 'Produto;Código de Negociação;Instituição;Quantidade;Preço de Fechamento;Valor Atualizado\n'
          'PETR4 - PETROBRAS;PETR4;XP INVESTIMENTOS;100;38,50;3.850,00\n'
          'HGLG11 - CSHG LOG;HGLG11;XP INVESTIMENTOS;20;160,00;3.200,00\n';

      final res = B3ImportService.parseBytes(
        Uint8List.fromList(utf8.encode(csv)),
        'posicao_b3.csv',
      );
      expect(res.mode, 'position');
      expect(res.items.length, 2);
      expect(res.items[0].ticker, 'PETR4');
      expect(res.items[0].assetClass, InvestAssetClass.stock);
      expect(res.items[0].quantity, 100);
      expect(res.items[0].unitPriceCents, 3850);
      expect(res.items[1].ticker, 'HGLG11');
      expect(res.items[1].assetClass, InvestAssetClass.fii);
    });

    test('Faz parse de XLSX (ZIP + XML) da B3 corretamente', () {
      final archive = Archive();
      const sharedStrings = '''<?xml version="1.0" encoding="UTF-8"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <si><t>Código de Negociação</t></si>
  <si><t>Produto</t></si>
  <si><t>Quantidade</t></si>
  <si><t>Preço</t></si>
  <si><t>Valor Atualizado</t></si>
  <si><t>ITUB4</t></si>
  <si><t>ITAU UNIBANCO</t></si>
</sst>''';
      const sheet1 = '''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="s"><v>0</v></c>
      <c r="B1" t="s"><v>1</v></c>
      <c r="C1" t="s"><v>2</v></c>
      <c r="D1" t="s"><v>3</v></c>
      <c r="E1" t="s"><v>4</v></c>
    </row>
    <row r="2">
      <c r="A2" t="s"><v>5</v></c>
      <c r="B2" t="s"><v>6</v></c>
      <c r="C2"><v>50</v></c>
      <c r="D2"><v>32.5</v></c>
      <c r="E2"><v>1625</v></c>
    </row>
  </sheetData>
</worksheet>''';

      archive.addFile(ArchiveFile(
        'xl/sharedStrings.xml',
        utf8.encode(sharedStrings).length,
        utf8.encode(sharedStrings),
      ));
      archive.addFile(ArchiveFile(
        'xl/worksheets/sheet1.xml',
        utf8.encode(sheet1).length,
        utf8.encode(sheet1),
      ));
      final xlsxBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      final res = B3ImportService.parseBytes(xlsxBytes, 'b3_posicao.xlsx');
      expect(res.items.length, 1);
      expect(res.items.first.ticker, 'ITUB4');
      expect(res.items.first.assetClass, InvestAssetClass.stock);
      expect(res.items.first.quantity, 50);
      expect(res.items.first.totalCents, 162500);
    });

    test('XLSX multi-aba B3 classifica Tesouro Direto e converte data serial do Excel', () {
      final archive = Archive();
      const workbookXml = '''<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheets>
    <sheet name="Acoes" sheetId="1"/>
    <sheet name="Tesouro Direto" sheetId="2"/>
  </sheets>
</workbook>''';
      const sharedStrings = '''<?xml version="1.0" encoding="UTF-8"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <si><t>Código de Negociação</t></si>
  <si><t>Produto</t></si>
  <si><t>Quantidade</t></si>
  <si><t>Valor Atualizado</t></si>
  <si><t>PETR4</t></si>
  <si><t>PETROBRAS</t></si>
  <si><t>Data da Movimentação</t></si>
  <si><t>Tipo de Movimentação</t></si>
  <si><t>Tesouro Selic 2029</t></si>
  <si><t>Compra</t></si>
</sst>''';
      const sheet1 = '''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="s"><v>0</v></c>
      <c r="B1" t="s"><v>1</v></c>
      <c r="C1" t="s"><v>2</v></c>
      <c r="D1" t="s"><v>3</v></c>
    </row>
    <row r="2">
      <c r="A2" t="s"><v>4</v></c>
      <c r="B2" t="s"><v>5</v></c>
      <c r="C2"><v>10</v></c>
      <c r="D2"><v>380</v></c>
    </row>
  </sheetData>
</worksheet>''';
      // 45730 = 2025-03-14 em serial Excel
      const sheet2 = '''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="s"><v>6</v></c>
      <c r="B1" t="s"><v>7</v></c>
      <c r="C1" t="s"><v>1</v></c>
      <c r="D1" t="s"><v>2</v></c>
      <c r="E1" t="s"><v>3</v></c>
    </row>
    <row r="2">
      <c r="A2"><v>45730</v></c>
      <c r="B2" t="s"><v>9</v></c>
      <c r="C2" t="s"><v>8</v></c>
      <c r="D2"><v>0.5</v></c>
      <c r="E2"><v>7500</v></c>
    </row>
  </sheetData>
</worksheet>''';

      archive.addFile(ArchiveFile('xl/workbook.xml',
          utf8.encode(workbookXml).length, utf8.encode(workbookXml)));
      archive.addFile(ArchiveFile('xl/sharedStrings.xml',
          utf8.encode(sharedStrings).length, utf8.encode(sharedStrings)));
      archive.addFile(ArchiveFile('xl/worksheets/sheet1.xml',
          utf8.encode(sheet1).length, utf8.encode(sheet1)));
      archive.addFile(ArchiveFile('xl/worksheets/sheet2.xml',
          utf8.encode(sheet2).length, utf8.encode(sheet2)));

      final xlsxBytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final res = B3ImportService.parseBytes(xlsxBytes, 'b3_multi.xlsx');

      expect(res.items.length, 2);
      expect(res.items[0].assetClass, InvestAssetClass.stock);
      expect(res.items[1].assetClass, InvestAssetClass.tesouro);
      expect(res.items[1].dateIso, '2025-03-14');
      expect(res.items[1].opType, InvestOpType.buy);
    });
  });
}
