import 'dart:math';

import '../models/openmoney_models.dart';
import 'investment_engine.dart';

enum InvestmentInsightSeverity { info, positive, warning, critical }

class InvestmentInsight {
  final String id;
  final InvestmentInsightSeverity severity;
  final String category;
  final String title;
  final String detail;
  final String aiPrompt;

  const InvestmentInsight({
    required this.id,
    required this.severity,
    required this.category,
    required this.title,
    required this.detail,
    required this.aiPrompt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'severity': severity.name,
        'category': category,
        'title': title,
        'detail': detail,
      };
}

class InvestmentInsightsReport {
  final int diversificationScore;
  final String scoreLabel;
  final Map<String, int> fixedIncomeByIndexer;
  final List<InvestmentInsight> insights;

  const InvestmentInsightsReport({
    required this.diversificationScore,
    required this.scoreLabel,
    required this.fixedIncomeByIndexer,
    required this.insights,
  });

  Map<String, dynamic> toAiContextJson({
    required PortfolioSummary summary,
    required int cashBalanceCents,
    required String baseCurrency,
  }) {
    final openPos = summary.positions
        .where((p) => p.hasOpenPosition && !p.asset.inactive)
        .toList();
    final totalGross = summary.totalMarketValueGrossCents;
    return {
      'baseCurrency': baseCurrency,
      'cashBalance': formatCurrency(cashBalanceCents, baseCurrency),
      'appliedCost': formatCurrency(summary.totalCostBasisCents, baseCurrency),
      'grossMarketValue': formatCurrency(totalGross, baseCurrency),
      'estimatedTax': formatCurrency(summary.totalEstimatedTaxCents, baseCurrency),
      'netMarketValue':
          formatCurrency(summary.totalMarketValueNetCents, baseCurrency),
      'totalPatrimony':
          formatCurrency(cashBalanceCents + totalGross, baseCurrency),
      'unrealizedPnl':
          formatCurrency(summary.totalUnrealizedPnlCents, baseCurrency),
      'unrealizedPnlPct':
          double.parse(summary.totalUnrealizedPnlPct.toStringAsFixed(2)),
      'realizedPnl':
          formatCurrency(summary.totalRealizedPnlCents, baseCurrency),
      'totalDividends':
          formatCurrency(summary.totalDividendsCents, baseCurrency),
      'diversificationScore': diversificationScore,
      'diversificationLabel': scoreLabel,
      'allocationByClass': summary.byClass.map(
        (k, v) => MapEntry(
          k.label,
          {
            'value': formatCurrency(v, baseCurrency),
            'sharePct': totalGross > 0
                ? double.parse(((v / totalGross) * 100.0).toStringAsFixed(1))
                : 0.0,
          },
        ),
      ),
      'fixedIncomeByIndexer': fixedIncomeByIndexer.map(
        (k, v) => MapEntry(k, formatCurrency(v, baseCurrency)),
      ),
      'topPositions': openPos.take(12).map((p) {
        final cur = p.asset.currency;
        return {
          'ticker': p.asset.displayCode,
          'class': p.asset.assetClass.label,
          'qty': p.currentQty,
          'avgBuy': formatCurrency(p.avgBuyPriceCents, cur),
          'grossValue': formatCurrency(p.currentGrossValueCents, cur),
          'pnlPct': double.parse(p.unrealizedPnlPct.toStringAsFixed(2)),
          'dividends': formatCurrency(p.totalDividendsCents, cur),
          if (p.asset.isFixedIncome) 'daysHeld': p.daysHeld,
          if (p.asset.isFixedIncome) 'irRatePct': p.irRatePct,
          if (p.asset.maturityDate != null) 'maturityDate': p.asset.maturityDate,
        };
      }).toList(),
      'localInsights': insights.map((i) => i.toJson()).toList(),
    };
  }
}

/// Motor determinístico local de análise e diagnóstico da carteira de investimentos.
/// Executa 100% offline sem custo de API e alimenta a aba Análise & Alocação + Assistente IA.
class InvestmentInsightsEngine {
  static InvestmentInsightsReport analyze({
    required PortfolioSummary summary,
    required int cashBalanceCents,
    required String baseCurrency,
    String? asOfDateIso,
  }) {
    final openPos = summary.positions
        .where((p) => p.hasOpenPosition && !p.asset.inactive)
        .toList();
    final totalGross = summary.totalMarketValueGrossCents;
    final totalPatrimony = cashBalanceCents + totalGross;
    final asOf = _parseIsoSafe(asOfDateIso ?? todayISO());

    if (openPos.isEmpty && cashBalanceCents <= 0) {
      return const InvestmentInsightsReport(
        diversificationScore: 0,
        scoreLabel: 'Sem posições',
        fixedIncomeByIndexer: {},
        insights: [],
      );
    }

    final insights = <InvestmentInsight>[];

    // 1. Score de Diversificação (10..100) + Concentração por ativo/classe
    int score = 100;
    if (openPos.isEmpty) {
      score = 20;
    } else if (totalGross > 0) {
      final topAsset = openPos.first;
      final topAssetPct = (topAsset.currentGrossValueCents / totalGross) * 100.0;
      if (topAssetPct > 40.0) {
        score -= 30;
        insights.add(InvestmentInsight(
          id: 'conc_asset_crit',
          severity: InvestmentInsightSeverity.critical,
          category: 'Concentração',
          title:
              '${topAsset.asset.displayCode} concentra ${topAssetPct.toStringAsFixed(1)}% da carteira',
          detail:
              'Acima de 40% em um único ativo eleva o risco específico. Avalie rebalancear novos aportes.',
          aiPrompt:
              'Meu ativo ${topAsset.asset.displayCode} concentra ${topAssetPct.toStringAsFixed(1)}% da carteira. Como posso rebalancear os próximos aportes?',
        ));
      } else if (topAssetPct >= 25.0) {
        score -= 15;
        insights.add(InvestmentInsight(
          id: 'conc_asset_warn',
          severity: InvestmentInsightSeverity.warning,
          category: 'Concentração',
          title:
              '${topAsset.asset.displayCode} representa ${topAssetPct.toStringAsFixed(1)}% da carteira',
          detail:
              'Posição relevante em um único ativo (acima de 25%). Acompanhe o peso nos próximos aportes.',
          aiPrompt:
              'Analise a concentração de ${topAsset.asset.displayCode} (${topAssetPct.toStringAsFixed(1)}%) na minha carteira.',
        ));
      }

      if (summary.byClass.isNotEmpty) {
        final topClsEntry = summary.byClass.entries
            .reduce((a, b) => a.value >= b.value ? a : b);
        final topClsPct = (topClsEntry.value / totalGross) * 100.0;
        if (topClsPct >= 60.0 && summary.byClass.length == 1) {
          score -= 25;
        } else if (topClsPct >= 65.0) {
          score -= 12;
        }
        if (topClsPct >= 60.0) {
          insights.add(InvestmentInsight(
            id: 'conc_class',
            severity: InvestmentInsightSeverity.warning,
            category: 'Alocação',
            title:
                '${topClsEntry.key.label} soma ${topClsPct.toStringAsFixed(1)}% do portfólio',
            detail:
                'Boa parte do risco está concentrada em uma única classe de ativos.',
            aiPrompt:
                'Minha carteira tem ${topClsPct.toStringAsFixed(1)}% em ${topClsEntry.key.label}. Esse nível de concentração faz sentido?',
          ));
        }
      }

      if (summary.byClass.length < 2) score -= 15;
      if (openPos.length < 4) score -= 15;
    }
    score = max(10, min(100, score));
    final scoreLabel = score >= 80
        ? 'Excelente'
        : score >= 60
            ? 'Equilibrada'
            : score >= 40
                ? 'Moderada'
                : 'Concentrada';

    // 2. Mix de Indexadores em Renda Fixa
    final fixedByIndexer = <String, int>{};
    for (final p in openPos) {
      if (!p.asset.isFixedIncome) continue;
      final idx = p.asset.indexer ?? InvestFixedIncomeIndexer.cdi;
      final key = (idx == InvestFixedIncomeIndexer.cdi ||
              idx == InvestFixedIncomeIndexer.selic)
          ? 'CDI / Selic'
          : idx.label;
      fixedByIndexer[key] =
          (fixedByIndexer[key] ?? 0) + p.currentGrossValueCents;
    }

    // 3. Radar Tributário (IR Regressivo) & Vencimentos próximos (<= 90 dias)
    for (final p in openPos) {
      if (p.asset.isFixedIncome && !p.asset.taxExempt) {
        for (final threshold in const [181, 361, 721]) {
          final rem = threshold - p.daysHeld;
          if (rem > 0 && rem <= 30) {
            final nextRate =
                threshold == 181 ? '20,0%' : (threshold == 361 ? '17,5%' : '15,0%');
            insights.add(InvestmentInsight(
              id: 'ir_drop_${p.asset.id}',
              severity: InvestmentInsightSeverity.info,
              category: 'IR Regressivo',
              title:
                  '${p.asset.displayCode} cai para $nextRate de IR em $rem dia(s)',
              detail:
                  'Atualmente em ${p.irRatePct.toStringAsFixed(1)}% (${p.daysHeld} dias). Se não precisar do recurso agora, aguardar reduz o imposto.',
              aiPrompt:
                  'Vale a pena aguardar $rem dias para resgatar ${p.asset.displayCode} e pagar $nextRate de IR em vez de ${p.irRatePct.toStringAsFixed(1)}%?',
            ));
            break;
          }
        }
      }

      if (p.asset.maturityDate != null && p.asset.maturityDate!.length >= 10) {
        final dMat = _parseIsoSafe(p.asset.maturityDate!);
        final daysToMat = dMat.difference(asOf).inDays;
        if (daysToMat < 0) {
          insights.add(InvestmentInsight(
            id: 'mat_${p.asset.id}',
            severity: InvestmentInsightSeverity.critical,
            category: 'Vencido',
            title:
                '${p.asset.displayCode} venceu há ${daysToMat.abs()} dia(s) (${fmtDate(p.asset.maturityDate!)})',
            detail:
                'Valor bruto estimado de ${formatCurrency(p.currentGrossValueCents, p.asset.currency)}. Registre o resgate para atualizar seu caixa e IR.',
            aiPrompt:
                'Meu título ${p.asset.displayCode} venceu em ${fmtDate(p.asset.maturityDate!)}. Como devo lançar o resgate e reinvestir o valor?',
          ));
        } else if (daysToMat == 0) {
          insights.add(InvestmentInsight(
            id: 'mat_${p.asset.id}',
            severity: InvestmentInsightSeverity.warning,
            category: 'Vencimento',
            title:
                '${p.asset.displayCode} vence hoje (${fmtDate(p.asset.maturityDate!)})',
            detail:
                'Valor bruto estimado de ${formatCurrency(p.currentGrossValueCents, p.asset.currency)}. Confira o crédito líquido na corretora e registre o resgate.',
            aiPrompt:
                'Meu título ${p.asset.displayCode} vence hoje (${fmtDate(p.asset.maturityDate!)}). Quais opções combinam com minha carteira para reinvestir?',
          ));
        } else if (daysToMat <= 90) {
          insights.add(InvestmentInsight(
            id: 'mat_${p.asset.id}',
            severity: InvestmentInsightSeverity.warning,
            category: 'Vencimento',
            title:
                '${p.asset.displayCode} vence em $daysToMat dia(s) (${fmtDate(p.asset.maturityDate!)})',
            detail:
                'Valor bruto atual de ${formatCurrency(p.currentGrossValueCents, p.asset.currency)}. Planeje o reinvestimento antecipadamente.',
            aiPrompt:
                'Meu título ${p.asset.displayCode} vence em ${fmtDate(p.asset.maturityDate!)}. Quais opções combinam com minha carteira para reinvestir?',
          ));
        }
      }
    }

    // 4. Caixa parado em corretoras (>= R$ 1.000 e >= 15% do patrimônio de investimentos)
    if (cashBalanceCents >= 100000 &&
        totalPatrimony > 0 &&
        (cashBalanceCents / totalPatrimony) >= 0.15) {
      final pct = (cashBalanceCents / totalPatrimony) * 100.0;
      insights.add(InvestmentInsight(
        id: 'idle_cash',
        severity: InvestmentInsightSeverity.info,
        category: 'Liquidez',
        title:
            '${formatCurrency(cashBalanceCents, baseCurrency)} em caixa livre (${pct.toStringAsFixed(1)}%)',
        detail:
            'Saldo parado na conta de investimentos sem render em ativos ou reserva remunerada.',
        aiPrompt:
            'Tenho ${formatCurrency(cashBalanceCents, baseCurrency)} parados em caixa na conta de investimentos. Como alocar considerando minha carteira atual?',
      ));
    }

    // 5. Destaques de Performance
    if (openPos.isNotEmpty) {
      final byPnl = List<AssetPositionSummary>.from(openPos)
        ..sort((a, b) => b.unrealizedPnlPct.compareTo(a.unrealizedPnlPct));
      final best = byPnl.first;
      final worst = byPnl.last;
      if (best.unrealizedPnlPct > 0.5) {
        insights.add(InvestmentInsight(
          id: 'best_perf',
          severity: InvestmentInsightSeverity.positive,
          category: 'Desempenho',
          title:
              'Maior alta: ${best.asset.displayCode} (+${best.unrealizedPnlPct.toStringAsFixed(2)}%)',
          detail:
              'Ganho aberto de ${formatCurrency(best.unrealizedPnlCents, best.asset.currency)} sobre o custo aplicado.',
          aiPrompt:
              '${best.asset.displayCode} está com alta de +${best.unrealizedPnlPct.toStringAsFixed(2)}%. Devo manter ou realizar parte do lucro?',
        ));
      }
      if (worst.unrealizedPnlPct < -3.0) {
        insights.add(InvestmentInsight(
          id: 'worst_perf',
          severity: InvestmentInsightSeverity.warning,
          category: 'Desempenho',
          title:
              'Maior baixa: ${worst.asset.displayCode} (${worst.unrealizedPnlPct.toStringAsFixed(2)}%)',
          detail:
              'Desvalorização de ${formatCurrency(worst.unrealizedPnlCents, worst.asset.currency)} frente ao preço médio de compra.',
          aiPrompt:
              '${worst.asset.displayCode} está com ${worst.unrealizedPnlPct.toStringAsFixed(2)}%. Avalie o peso desse ativo na minha carteira.',
        ));
      }
    }

    // 6. Renda Passiva / Proventos
    if (summary.totalDividendsCents > 0) {
      final yoc = summary.totalCostBasisCents > 0
          ? (summary.totalDividendsCents / summary.totalCostBasisCents) * 100.0
          : 0.0;
      insights.add(InvestmentInsight(
        id: 'passive_income',
        severity: InvestmentInsightSeverity.positive,
        category: 'Renda Passiva',
        title:
            'Proventos acumulados: ${formatCurrency(summary.totalDividendsCents, baseCurrency)}',
        detail:
            'Equivalente a ${yoc.toStringAsFixed(2)}% de Yield on Cost sobre o capital atualmente aplicado.',
          aiPrompt:
              'Como posso aumentar minha renda passiva mensal (hoje acumulada em ${formatCurrency(summary.totalDividendsCents, baseCurrency)})?',
      ));
    }

    // 7. Higiene de Cotações (preços manuais ou desatualizados > 7 dias)
    int manualOrStale = 0;
    for (final p in openPos) {
      if (!p.asset.assetClass.isVariableIncome &&
          p.asset.assetClass != InvestAssetClass.tesouro) {
        continue;
      }
      if (p.asset.manualPrice || p.asset.priceUpdatedAt == null) {
        manualOrStale++;
      } else {
        final upd = DateTime.tryParse(p.asset.priceUpdatedAt!);
        if (upd != null && asOf.difference(upd).inDays > 7) {
          manualOrStale++;
        }
      }
    }
    if (manualOrStale > 0) {
      insights.add(InvestmentInsight(
        id: 'stale_quotes',
        severity: InvestmentInsightSeverity.info,
        category: 'Cotações',
        title:
            '$manualOrStale ativo(s) em modo manual ou sem cotação recente (> 7d)',
        detail:
            'Clique em Cotações no topo da tela para atualizar preços de ações, FIIs, criptos e Tesouro Direto.',
        aiPrompt:
            'Resuma quais ativos da minha carteira estão com preço manual ou desatualizado.',
      ));
    }

    return InvestmentInsightsReport(
      diversificationScore: score,
      scoreLabel: scoreLabel,
      fixedIncomeByIndexer: fixedByIndexer,
      insights: insights,
    );
  }

  static DateTime _parseIsoSafe(String iso) {
    try {
      return dateFromISO(iso);
    } catch (_) {
      return DateTime.now();
    }
  }
}
