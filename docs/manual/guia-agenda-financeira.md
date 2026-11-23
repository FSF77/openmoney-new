# 📅 Guia do Usuário: Agenda / Calendário Financeiro

A **Agenda Financeira** junta suas contas a pagar, faturas de cartão de crédito e receitas previstas em uma única visão diária do mês. Assim você enxerga, dia a dia, tudo o que vem pela frente sem surpresas no saldo.

---

## 1. Passo a Passo Prático de Uso (Perspectiva do Usuário)

### 1.1 Onde Encontrar a Agenda
- **Barra Lateral (Desktop / Tablet):** Clique no item **"Agenda"** (ícone de calendário) localizado no menu de navegação, imediatamente abaixo de **Lançamentos** e acima de *Contas a Pagar & Receber*.
- **Atalho Rápido (Cmd+K / Ctrl+K):** Abra a Paleta de Comandos e digite *"Agenda"* ou *"Calendário"* para navegar instantaneamente.
- **Dispositivos Móveis (Smartphones):** Acesse pelo menu principal ou gaveta de navegação.

### 1.2 Navegação do Mês e Visualização
1. No topo, utilize as setas **‹** e **›** para navegar entre os meses anteriores e futuros.
2. O botão **Hoje** retorna imediatamente para o mês e dia atuais.
3. A grade do calendário organiza os dias de **Domingo a Sábado**:
   - **Bolinhas Laranjas:** Indicam contas a pagar e faturas de cartão com vencimento naquele dia.
   - **Bolinhas Verdes:** Indicam receitas previstas a entrar.
   - **Bolinhas Cinzas:** Indicam itens já quitados/conciliados (visíveis quando o filtro *Concluídos* está ativo).

### 1.3 Resumo Executivo Compacto (2 Linhas)
Logo abaixo do cabeçalho, dois cartões compactos (no mesmo padrão visual da tela de lançamentos) oferecem uma leitura instantânea da saúde do seu mês:
- **A Pagar no Mês:** Total de saídas pendentes com indicador lateral da quantidade de contas e faturas abertas (destacando em vermelho se houver contas atrasadas).
- **A Receber no Mês:** Total de entradas previstas com indicador do número de receitas esperadas.
Ambos ocupam altura mínima (~50px), garantindo que a grade dos dias fique ampla e totalmente visível sem empurrar o conteúdo para fora da tela.

### 1.4 Resolução Rápida Direto pelo Calendário (Fluxo de 1 Clique)
Você não precisa sair da Agenda para dar baixa em suas contas:
1. **Contas a Pagar e Receitas:** Clique sobre a pílula do lançamento na grade. No diálogo que se abre, clique no botão verde **"Marcar como Paga"** ou **"Marcar como Recebida"**. O item é conciliado na hora e os totalizadores do topo se atualizam automaticamente. Se cometeu um engano, basta clicar no item e escolher **"Desmarcar"**.
2. **Faturas de Cartão de Crédito:** As compras do cartão não poluem a grade individualmente; elas aparecem de forma consolidada no dia do **vencimento da fatura**. Ao clicar na fatura, você vê o valor total de compras, o que já foi pago e o saldo pendente, com o botão **"Pagar Fatura"** para realizar o pagamento direto.

### 1.5 Filtros Rápidos do Topo
Chips intuitivos permitem alternar o que você deseja visualizar:
- **● Contas e faturas:** Mostra ou esconde despesas e faturas abertas.
- **● Receitas previstas:** Mostra ou esconde entradas futuras.
- **● Concluídos:** Desativado por padrão para manter a tela limpa. Quando ligado, exibe lançamentos já pagos/recebidos (com traço suave sobre o texto).

### 1.6 Impressão em 1 Página A4 Horizontal (Paisagem)
Clique na opção **"Imprimir"** no topo da tela para exportar ou imprimir uma folha completa de planejamento financeiro mensal:
- Diagramada sob medida para caber em **uma única página A4 horizontal (paisagem)**.
- Traz o cabeçalho executivo, os cartões de controle e a grade diária preenchida com todos os seus vencimentos, sem vazamentos de página ou quebra de linhas.

---

## 2. Ações Rápidas de Lançamento (Despesa, Receita e Transferência)

Seguindo o mesmo padrão consagrado da tela de extrato e fatura (`AccountLedgerView`), a Agenda disponibiliza botões dedicados de ação direta:

- **Nova Despesa (Ícone Vermelho):** Abre o formulário pré-configurado para saída de dinheiro.
- **Nova Receita (Ícone Verde):** Abre o cadastro para previsão de entradas ou salários.
- **Transferência (Ícone Azul/Accent):** Permite programar transferências entre contas bancárias ou aportes.

> [!TIP]
> **Adicionar direto no dia:** Em qualquer dia da grade mensal, clique no botão `+` no canto superior da célula do dia para escolher se deseja registrar uma **Nova Despesa**, **Nova Receita** ou **Nova Transferência** já com aquela data pré-selecionada.

---

## 3. Grade Mensal Otimizada (Design e Usabilidade)

- **Linhas Suaves em Cinza Claro:** As bordas internas dos dias utilizam um tom cinza claro sutil e harmonioso, combinando com a borda externa da moldura do calendário para uma leitura confortável e sem poluição visual.
- **Altura Ampla dos Dias:** Aproveitando a economia de espaço vertical proporcionada pelos cartões de 2 linhas, as células contam com altura generosa.
- **Mais Itens por Dia:** Com tipografia compacta e ajustada, a grade comporta até **4 lançamentos diretamente na célula**, exibindo o botão `+N mais` apenas nos dias com grande volume de movimentações.

---

## 4. Gestão de Segurança e FAQ

### 4.1 Meus lançamentos criados ou alterados na Agenda afetam meus dados reais?
Sim, com total segurança. Lançamentos adicionados pela Agenda ou marcados como pagos utilizam as mesmas regras estritas de persistência, schema `v: 7`, auditoria (`AuditLogManager`) e sincronização híbrida (Sync v2 com Anti-Wipe Guard) do OpenMoney.

### 4.2 O que acontece com compras parceladas no cartão de crédito?
Cada parcela cai automaticamente na fatura do seu respectivo mês de vencimento. Na Agenda, você vê a fatura consolidada no dia em que ela deve ser paga, refletindo com fidelidade a saída real de caixa.

### 4.3 A Agenda funciona offline?
Sim! O motor da Agenda funciona 100% no seu dispositivo (macOS, Windows, iOS, Android ou Web local). Se você utiliza o Cloud Sync v2, as alterações são sincronizadas automaticamente assim que houver conexão.

---

## 5. Detalhamento Técnico e Arquitetura

- **Motor Central:** `lib/services/agenda_engine.dart` (puro e determinístico, responsável pelo cálculo de intervalos de grade, agrupamento de faturas via `invoiceSummary` e totalizadores).
- **Modelos em Memória:** `lib/models/agenda_models.dart` (`AgendaEntry`, `AgendaMonthSummary`).
- **Exportador PDF:** `lib/services/pdf_report_generator.dart` (`buildAgendaReportPdfBytes`, operando com dimensões paisagem 841.89 x 595.28 pt em página única).
- **Interface e Responsividade:** `lib/ui/views/agenda_view.dart` (grade mensal adaptativa, suporte a desktop 4K até mobile compacto sem estouro de layout).
