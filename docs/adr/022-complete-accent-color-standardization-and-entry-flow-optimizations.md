# ADR 022: Padronização Visual Integral da Cor de Destaque, Eliminação de Resíduos Lilases do M3 e Otimização do Fluxo de Lançamentos e Extratos

**Status:** ✅ Aprovado, Implementado e Validado (Flutter & Swift macOS/iOS)  
**Data:** 13/11/2026  
**Decisores:** Tech Lead / Arquitetura OpenMoney  
**Severidade:** 🟢 Experiência do Usuário / Design System / Produtividade  

---

## 1. Contexto e Motivação

Durante o ciclo de refinamento contínuo da interface multiplataforma do OpenMoney (Flutter Desktop, Web e Mobile), foram identificadas oportunidades de melhoria ergonômica e consistência visual:

1. **Inconsistências Visuais de Cor (Resíduos Lilases do Material 3):**
   - Diversos botões padrão (`OutlinedButton`, `FilledButton`, `SegmentedButton`, `FilterChip`) herdavam a paleta lilás padrão do Material 3 do Flutter quando nenhum esquema abrangente era vinculado às propriedades de `colorScheme` (`primaryContainer`, `secondaryContainer`, etc.) ou a estilos globais de botões.
   - Telas como Extrato da Conta, Fluxo de Caixa, Relatórios, Gestão de Previsões, Pesquisa Global, Categorias e Ajustes apresentavam elementos em lilás discrepantes da cor de destaque customizada pelo usuário (`colors.accent` configurável entre Azul Oceano, Esmeralda, Índigo, Sunset Laranja, Ciano Futurista e Titanium Slate).

2. **Espaço Útil de Visualização no Extrato das Contas:**
   - Usuários com monitores menores ou focados em auditoria de histórico demandavam a capacidade de ocultar o bloco inline de inserção de lançamentos no topo do extrato para maximizar a área vertical de rolagem dos dados.

3. **Eficiência no Fluxo de Inclusão de Transações:**
   - A inclusão manual de transferências exigia navegar pela hierarquia de categorias ou depender de fluxos secundários.
   - Usuários que precisavam lançar múltiplos comprovantes ou recibos em sequência eram obrigados a reabrir o modal repetidamente a cada registro concluído.
   - Na seleção da conta de destino para transferências, contas do tipo Cartão de Crédito apareciam misturadas às contas correntes, gerando ruído na identificação rápida de contas bancárias transacionais.

4. **Visualização das Tags de Metadados no Datagrid:**
   - As tags informativas de lançamentos (recorrência, fatura e previsão) estavam disponíveis na visualização em lista diária, mas não apareciam de forma sutil e harmoniosa na visualização em tabela (Datagrid).

---

## 2. Decisões Arquiteturais e de Design

### 2.1. Padronização Global do Tema Dinâmico (`lib/main.dart`)
- **`ColorScheme.fromSeed` Completo:** Ambos os temas Claro e Escuro agora geram todas as variantes tonais (`primary`, `primaryContainer`, `secondary`, `secondaryContainer`, `tertiary`, `tertiaryContainer`, `onPrimaryContainer`, `onSecondaryContainer`, `onTertiaryContainer`) derivadas matematicamente da cor de destaque ativa (`colors.accent`).
- **Temas Globais de Botões:**
  - `OutlinedButtonThemeData`: `foregroundColor: colors.accent` e borda translúcida com transparência suave `colors.accent.withValues(alpha: 0.35)`.
  - `FilledButtonThemeData`: `backgroundColor: colors.accent` e contraste `foregroundColor: Colors.white`.
  - `SegmentedButtonThemeData`: Fundo de seleção translúcido na cor de destaque (`alpha: 0.18` a `0.20`) com texto e ícone ativos em `colors.accent`.
  - `ChipThemeData`: Fundo do chip selecionado e checkmarks derivados da cor de destaque.
- **Fim dos Tons Lilases:** Eliminação total e definitiva de qualquer resquício de cor lilás em todos os módulos e diálogos da aplicação.

### 2.2. Parâmetro de Ocultação do Bloco Inline de Lançamentos
- Configurado na Central de **Ajustes & Personalização** (`showAccountInlineEntry`):
  - **Habilitado (Padrão):** Exibe a barra rápida de inserção com campos de data, favorecido, categoria e valor no topo do extrato.
  - **Desabilitado:** Oculta completamente o formulário inline, liberando espaço vertical imediato na listagem/datagrid.
  - **Botão Circular `+` no Cabeçalho:** Ao lado do nome da conta e posicionado à direita (junto ao botão de edição da conta), adiciona-se um botão circular translúcido com `+` na cor de destaque para invocar o modal de novo lançamento pré-selecionando a conta atual.

### 2.3. Aperfeiçoamento da Tela de Novo Lançamento
- **Aba Nativa de Transferência (`⇄ Transferência`):** Adicionada no seletor de tipologia (`− Despesa`, `+ Receita`, `⇄ Transferência`), ativando diretamente a seleção de conta de destino e campos cambiais pertinentes.
- **Ordenação Prioritária de Contas de Destino:**
  1. Contas operacionais e bancárias (não-cartão) favoritas.
  2. Contas operacionais e bancárias ativas regulares.
  3. Contas do tipo Cartão de Crédito no final absoluto da lista (favoritas seguidas de ativas).
  4. Exclusão automática da conta de origem.
- **Botão "Salvar e Criar Outro":** Permite registrar a transação, mantendo o modal aberto com foco renovado para cadastros contínuos, preservando a conta selecionada e a data.
- **Botões Dimensionados em Linha Única no Mobile:** Adequação responsiva em dispositivos móveis para que os botões `Cancelar`, `Salvar e Criar Outro` e `Salvar` compartilhem a mesma linha sem deformações ou quebras antiestéticas.

### 2.4. Tags de Recorrência, Fatura e Previsão no Datagrid e Extrato
- Redução de tamanho de fonte e preenchimento para máxima discrição visual.
- Diferenciação semântica entre tags de Fatura e Previsão, evitando confusão de cores.
- Inclusão das tags de metadados na coluna descritiva do modo Datagrid de forma sutil e harmoniosa.

---

## 3. Validação e Conformidade Multi-Stack

1. **OpenMoney Flutter:**
   - 80 testes automatizados cobrindo paridade de ordenação de contas de transferência, persistência de preferências de extrato e componentes de interface (`All tests passed!`).
   - 0 erros no analisador estático (`flutter analyze`).
2. **OpenMoney Swift (macOS & iOS):**
   - Compilação nativa com 0 erros (`Build complete!`).
   - Paridade conceitual e de regras de negócio 100% preservada.
