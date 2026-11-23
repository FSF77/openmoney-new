import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/services/agenda_quick_parser.dart';

void main() {
  group('AgendaQuickParser', () {
    final ref = DateTime(2026, 12, 1); // Terça-feira, 01/12/2026

    test('parse conta a pagar com dia do mes e valor', () {
      final res = AgendaQuickParser.parse('Luz 180 dia 15', referenceDate: ref);
      expect(res, isNotNull);
      expect(res!.title, 'Luz');
      expect(res.amountCents, -18000); // Despesa
      expect(res.date, '2026-12-15');
      expect(res.isIncome, false);
    });

    test('parse receita com palavra-chave salario', () {
      final res = AgendaQuickParser.parse('Salário 5000 dia 5', referenceDate: ref);
      expect(res, isNotNull);
      expect(res!.title, 'Salário');
      expect(res.amountCents, 500000); // Receita
      expect(res.date, '2026-12-05');
      expect(res.isIncome, true);
    });

    test('parse com amanhã', () {
      final res = AgendaQuickParser.parse('Consultoria 2500 amanhã', referenceDate: ref);
      expect(res, isNotNull);
      expect(res!.title, 'Consultoria');
      expect(res.amountCents, 250000);
      expect(res.date, '2026-12-02');
      expect(res.isIncome, true); // Consultoria é keyword de receita
    });

    test('parse com sexta-feira', () {
      // 01/12/2026 é terça. A próxima sexta é dia 04/12/2026
      final res = AgendaQuickParser.parse('Mercado 350 sexta', referenceDate: ref);
      expect(res, isNotNull);
      expect(res!.title, 'Mercado');
      expect(res.amountCents, -35000);
      expect(res.date, '2026-12-04');
      expect(res.isIncome, false);
    });

    test('parse com formato R\$ e decimais', () {
      final res = AgendaQuickParser.parse('Condomínio R\$ 654,44 dia 10', referenceDate: ref);
      expect(res, isNotNull);
      expect(res!.title, 'Condomínio');
      expect(res.amountCents, -65444);
      expect(res.date, '2026-12-10');
      expect(res.isIncome, false);
    });

    test('parse com data barra DD/MM/AAAA', () {
      final res = AgendaQuickParser.parse('Dentista 250 20/12/2026', referenceDate: ref);
      expect(res, isNotNull);
      expect(res!.title, 'Dentista');
      expect(res.amountCents, -25000);
      expect(res.date, '2026-12-20');
      expect(res.isIncome, false);
    });

    test('parse com prefixo explícito de receita', () {
      final res = AgendaQuickParser.parse('+ Venda de Celular 1200 dia 18', referenceDate: ref);
      expect(res, isNotNull);
      expect(res!.title, 'Venda de Celular');
      expect(res.amountCents, 120000);
      expect(res.date, '2026-12-18');
      expect(res.isIncome, true);
    });
  });
}
