import 'package:flutter_test/flutter_test.dart';
import '../lib/models/openmoney_models.dart';
import '../lib/services/shortcut_url_service.dart';
import '../lib/store/money_store.dart';

void main() {
  group('ShortcutUrlService Tests', () {
    test('Parseia bloco ?recibo=Data:07/11/2026;Conta: Nubank;Favorecido:Posto;Valor:100.99;', () {
      const rawQuery =
          '?recibo=Data:07/11/2026;Conta: Nubank;Favorecido:Posto;Valor:100.99;';
      final draft = ShortcutUrlService.parseQueryString(rawQuery);
      expect(draft, isNotNull);
      expect(draft!.rawDate, '07/11/2026');
      expect(draft.rawAccount, 'Nubank');
      expect(draft.rawPayee, 'Posto');
      expect(draft.rawAmount, '100.99');
    });

    test('Parseia bloco ?recibo codificado com vírgula decimal e Apple Wallet', () {
      final encoded = Uri.encodeQueryComponent(
        'Data:03/11/2026;Conta:Nubank Mastercard Ultravioleta;Favorecido:Drogasil;Valor:30,99;Nota:Remédio;',
      );
      final draft = ShortcutUrlService.parseQueryString('?recibo=$encoded');
      expect(draft, isNotNull);
      expect(draft!.rawDate, '03/11/2026');
      expect(draft.rawAccount, 'Nubank Mastercard Ultravioleta');
      expect(draft.rawPayee, 'Drogasil');
      expect(draft.rawAmount, '30,99');
      expect(draft.rawMemo, 'Remédio');
    });

    test('Parseia query params individuais (?data=...&conta=...&favorecido=...&valor=...)', () {
      const rawQuery =
          '?data=07/11/2026&conta=Ita%C3%BA&favorecido=Posto%20Ipiranga&valor=250.50';
      final draft = ShortcutUrlService.parseQueryString(rawQuery);
      expect(draft, isNotNull);
      expect(draft!.rawDate, '07/11/2026');
      expect(draft.rawAccount, 'Itaú');
      expect(draft.rawPayee, 'Posto Ipiranga');
      expect(draft.rawAmount, '250.50');
    });

    test('Resolve conta, categoria por histórico, valor em centavos e data ISO no MoneyStore', () {
      final store = MoneyStore(autoBoot: false);
      store.db = Database(
        accounts: [
          Account(id: 'acc_itau', name: 'Itaú Corrente', type: 'Corrente', opening: 0),
          Account(
            id: 'acc_nu_card',
            name: 'Cartão Nubank UV',
            type: kCardType,
            opening: 0,
            card: CardConfig(closeDay: 5, dueDay: 12, pay: 'acc_itau'),
          ),
        ],
        cats: [
          CategoryItem(name: 'Transporte', type: 'Despesa'),
          CategoryItem(name: 'Combustível', parent: 'Transporte', type: 'Despesa'),
          CategoryItem(name: 'Saúde', type: 'Despesa'),
          CategoryItem(name: 'Farmácia', parent: 'Saúde', type: 'Despesa'),
        ],
        txs: [
          Transaction(
            id: 't1',
            acc: 'acc_nu_card',
            date: '2026-10-15',
            payee: 'Posto Shell',
            cat: 'Transporte:Combustível',
            memo: '',
            amt: -15000,
            rec: true,
          ),
        ],
      );
      store.markIndexesDirty();

      final draft = ShortcutUrlService.parseQueryString(
        '?recibo=Data:07/11/2026;Conta: Nubank;Favorecido:Posto;Valor:100.99;',
      )!;
      final resolved = ShortcutUrlService.resolveDraft(draft, store);

      expect(resolved.accountId, 'acc_nu_card');
      expect(resolved.dateIso, '2026-11-07');
      expect(resolved.payee, 'Posto');
      expect(resolved.amountCents, 10099);
      expect(resolved.category, 'Transporte:Combustível');
      expect(resolved.isExpense, isTrue);
    });
  });
}
