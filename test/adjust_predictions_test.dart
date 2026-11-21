import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  test('modo por fatura: previsao com base na data do mes + gastos de banco do mes + gastos de cartao com fatura no mes', () {
    final store = MoneyStore(autoBoot: false);
    store.db = Database(
      accounts: [
        Account(id: 'bank', name: 'Banco', type: 'Corrente', opening: 0),
        Account(
          id: 'x',
          name: 'Cartão X',
          type: 'Cartão de crédito',
          opening: 0,
          card: CardConfig(closeDay: 25, dueDay: 5, pay: 'bank'),
        ),
      ],
      txs: [
        // Previsão para o mês de Novembro/2026 (mesmo lançada no cartão, vale a data do lançamento)
        Transaction(acc: 'x', date: '2026-11-05', payee: 'Previsão Mercado', cat: 'Mercado', amt: -100000),
        // 1. Gasto Banco em Novembro: R$ 200,00 (dinheiro sai em novembro) -> entra!
        Transaction(acc: 'bank', date: '2026-11-02', payee: 'Mercado A', cat: 'Mercado', amt: -20000),
        // 2. Gasto Cartão em 15/10: fatura vence em 05/11 (ik = 2026-11) -> entra no abatimento de novembro!
        Transaction(acc: 'x', date: '2026-10-15', payee: 'Mercado B', cat: 'Mercado', amt: -30000),
        // 3. Gasto Cartão em 28/11: fatura vence em 05/12 (ik = 2026-12) -> NÃO entra em novembro!
        Transaction(acc: 'x', date: '2026-11-28', payee: 'Mercado C', cat: 'Mercado', amt: -15000),
      ],
      predMode: 'invoice',
    );

    final res = store.adjustPredictions('2026-11');
    expect(res.totalDeductedCents, 50000); // R$ 200 + R$ 300 = R$ 500
    expect(store.db.txs.firstWhere((t) => t.payee.startsWith('Previs')).amt, -50000); // R$ 1000 - R$ 500 = R$ 500
  });

  test('modo por mes padrao: abate apenas despesas com data do proprio mes', () {
    final store = MoneyStore(autoBoot: false);
    store.db = Database(
      accounts: [
        Account(id: 'bank', name: 'Banco', type: 'Corrente', opening: 0),
        Account(
          id: 'x',
          name: 'Cartão X',
          type: 'Cartão de crédito',
          opening: 0,
          card: CardConfig(closeDay: 25, dueDay: 5, pay: 'bank'),
        ),
      ],
      txs: [
        Transaction(acc: 'x', date: '2026-11-05', payee: 'Previsão Mercado', cat: 'Mercado', amt: -100000),
        Transaction(acc: 'bank', date: '2026-11-02', payee: 'Mercado A', cat: 'Mercado', amt: -20000), // Data 11: entra (200)
        Transaction(acc: 'x', date: '2026-10-15', payee: 'Mercado B', cat: 'Mercado', amt: -30000),    // Data 10: não entra
        Transaction(acc: 'x', date: '2026-11-28', payee: 'Mercado C', cat: 'Mercado', amt: -15000),    // Data 11: entra (150)
      ],
      predMode: 'month',
    );

    final res = store.adjustPredictions('2026-11');
    expect(res.totalDeductedCents, 35000); // R$ 200 + R$ 150 = R$ 350
    expect(store.db.txs.firstWhere((t) => t.payee.startsWith('Previs')).amt, -65000); // R$ 1000 - R$ 350 = R$ 650
  });

  test('parametro predMonths define horizonte de meses avaliados para ambos os modos', () {
    final store = MoneyStore(autoBoot: false);
    store.db = Database(
      accounts: [
        Account(id: 'bank', name: 'Banco', type: 'Corrente', opening: 0),
      ],
      txs: [
        // Previsões em 3 meses distintos
        Transaction(acc: 'bank', date: '2026-11-01', payee: 'Previsão Mercado Nov', cat: 'Mercado', amt: -50000),
        Transaction(acc: 'bank', date: '2026-12-01', payee: 'Previsão Mercado Dez', cat: 'Mercado', amt: -50000),
        Transaction(acc: 'bank', date: '2027-01-01', payee: 'Previsão Mercado Jan', cat: 'Mercado', amt: -50000),
        // Despesas reais em cada mês
        Transaction(acc: 'bank', date: '2026-11-10', payee: 'Supermercado 1', cat: 'Mercado', amt: -20000),
        Transaction(acc: 'bank', date: '2026-12-10', payee: 'Supermercado 2', cat: 'Mercado', amt: -30000),
        Transaction(acc: 'bank', date: '2027-01-10', payee: 'Supermercado 3', cat: 'Mercado', amt: -40000),
      ],
      predMode: 'month',
      predMonths: 3,
    );

    expect(store.db.predMonths, 3);

    // Com predMonths = 1, só abate Novembro
    store.setPredMonths(1);
    expect(store.db.predMonths, 1);
    var res = store.adjustPredictions('2026-11');
    expect(res.totalDeductedCents, 20000); // Somente Nov (20000)
    expect(store.db.txs.firstWhere((t) => t.payee == 'Previsão Mercado Nov').amt, -30000);
    expect(store.db.txs.firstWhere((t) => t.payee == 'Previsão Mercado Dez').amt, -50000); // Intacto
    expect(store.db.txs.firstWhere((t) => t.payee == 'Previsão Mercado Jan').amt, -50000); // Intacto

    // Agora com predMonths = 3, avalia Nov + Dez + Jan
    store.setPredMonths(3);
    res = store.adjustPredictions('2026-11');
    // Nov já estava abatido em 20000 (resta 0 a abater nele), Dez abate 30000 e Jan abate 40000
    expect(store.db.txs.firstWhere((t) => t.payee == 'Previsão Mercado Dez').amt, -20000); // 50000 - 30000
    expect(store.db.txs.firstWhere((t) => t.payee == 'Previsão Mercado Jan').amt, -10000); // 50000 - 40000
  });

  test('Database JSON serialization preserves predMonths', () {
    final dbDefault = Database();
    expect(dbDefault.predMonths, 3);
    expect(dbDefault.toJson().containsKey('predMonths'), isFalse); // Omitido quando padrão

    final dbCustom = Database(predMonths: 6);
    expect(dbCustom.predMonths, 6);
    final json = dbCustom.toJson();
    expect(json['predMonths'], 6);

    final restored = Database.fromJson(json);
    expect(restored.predMonths, 6);
  });
}
