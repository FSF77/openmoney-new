import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/models/openmoney_models.dart';
import 'package:openmoney/store/money_store.dart';

void main() {
  MoneyStore build() {
    final store = MoneyStore(autoBoot: false);
    store.db = Database(
      accounts: [
        Account(id: 'a', name: 'Banco A', type: 'Corrente', opening: 0, business: 'Loja'),
        Account(id: 'b', name: 'Banco B', type: 'Corrente', opening: 0),
      ],
      txs: [
        Transaction(acc: 'a', date: '2099-01-10', payee: 'TV "Smart"', cat: 'Casa', amt: -10000, pn: 1, pt: 3),
        Transaction(acc: 'a', date: '2099-02-10', payee: 'TV "Smart"', cat: 'Casa', amt: -10000, pn: 2, pt: 3),
        Transaction(acc: 'a', date: '2099-01-10', payee: 'Conciliada', cat: 'X', amt: -500, pn: 1, pt: 2, rec: true),
        Transaction(acc: 'a', date: '2099-01-10', payee: 'À vista', cat: 'X', amt: -500),
        Transaction(acc: 'a', date: '2099-01-10', payee: 'Receita', cat: 'X', amt: 500, pn: 1, pt: 2),
        Transaction(acc: 'b', date: '2099-01-10', payee: 'Outra', cat: 'X', amt: -700, pn: 1, pt: 2),
      ],
    );
    return store;
  }

  test('installmentItems filtra apenas despesas parceladas em aberto', () {
    final s = build();
    expect(s.installmentItems().length, 3);
    expect(s.installmentItems(accountIds: {'b'}).length, 1);
    expect(s.installmentItems(accountIds: {'a'}).length, 2);
  });

  test('dueBillsCSVString escapa aspas e usa vírgula decimal', () {
    final s = build();
    final csv = s.dueBillsCSVString(s.installmentItems(accountIds: {'a'}));
    expect(csv.startsWith('\uFEFFVencimento;'), isTrue);
    expect(csv.contains('"TV ""Smart"""'), isTrue);
    expect(csv.contains('1/3;-100,00'), isTrue);
  });
}
