import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  group('Budget Limit Verification Tests (Parity)', () {
    late MoneyStore store;

    setUp(() {
      store = MoneyStore(autoBoot: false);
      store.saveAccount(
        name: 'Conta Corrente',
        type: 'Conta Corrente',
        openingCents: 100000,
        closeDay: 0,
        dueDay: 0,
        payAccId: '',
      );
    });

    test('1. Retorna null quando categoria não possui limite definido no orçamento', () {
      final acc = store.db.accounts.first;
      final check = store.checkBudgetExceeded(
        accId: acc.id,
        date: '2026-11-12',
        catSelection: 'Lazer',
        signedAmt: -50000,
      );
      expect(check, isNull);
    });

    test('2. Retorna null para lançamentos de receita e transferências', () {
      final acc = store.db.accounts.first;
      store.setBudget('Salário', 100000);
      store.setBudget('Alimentação', 100000);

      // Receita com categoria que tem limite (>0)
      final checkIncome = store.checkBudgetExceeded(
        accId: acc.id,
        date: '2026-11-12',
        catSelection: 'Salário',
        signedAmt: 150000,
      );
      expect(checkIncome, isNull);

      // Transferência entre contas
      final checkXfer = store.checkBudgetExceeded(
        accId: acc.id,
        date: '2026-11-12',
        catSelection: 'xfer:other_acc',
        signedAmt: -150000,
      );
      expect(checkXfer, isNull);
    });

    test('3. Retorna null quando o gasto está dentro do limite definido', () {
      final acc = store.db.accounts.first;
      store.setBudget('Alimentação', 50000); // R$ 500,00

      // Primeiro gasto de R$ 200,00
      store.addTransaction(
        accId: acc.id,
        date: '2026-11-05',
        payee: 'Restaurante A',
        catSelection: 'Alimentação',
        memo: '',
        signedAmt: -20000,
      );

      // Novo gasto de R$ 250,00 (Total: R$ 450,00 <= R$ 500,00)
      final check = store.checkBudgetExceeded(
        accId: acc.id,
        date: '2026-11-12',
        catSelection: 'Alimentação',
        signedAmt: -25000,
      );
      expect(check, isNull);
    });

    test('4. Retorna BudgetCheckResult com cálculos corretos quando gasto ultrapassa o limite', () {
      final acc = store.db.accounts.first;
      store.setBudget('Alimentação', 50000); // R$ 500,00

      // Gasto anterior de R$ 400,00 no mês 2026-11
      store.addTransaction(
        accId: acc.id,
        date: '2026-11-05',
        payee: 'Restaurante A',
        catSelection: 'Alimentação',
        memo: '',
        signedAmt: -40000,
      );

      // Gasto em outro mês (2026-10) que não deve influenciar novembro
      store.addTransaction(
        accId: acc.id,
        date: '2026-10-20',
        payee: 'Restaurante Outubro',
        catSelection: 'Alimentação',
        memo: '',
        signedAmt: -30000,
      );

      // Novo gasto de R$ 150,00 em novembro (Total: R$ 550,00 > R$ 500,00)
      final check = store.checkBudgetExceeded(
        accId: acc.id,
        date: '2026-11-12',
        catSelection: 'Alimentação',
        signedAmt: -15000,
      );

      expect(check, isNotNull);
      expect(check!.categoryPath, 'Alimentação');
      expect(check.budgetCents, 50000);
      expect(check.currentSpentCents, 40000);
      expect(check.newAmountCents, 15000);
      expect(check.availableBeforeCents, 10000);
      expect(check.totalProjectedCents, 55000);
      expect(check.excessCents, 5000);
      expect(check.month, '2026-11');
    });

    test('5. Subcategoria sem limite próprio herda e valida o limite da categoria pai', () {
      final acc = store.db.accounts.first;
      store.setBudget('Transporte', 60000); // R$ 600,00 no pai

      // Gasto em Transporte › Combustível
      store.addTransaction(
        accId: acc.id,
        date: '2026-11-02',
        payee: 'Posto Shell',
        catSelection: 'Transporte › Combustível',
        memo: '',
        signedAmt: -45000, // R$ 450,00
      );

      // Novo gasto em Transporte › Estacionamento de R$ 200,00 (Total: R$ 650,00 > R$ 600,00)
      final check = store.checkBudgetExceeded(
        accId: acc.id,
        date: '2026-11-10',
        catSelection: 'Transporte › Estacionamento',
        signedAmt: -20000,
      );

      expect(check, isNotNull);
      expect(check!.categoryPath, 'Transporte');
      expect(check.budgetCents, 60000);
      expect(check.currentSpentCents, 45000);
      expect(check.newAmountCents, 20000);
      expect(check.availableBeforeCents, 15000);
      expect(check.totalProjectedCents, 65000);
      expect(check.excessCents, 5000);
    });

    test('6. Subcategoria com limite próprio prioriza seu teto individual', () {
      final acc = store.db.accounts.first;
      store.setBudget('Saúde', 100000); // R$ 1.000,00 no pai
      store.setBudget('Saúde › Farmácia', 20000); // R$ 200,00 na subcategoria

      // Gasto de R$ 150,00 em Farmácia
      store.addTransaction(
        accId: acc.id,
        date: '2026-11-03',
        payee: 'Drogaria Raia',
        catSelection: 'Saúde › Farmácia',
        memo: '',
        signedAmt: -15000,
      );

      // Novo gasto de R$ 100,00 em Farmácia (Total: R$ 250,00 > R$ 200,00 da subcategoria)
      final check = store.checkBudgetExceeded(
        accId: acc.id,
        date: '2026-11-12',
        catSelection: 'Saúde › Farmácia',
        signedAmt: -10000,
      );

      expect(check, isNotNull);
      expect(check!.categoryPath, 'Saúde › Farmácia');
      expect(check.budgetCents, 20000);
      expect(check.currentSpentCents, 15000);
      expect(check.newAmountCents, 10000);
      expect(check.availableBeforeCents, 5000);
      expect(check.excessCents, 5000);
    });

    test('7. Parcelamento avalia o impacto da parcela no mês da data do lançamento', () {
      final acc = store.db.accounts.first;
      store.setBudget('Educação', 30000); // R$ 300,00

      // Compra parcelada de R$ 1.000,00 em 5x (parcela de R$ 200,00/mês <= R$ 300,00)
      final checkWithin = store.checkBudgetExceeded(
        accId: acc.id,
        date: '2026-11-15',
        catSelection: 'Educação',
        signedAmt: -100000,
        mode: 'installment',
        installments: 5,
      );
      expect(checkWithin, isNull);

      // Compra parcelada de R$ 800,00 em 2x (parcela de R$ 400,00/mês > R$ 300,00)
      final checkExceeded = store.checkBudgetExceeded(
        accId: acc.id,
        date: '2026-11-15',
        catSelection: 'Educação',
        signedAmt: -80000,
        mode: 'installment',
        installments: 2,
      );
      expect(checkExceeded, isNotNull);
      expect(checkExceeded!.newAmountCents, 40000);
      expect(checkExceeded.excessCents, 10000);
    });

    test('8. Lançamentos de Previsões são ignorados e não somados no gasto da categoria', () {
      final acc = store.db.accounts.first;
      store.setBudget('Lazer', 50000); // R$ 500,00

      // Lançamento com favorecido "Previsão Lazer" de R$ 400,00
      store.addTransaction(
        accId: acc.id,
        date: '2026-11-01',
        payee: 'Previsão Lazer',
        catSelection: 'Lazer',
        memo: '',
        signedAmt: -40000,
      );

      // Gasto real de R$ 100,00
      store.addTransaction(
        accId: acc.id,
        date: '2026-11-05',
        payee: 'Cinema',
        catSelection: 'Lazer',
        memo: '',
        signedAmt: -10000,
      );

      // Novo gasto real de R$ 200,00
      // Se Previsão fosse somada, gasto seria 400 + 100 + 200 = 700 (> 500).
      // Mas como Previsões NÃO entram na soma, gasto real é 100 + 200 = 300 (<= 500).
      final check = store.checkBudgetExceeded(
        accId: acc.id,
        date: '2026-11-12',
        catSelection: 'Lazer',
        signedAmt: -20000,
        payee: 'Restaurante Final de Semana',
      );
      expect(check, isNull);

      // Cadastrar uma nova previsão também não deve disparar alerta de limite de gastos
      final checkNewPred = store.checkBudgetExceeded(
        accId: acc.id,
        date: '2026-11-12',
        catSelection: 'Lazer',
        signedAmt: -80000,
        payee: 'Previsão Viagem',
      );
      expect(checkNewPred, isNull);
    });
  });
}
