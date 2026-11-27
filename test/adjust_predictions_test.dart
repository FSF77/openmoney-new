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

  test('abatimento considera por padrao o mes atual real e verifica quando mes selecionado ultrapassa predMonths', () {
    final store = MoneyStore(autoBoot: false);
    store.db = Database(
      accounts: [
        Account(id: 'bank', name: 'Banco', type: 'Corrente', opening: 0),
      ],
      predMode: 'month',
      predMonths: 3,
    );

    // Mês atual de referência: 2026-11
    // Com predMonths = 3, o horizonte a partir do mês atual cobre: 2026-11, 2026-12 e 2027-01
    expect(store.predictionsHorizonEndMonth(baseMonthYM: '2026-11'), '2027-01');

    // Mês passado (2026-10), mês atual (2026-11) e meses dentro da janela (2026-12, 2027-01) NÃO ultrapassam o horizonte
    expect(
      store.isSelectedMonthBeyondPredictionsHorizon('2026-10', currentMonthOverride: '2026-11'),
      isFalse,
    );
    expect(
      store.isSelectedMonthBeyondPredictionsHorizon('2026-11', currentMonthOverride: '2026-11'),
      isFalse,
    );
    expect(
      store.isSelectedMonthBeyondPredictionsHorizon('2026-12', currentMonthOverride: '2026-11'),
      isFalse,
    );
    expect(
      store.isSelectedMonthBeyondPredictionsHorizon('2027-01', currentMonthOverride: '2026-11'),
      isFalse,
    );

    // Mesmo que useSelectedWhenBeyond seja true, meses dentro ou anteriores ao horizonte sempre iniciam no mês atual real
    expect(
      store.resolvePredictionsStartMonth(
        selectedMonthYM: '2026-10',
        currentMonthOverride: '2026-11',
        useSelectedWhenBeyond: true,
      ),
      '2026-11',
    );
    expect(
      store.resolvePredictionsStartMonth(
        selectedMonthYM: '2027-01',
        currentMonthOverride: '2026-11',
        useSelectedWhenBeyond: true,
      ),
      '2026-11',
    );

    // Mês selecionado além do horizonte de 3 meses (2027-02 em diante) -> ultrapassa predMonths!
    expect(
      store.isSelectedMonthBeyondPredictionsHorizon('2027-02', currentMonthOverride: '2026-11'),
      isTrue,
    );
    expect(
      store.resolvePredictionsStartMonth(
        selectedMonthYM: '2027-02',
        currentMonthOverride: '2026-11',
        useSelectedWhenBeyond: false,
      ),
      '2026-11',
    );
    expect(
      store.resolvePredictionsStartMonth(
        selectedMonthYM: '2027-02',
        currentMonthOverride: '2026-11',
        useSelectedWhenBeyond: true,
      ),
      '2027-02',
    );

    // Com predMonths = 1, o horizonte a partir de 2026-11 cobre apenas 2026-11; 2026-12 já ultrapassa
    store.setPredMonths(1);
    expect(store.predictionsHorizonEndMonth(baseMonthYM: '2026-11'), '2026-11');
    expect(
      store.isSelectedMonthBeyondPredictionsHorizon('2026-11', currentMonthOverride: '2026-11'),
      isFalse,
    );
    expect(
      store.isSelectedMonthBeyondPredictionsHorizon('2026-12', currentMonthOverride: '2026-11'),
      isTrue,
    );
  });

  test('previsao com valor R\$ 0 nao sofre nenhum ajuste e nao volta o saldo mesmo que gastos sejam menores que a base', () {
    final store = MoneyStore(autoBoot: false);
    store.db = Database(
      accounts: [
        Account(id: 'bank', name: 'Banco', type: 'Corrente', opening: 0),
      ],
      txs: [
        // Previsão já com valor 0 (zerada manualmente ou por execução anterior), mas com base de R$ 1.000,00 no memo
        Transaction(
          id: 'p_zero',
          acc: 'bank',
          date: '2026-11-05',
          payee: 'Previsão Mercado',
          cat: 'Mercado',
          memo: '[Previsão base: R\$ 1.000,00]',
          amt: 0,
        ),
        // Gasto na categoria de apenas R$ 300,00 (ainda haveria R$ 700,00 de saldo teórico)
        Transaction(
          id: 'g1',
          acc: 'bank',
          date: '2026-11-10',
          payee: 'Supermercado',
          cat: 'Mercado',
          amt: -30000,
        ),
        // Outra previsão ativa com saldo > 0 para confirmar que apenas a zerada é ignorada
        Transaction(
          id: 'p_ativa',
          acc: 'bank',
          date: '2026-11-05',
          payee: 'Previsão Farmácia',
          cat: 'Farmácia',
          memo: '[Previsão base: R\$ 200,00]',
          amt: -20000,
        ),
        Transaction(
          id: 'g2',
          acc: 'bank',
          date: '2026-11-12',
          payee: 'Drogaria',
          cat: 'Farmácia',
          amt: -5000,
        ),
      ],
      predMode: 'month',
      predMonths: 1,
    );

    final res = store.adjustPredictions('2026-11');

    // A previsão que estava com R$ 0 permanece exatamente com R$ 0 (não volta para -70000)
    final predZero = store.db.txs.firstWhere((t) => t.id == 'p_zero');
    expect(predZero.amt, 0);

    // A previsão ativa de Farmácia foi abatida normalmente de -20000 para -15000
    final predAtiva = store.db.txs.firstWhere((t) => t.id == 'p_ativa');
    expect(predAtiva.amt, -15000);
    expect(res.totalDeductedCents, 5000);
    expect(res.items.length, 1);
    expect(res.items.first.payee, 'Previsão Farmácia');
  });
}
