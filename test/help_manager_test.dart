import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmoney/services/help_manager.dart';
import 'package:openmoney/store/money_store.dart';
import 'package:openmoney/ui/modals/help_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HelpManager & Markdown Parser Tests', () {
    test('HelpManager inicializa e carrega seções estruturadas', () async {
      final manager = HelpManager.instance;
      await manager.reload();

      expect(manager.isLoaded, isTrue);
      expect(manager.sections, isNotEmpty);
      expect(manager.rawMarkdown, isNotEmpty);

      // Verifica se há seções principais reconhecidas
      final titles = manager.sections.map((s) => s.cleanTitle).toList();
      expect(titles.any((t) => t.contains('Visão Geral') || t.contains('Filosofia')), isTrue);
      expect(titles.any((t) => t.contains('Contas') || t.contains('Cartões') || t.contains('Livro-Caixa')), isTrue);

      // Verifica integridade dos blocos
      final firstSec = manager.sections.first;
      expect(firstSec.id, isNotEmpty);
      expect(firstSec.blocks, isNotEmpty);
      expect(firstSec.icon, isNotNull);
    });

    test('Seleção inteligente de ícones mapeia palavras-chave para Material Icons', () {
      expect(HelpManager.iconForTitle('Visão Geral e Filosofia', 'Geral'), Icons.auto_awesome);
      expect(HelpManager.iconForTitle('Regras de Negócio e Governança', 'Geral'), Icons.verified_user_outlined);
      expect(HelpManager.iconForTitle('Cartão de Crédito e Faturas', 'Módulos'), Icons.credit_card);
      expect(HelpManager.iconForTitle('Gestão de Contas', 'Módulos'), Icons.account_balance);
      expect(HelpManager.iconForTitle('Busca Global', 'Módulos'), Icons.search);
      expect(HelpManager.iconForTitle('Limite de Gastos', 'Planejamento'), Icons.pie_chart_outline);
      expect(HelpManager.iconForTitle('Fluxo de Caixa', 'Planejamento'), Icons.table_chart_outlined);
      expect(HelpManager.iconForTitle('Atalhos de Teclado', 'Geral'), Icons.keyboard);
    });

    test('Limpeza de títulos remove emojis e prefixos visuais', () {
      final sec1 = HelpSection(
        id: '1',
        title: '🌟 Visão Geral',
        parentGroup: 'Geral',
        icon: Icons.star,
        rawMarkdown: 'texto',
        blocks: [],
        order: 0,
      );
      expect(sec1.cleanTitle, 'Visão Geral');

      final sec2 = HelpSection(
        id: '2',
        title: '💎 Funcionalidades',
        parentGroup: 'Geral',
        icon: Icons.star,
        rawMarkdown: 'texto',
        blocks: [],
        order: 1,
      );
      expect(sec2.cleanTitle, 'Funcionalidades');
    });

    testWidgets('HelpModal renderiza cabeçalho, lista de tópicos e detalhes', (tester) async {
      final store = MoneyStore(autoBoot: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showHelpModal(ctx, store),
                child: const Text('Abrir Ajuda'),
              ),
            ),
          ),
        ),
      );

      // Clica para abrir modal
      await tester.tap(find.text('Abrir Ajuda'));
      await tester.pumpAndSettle();

      // Verifica elementos do cabeçalho
      expect(find.text('Ajuda e Manual do OpenMoney'), findsOneWidget);
      expect(find.text('Manual Integrado OpenMoney'), findsOneWidget);
      expect(find.text('Recarregar'), findsOneWidget);
      expect(find.text('Copiar Seção'), findsOneWidget);

      // Verifica campo de busca
      expect(find.byType(TextField), findsOneWidget);

      // Fecha modal clicando no botão fechar (close)
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Ajuda e Manual do OpenMoney'), findsNothing);
    });
  });
}
