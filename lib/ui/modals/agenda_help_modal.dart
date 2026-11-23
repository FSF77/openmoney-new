import 'package:flutter/material.dart';
import '../theme/liquid_glass.dart';

Future<void> showAgendaHelpModal(BuildContext context) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final colors = OpenMoneyColors(isDark);

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: colors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      title: Row(
        children: [
          Icon(Icons.calendar_month_outlined, color: colors.accent, size: 24),
          const SizedBox(width: 10),
          Text(
            'Como funciona a Agenda',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A Agenda consolida todos os seus compromissos e pendências financeiras em uma visão diária do mês.',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _buildHelpTopic(
                colors,
                icon: Icons.notifications_active_outlined,
                iconColor: colors.warning,
                title: 'Contas a Pagar e Faturas de Cartão',
                description:
                    'Contas a pagar aparecem na data de vencimento. Compras em cartão de crédito são agrupadas de forma consolidada no dia exato do pagamento da fatura.',
              ),
              const SizedBox(height: 12),
              _buildHelpTopic(
                colors,
                icon: Icons.trending_up,
                iconColor: colors.income,
                title: 'Receitas Previstas',
                description:
                    'Entradas planejadas ou a receber aparecem sinalizadas em verde no calendário, permitindo saber quando o dinheiro vai entrar.',
              ),
              const SizedBox(height: 12),
              _buildHelpTopic(
                colors,
                icon: Icons.check_circle_outline,
                iconColor: colors.accent,
                title: 'Resolva direto pelo Calendário',
                description:
                    'Clique em qualquer item para ver os detalhes e marcar como paga ou recebida em 1 clique, sem precisar sair da Agenda.',
              ),
              const SizedBox(height: 12),
              _buildHelpTopic(
                colors,
                icon: Icons.add_circle_outline,
                iconColor: colors.accent,
                title: 'Lançamentos de Despesas, Receitas e Transferências',
                description:
                    'Utilize os botões dedicados de Nova Despesa, Nova Receita e Transferência no topo ou direto no dia desejado da grade para planejar seus lançamentos.',
              ),
              const SizedBox(height: 12),
              _buildHelpTopic(
                colors,
                icon: Icons.print_outlined,
                iconColor: colors.accentIndigo,
                title: 'Impressão em 1 Página A4 Horizontal',
                description:
                    'Gere a folha de planejamento financeiro mensal em formato paisagem com todos os seus vencimentos organizados.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.accent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Entendi', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

Widget _buildHelpTopic(
  OpenMoneyColors colors, {
  required IconData icon,
  required Color iconColor,
  required String title,
  required String description,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
