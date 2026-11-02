import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// MARK: - Markdown Block Types

abstract class MarkdownBlock {
  const MarkdownBlock();
}

class HeadingBlock extends MarkdownBlock {
  final int level;
  final String text;
  const HeadingBlock(this.level, this.text);
}

class ParagraphBlock extends MarkdownBlock {
  final String text;
  const ParagraphBlock(this.text);
}

class BulletBlock extends MarkdownBlock {
  final String text;
  const BulletBlock(this.text);
}

class NumberedBlock extends MarkdownBlock {
  final String num;
  final String text;
  const NumberedBlock(this.num, this.text);
}

class CodeBlock extends MarkdownBlock {
  final String lang;
  final String code;
  const CodeBlock(this.lang, this.code);
}

class QuoteBlock extends MarkdownBlock {
  final String text;
  const QuoteBlock(this.text);
}

class DividerBlock extends MarkdownBlock {
  const DividerBlock();
}

class ImageBlock extends MarkdownBlock {
  final String src;
  final String alt;
  const ImageBlock(this.src, this.alt);
}

// MARK: - Help Section Model

class HelpSection {
  final String id;
  final String title;
  final String parentGroup;
  final IconData icon;
  final String rawMarkdown;
  final List<MarkdownBlock> blocks;
  final int order;

  const HelpSection({
    required this.id,
    required this.title,
    required this.parentGroup,
    required this.icon,
    required this.rawMarkdown,
    required this.blocks,
    required this.order,
  });

  String get cleanTitle {
    var t = title;
    const prefixes = [
      '🌟 ', '📐 ', '🚀 ', '📋 ', '📁 ', '🛠️ ', '📄 ', '✨ ',
      '⚡ ', '💎 ', '⌨️ ', '🔄 ', '💻 ', '🎨 ', '🍏 ', '🪟 '
    ];
    for (final p in prefixes) {
      if (t.startsWith(p)) {
        t = t.substring(p.length);
      }
    }
    return t.trim();
  }
}

// MARK: - Help Manager & Markdown Loader

class HelpManager extends ChangeNotifier {
  static final HelpManager instance = HelpManager._();
  HelpManager._();

  String rawMarkdown = '';
  List<HelpSection> sections = [];
  String sourceDescription = 'Carregando...';
  String? sourcePath;
  DateTime lastLoadedDate = DateTime.now();
  bool isLoaded = false;

  Future<void> reload() async {
    final result = await _loadLiveReadme();
    rawMarkdown = result.content;
    sourceDescription = result.description;
    sourcePath = result.path;
    lastLoadedDate = DateTime.now();
    sections = _parseSections(result.content);
    isLoaded = true;
    notifyListeners();
  }

  Future<({String content, String description, String? path})> _loadLiveReadme() async {
    // 1. Tentar ler diretamente do disco em Desktop
    if (!kIsWeb) {
      try {
        final List<String> candidatePaths = [
          'README.md',
          '../README.md',
        ];

        // Adiciona caminhos relativos ao executável / script
        try {
          final execDir = File(Platform.resolvedExecutable).parent;
          candidatePaths.add('${execDir.path}/README.md');
          candidatePaths.add('${execDir.parent.path}/README.md');
          // No macOS (.app/Contents/MacOS)
          candidatePaths.add('${execDir.parent.parent.parent.path}/README.md');
        } catch (_) {}

        for (final p in candidatePaths) {
          final file = File(p);
          if (file.existsSync()) {
            final content = await file.readAsString();
            if (content.trim().isNotEmpty) {
              return (
                content: content,
                description: 'Arquivo Local ($p)',
                path: file.absolute.path,
              );
            }
          }
        }
      } catch (_) {}
    }

    // 2. Tentar carregar como Asset do bundle Flutter
    try {
      final assetContent = await rootBundle.loadString('README.md');
      if (assetContent.trim().isNotEmpty) {
        return (
          content: assetContent,
          description: 'Recurso Integrado (Bundle Asset)',
          path: null,
        );
      }
    } catch (_) {}

    try {
      final assetContent2 = await rootBundle.loadString('assets/README.md');
      if (assetContent2.trim().isNotEmpty) {
        return (
          content: assetContent2,
          description: 'Recurso Integrado (assets/README.md)',
          path: null,
        );
      }
    } catch (_) {}

    // 3. Fallback incorporado
    return (
      content: _fallbackReadme,
      description: 'Manual Padrão Embutido',
      path: null,
    );
  }

  // MARK: - Markdown Parser into Structured Sections

  List<HelpSection> _parseSections(String markdown) {
    final result = <HelpSection>[];
    final lines = markdown.split(RegExp(r'\r?\n'));

    String currentGroup = 'Geral';
    String currentSectionTitle = 'Visão Geral';
    final currentLines = <String>[];
    bool inCodeBlock = false;
    int order = 0;

    void flushSection() {
      final sectionText = currentLines.join('\n').trim();
      if (sectionText.isNotEmpty) {
        final blocks = _parseBlocks(sectionText);
        final icon = iconForTitle(currentSectionTitle, currentGroup);
        final secId = 'sec-$order-${currentSectionTitle.hashCode}';
        result.add(
          HelpSection(
            id: secId,
            title: currentSectionTitle,
            parentGroup: currentGroup,
            icon: icon,
            rawMarkdown: sectionText,
            blocks: blocks,
            order: order,
          ),
        );
        order++;
      }
      currentLines.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        inCodeBlock = !inCodeBlock;
        currentLines.add(line);
        continue;
      }

      if (inCodeBlock) {
        currentLines.add(line);
        continue;
      }

      if (line.startsWith('## ')) {
        flushSection();
        final groupName = line.substring(3).trim();
        currentGroup = groupName;
        currentSectionTitle = groupName;
        continue;
      }

      if (line.startsWith('### ')) {
        flushSection();
        final subTitle = line.substring(4).trim();
        currentSectionTitle = subTitle;
        continue;
      }

      currentLines.add(line);
    }

    flushSection();
    return result;
  }

  // MARK: - Block Parser

  List<MarkdownBlock> _parseBlocks(String text) {
    final blocks = <MarkdownBlock>[];
    final lines = text.split(RegExp(r'\r?\n'));

    String codeLang = '';
    final codeLines = <String>[];
    bool inCode = false;

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        if (inCode) {
          blocks.add(CodeBlock(codeLang, codeLines.join('\n')));
          codeLines.clear();
          codeLang = '';
          inCode = false;
        } else {
          inCode = true;
          codeLang = trimmed.substring(3).trim();
          codeLines.clear();
        }
        continue;
      }

      if (inCode) {
        codeLines.add(line);
        continue;
      }

      if (trimmed.isEmpty) {
        continue;
      }

      // Imagens HTML: <img src="..." alt="..." />
      if (trimmed.contains('<img')) {
        final srcMatch = RegExp(r'''src=["']([^"']+)["']''').firstMatch(trimmed);
        final altMatch = RegExp(r'''alt=["']([^"']+)["']''').firstMatch(trimmed);
        final src = srcMatch?.group(1) ?? '';
        final alt = altMatch?.group(1) ?? '';
        if (src.isNotEmpty) {
          blocks.add(ImageBlock(src, alt));
          continue;
        }
      }

      // Imagens Markdown: ![alt](src)
      if (trimmed.startsWith('![') && trimmed.contains('](') && trimmed.endsWith(')')) {
        final alt = trimmed.substring(2, trimmed.indexOf(']('));
        final src = trimmed.substring(trimmed.indexOf('](') + 2, trimmed.length - 1);
        blocks.add(ImageBlock(src, alt));
        continue;
      }

      final cleaned = _cleanHtmlTags(trimmed);
      if (cleaned.isEmpty) continue;

      if (cleaned == '---' || cleaned == '***') {
        blocks.add(const DividerBlock());
        continue;
      }

      if (cleaned.startsWith('#### ')) {
        blocks.add(HeadingBlock(4, cleaned.substring(5).trim()));
        continue;
      } else if (cleaned.startsWith('### ')) {
        blocks.add(HeadingBlock(3, cleaned.substring(4).trim()));
        continue;
      } else if (cleaned.startsWith('## ')) {
        blocks.add(HeadingBlock(2, cleaned.substring(3).trim()));
        continue;
      } else if (cleaned.startsWith('# ')) {
        blocks.add(HeadingBlock(1, cleaned.substring(2).trim()));
        continue;
      }

      if (cleaned.startsWith('- ') || cleaned.startsWith('* ')) {
        blocks.add(BulletBlock(cleaned.substring(2).trim()));
        continue;
      }

      final numMatch = RegExp(r'^(\d+\.)\s+(.+)$').firstMatch(cleaned);
      if (numMatch != null) {
        blocks.add(NumberedBlock(numMatch.group(1)!, numMatch.group(2)!));
        continue;
      }

      if (cleaned.startsWith('> ')) {
        blocks.add(QuoteBlock(cleaned.substring(2).trim()));
        continue;
      }

      blocks.add(ParagraphBlock(cleaned));
    }

    if (inCode && codeLines.isNotEmpty) {
      blocks.add(CodeBlock(codeLang, codeLines.join('\n')));
    }

    return blocks;
  }

  String _cleanHtmlTags(String text) {
    var str = text;
    str = str.replaceAll(RegExp(r'</?(strong|b)>', caseSensitive: false), '**');
    str = str.replaceAll(RegExp(r'</?(em|i)>', caseSensitive: false), '*');
    str = str.replaceAll(RegExp(r'<[^>]+>'), '');
    return str.trim();
  }

  // MARK: - Smart Icon Selection

  static IconData iconForTitle(String title, String group) {
    final tLower = title.toLowerCase();
    final lower = '$title $group'.toLowerCase();

    if (lower.contains('regra') ||
        lower.contains('governança') ||
        lower.contains('integridade') ||
        lower.contains('princípio')) {
      return Icons.verified_user_outlined;
    }
    if (tLower.contains('visão') ||
        tLower.contains('geral') ||
        tLower.contains('filosofia') ||
        tLower.contains('característica')) {
      return Icons.auto_awesome;
    }
    if (lower.contains('cartão') || lower.contains('fatura')) {
      return Icons.credit_card;
    }
    if (lower.contains('conta') ||
        lower.contains('patrimônio') ||
        lower.contains('livro-caixa') ||
        lower.contains('extrato')) {
      return Icons.account_balance;
    }
    if (lower.contains('lançamento')) {
      return Icons.receipt_long;
    }
    if (lower.contains('busca') || lower.contains('pesquisa')) {
      return Icons.search;
    }
    if (lower.contains('recorrente') || lower.contains('parcelad')) {
      return Icons.repeat;
    }
    if (lower.contains('transferência')) {
      return Icons.swap_horiz;
    }
    if (lower.contains('categoria')) {
      return Icons.label_outline;
    }
    if (lower.contains('limite') ||
        lower.contains('orçamento') ||
        lower.contains('budget')) {
      return Icons.pie_chart_outline;
    }
    if (lower.contains('fluxo de caixa') || lower.contains('cash flow')) {
      return Icons.table_chart_outlined;
    }
    if (lower.contains('relatório')) {
      return Icons.bar_chart;
    }
    if (lower.contains('importação') ||
        lower.contains('exportação') ||
        lower.contains('csv') ||
        lower.contains('qif')) {
      return Icons.import_export;
    }
    if (lower.contains('base') ||
        lower.contains('nuvem') ||
        lower.contains('banco') ||
        lower.contains('backup')) {
      return Icons.storage;
    }
    if (lower.contains('atalho') ||
        lower.contains('teclado') ||
        lower.contains('usabilidade')) {
      return Icons.keyboard;
    }
    if (lower.contains('atualização') || lower.contains('auto-update')) {
      return Icons.system_update_alt;
    }
    if (lower.contains('instalação') ||
        lower.contains('compilar') ||
        lower.contains('terminal') ||
        lower.contains('ambiente')) {
      return Icons.terminal;
    }
    if (lower.contains('estrutura') || lower.contains('código')) {
      return Icons.folder_open;
    }
    if (lower.contains('identidade') || lower.contains('ícone')) {
      return Icons.palette_outlined;
    }
    if (lower.contains('licença')) {
      return Icons.description_outlined;
    }
    if (lower.contains('coletor') ||
        lower.contains('mobile') ||
        lower.contains('celular')) {
      return Icons.phone_iphone;
    }

    return Icons.menu_book;
  }

  static const String _fallbackReadme = '''
# OpenMoney

## 🌟 Visão Geral e Filosofia
O **OpenMoney** une o rigor contábil do clássico Microsoft Money 99 com o design moderno Liquid Glass.
Seus dados pertencem exclusivamente a você: a base de dados é armazenada em um arquivo `openmoney.json` limpo e legível.

## 💎 Funcionalidades e Recursos Detalhados
### 1. Gestão de Contas e Livro-Caixa
Controle completo de contas correntes, cartões de crédito, poupança, investimentos e dinheiro com saldos reais e previstos.

### 2. Gestão de Cartões de Crédito e Faturas
Ciclo de corte e vencimento com cálculo automático de faturas e pagamentos parciais.

### 3. Central de Contas a Pagar e Receber
Lembretes automáticos com janela de dias, ordenação por urgência e conciliação em 1 clique.

### 4. Matriz de Fluxo de Caixa
Visão matricial por meses, trimestres, semestres e anos, com saldo anterior e final acumulados.

### 5. Relatórios Analíticos Mensais
Receitas à esquerda, despesas à direita, taxa de poupança e exportação em PDF A4.

### 6. Planejamento Financeiro: Limite de Gastos Mensal
Definição de limites de gastos por categoria e alertas visuais de consumo.

## ⌨️ Atalhos de Teclado Globais
- `Cmd/Ctrl + Shift + F`: Busca Global
- `Cmd/Ctrl + Alt + I`: Importar / Exportar (CSV/QIF)
- `Cmd/Ctrl + O`: Gerenciador de Bases
- `Cmd/Ctrl + Shift + B`: Histórico de Backups
- `F1`: Ajuda e Manual do OpenMoney
''';
}
