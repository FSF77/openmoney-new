import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/services/agenda_engine.dart';
import 'package:openmoney/services/pdf_report_generator.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  group('AgendaEngine', () {
    late MoneyStore store;

    setUp(() {
      store = MoneyStore(autoBoot: false);
      store.db = Database(
        accounts: [
          Account(id: 'bank', name: 'Conta Corrente', type: 'Corrente', opening: 0),
          Account(
            id: 'card1',
            name: 'Nubank',
            type: 'Cartão de crédito',
            opening: 0,
            card: CardConfig(closeDay: 25, dueDay: 5, pay: 'bank'),
            invoices: {
              '2026-12': InvoiceInfo(close: '2026-11-25', due: '2026-12-05', pay: 'bank'),
            },
          ),
        ],
        txs: [
          // 1. Conta a pagar em conta corrente (R$ 150,00 no dia 10/12/2026)
          Transaction(
            id: 't1',
            acc: 'bank',
            date: '2026-12-10',
            payee: 'Condomínio',
            cat: 'Moradia',
            amt: -15000,
            rec: false,
          ),
          // 2. Receita prevista em conta corrente (+R$ 5.000,00 no dia 05/12/2026)
          Transaction(
            id: 't2',
            acc: 'bank',
            date: '2026-12-05',
            payee: 'Salário FSF',
            cat: 'Salário',
            amt: 500000,
            rec: false,
          ),
          // 3. Compras no cartão de crédito que caem na fatura de 05/12/2026 (não devem poluir individualmente)
          Transaction(
            id: 'c1',
            acc: 'card1',
            date: '2026-11-15',
            payee: 'Supermercado',
            cat: 'Alimentação',
            amt: -35000, // R$ 350,00
            rec: true,
            ik: '2026-12',
          ),
          Transaction(
            id: 'c2',
            acc: 'card1',
            date: '2026-11-20',
            payee: 'Farmácia',
            cat: 'Saúde',
            amt: -15000, // R$ 150,00
            rec: true,
            ik: '2026-12',
          ),
          // 4. Transferência interna entre contas (não deve aparecer)
          Transaction(
            id: 'x1',
            acc: 'bank',
            peer: 'bank2',
            date: '2026-12-12',
            payee: 'Transferência Poupança',
            cat: 'Transferência',
            amt: -50000,
            rec: false,
            xfer: 'xfer_123',
          ),
        ],
      );
    });

    test('gera entradas da Agenda agrupando faturas de cartão no dia do vencimento', () {
      final entries = AgendaEngine.generateMonthEntries(
        store: store,
        month: '2026-12',
        includeDone: false,
      );

      // Deve ter:
      // 1) Receita no dia 05/12
      // 2) Fatura Nubank no dia 05/12 (R$ 350 + R$ 150 = R$ 500)
      // 3) Condomínio no dia 10/12
      // Não deve ter c1, c2 individuais nem xfer_123
      expect(entries.length, 3);

      final invoiceEntry = entries.firstWhere((e) => e.isInvoice);
      expect(invoiceEntry.title, 'Fatura Nubank');
      expect(invoiceEntry.date, '2026-12-05');
      expect(invoiceEntry.amountCents, 50000); // R$ 500,00 total das compras
      expect(invoiceEntry.isDone, false);

      final billEntry = entries.firstWhere((e) => e.isBill);
      expect(billEntry.title, 'Condomínio');
      expect(billEntry.date, '2026-12-10');
      expect(billEntry.amountCents, 15000);

      final incomeEntry = entries.firstWhere((e) => e.isIncome);
      expect(incomeEntry.title, 'Salário FSF');
      expect(incomeEntry.date, '2026-12-05');
      expect(incomeEntry.amountCents, 500000);
    });

    test('calcula resumo do mes com precisao', () {
      final summary = AgendaEngine.calculateMonthSummary(
        store: store,
        month: '2026-12',
      );

      // A pagar: Fatura (R$ 500) + Condomínio (R$ 150) = R$ 650,00 (65000 cents)
      expect(summary.pendingPayCount, 2);
      expect(summary.pendingPayTotalCents, 65000);

      // A receber: Salário FSF (R$ 5.000,00 = 500000 cents)
      expect(summary.pendingReceiveCount, 1);
      expect(summary.pendingReceiveTotalCents, 500000);
      expect(summary.nextIncomeTitle, 'Salário FSF');
    });

    test('buildGridDays monta dias de Domingo a Sábado cobrindo o mês', () {
      final entries = AgendaEngine.generateMonthEntries(
        store: store,
        month: '2026-12',
        includeDone: false,
      );

      final days = AgendaEngine.buildGridDays(
        month: '2026-12',
        entries: entries,
      );

      // Grade mensal sempre tem 35 ou 42 dias (múltiplo de 7)
      expect(days.length % 7, 0);
      expect(days.first.date.compareTo('2026-12-01') <= 0, true);
      expect(days.last.date.compareTo('2026-12-31') >= 0, true);

      // Dia 05/12 deve ter 2 itens (receita e fatura)
      final day5 = days.firstWhere((d) => d.date == '2026-12-05');
      expect(day5.entries.length, 2);
    });

    test('buildAgendaReportPdfBytes gera PDF valido', () {
      final bytes = PdfReportGenerator.buildAgendaReportPdfBytes(
        store,
        '2026-12',
      );
      expect(bytes.isNotEmpty, true);
      final str = String.fromCharCodes(bytes.take(10));
      expect(str.startsWith('%PDF-1.4'), true);
      File('/tmp/agenda_preview.pdf').writeAsBytesSync(bytes);
    });
  });
}
