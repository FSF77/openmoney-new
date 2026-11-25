# Guia do Usuário: Boas-Vindas e Primeiros Passos

Guia completo e direto para começar a usar o **OpenMoney** em minutos (disponível para **macOS, Windows, Web e Mobile**).

---

## 1. 🌟 O que é o OpenMoney?

Um sistema moderno de controle financeiro pessoal e patrimonial. Você registra o que **entra** (receitas), o que **sai** (despesas) e o que **movimenta entre contas** (transferências), acompanhando saldos reais, previsões, faturas de cartão de crédito, fluxo de caixa e relatórios com precisão de centavos.

O OpenMoney funciona em **operação híbrida**:

- 💻 **Modo Local (100% Offline):** seus dados ficam salvos em um arquivo único no seu computador (`openmoney.json`), sem cadastro nem servidor. Se quiser compartilhar entre dois computadores no modo local, basta salvar o arquivo em uma pasta na nuvem (iCloud Drive, OneDrive, Dropbox ou Google Drive).
- ☁️ **Modo Online (OpenMoney Cloud — Sync v2):** sincronização automática em tempo real entre computador, celular e navegador (`https://openmoney.app.br`), com criptografia por usuário (`AES-256-GCM`), fila offline e backups automáticos na nuvem (veja o [Guia de Sincronização Cloud](guia-sincronizacao-cloud.md)).

### Primeira abertura
Ao abrir o aplicativo pela primeira vez sem uma base configurada, a tela de boas-vindas permite escolher entre:
1. **Abrir base local existente (`.json`)**
2. **Criar nova base local (`.json`)**
3. **Conectar em Conta Online / Criar Conta Online** (OpenMoney Cloud)

No Desktop, você pode alternar entre **Local** e **Online** a qualquer momento pelo seletor no rodapé da barra lateral.

> 🔒 **Autenticação e Proteção:** A tela de login conta com preenchimento automático para **1Password, Bitwarden e Apple Chaves**, login com 1 clique por **Chave-senha (Passkey)** e opção de **Bloqueio Biométrico por Touch ID / Windows Hello** ao abrir o aplicativo (veja o [Guia de Autofill, Chaves-senha e Bloqueio Biométrico](guia-autofill-passkeys-e-biometria.md)).

---

## 2. 🧭 Conhecendo a tela

Na barra lateral (expansível ou no modo compacto *Mini Rail*), você encontra:

| Seção / Item | Para que serve |
|---|---|
| **Dashboard Geral** | Painel executivo (cockpit) com patrimônio consolidado, contas, investimentos, cartões, radar de vencimentos, gastos por categoria e ações rápidas |
| **+ Novo Lançamento** | Atalho rápido para registrar despesa, receita ou transferência em qualquer conta |
| **Contas** *(Favoritas, Ativas, Inativas)* | Extrato individual de cada conta bancária, carteira, investimento ou cartão de crédito |
| **Planejamento › Lançamentos** | Visão consolidada de todas as contas com filtros por dia/mês/ano, categoria, tag, tipo, conciliação e edição em lote |
| **Planejamento › Contas a Pagar & Receber** | Agenda de vencimentos próximos e atrasados com conciliação em 1 clique |
| **Planejamento › Compras Parceladas** | Acompanhamento de todos os parcelamentos em aberto |
| **Planejamento › Fluxo de Caixa** | Quadro matricial mês a mês (ou diário/trimestral/semestral/anual) de entradas, saídas, saldo anterior e saldo acumulado |
| **Planejamento › Relatórios** | Distribuição de receitas e despesas por categoria/subcategoria e taxa de poupança |
| **Planejamento › Previsões** | Controle centralizado de reservas orçamentárias mensais (teto previsto, abatido e saldo remanescente) |
| **Planejamento › Limite de Gastos** | Metas mensais por categoria com alerta preventivo ao registrar despesas |
| **Planejamento › Pesquisa Global** | Busca em toda a base de dados (`Cmd + Shift + F`) por descrição, categoria, nota, tag ou valor |
| **Módulos** | **Categorias e Subcategorias**, **Tags**, **Ajustes & Personalização**, **Gestão de Contas**, **Backups de Segurança**, **Logs de Alterações**, **Importação / Exportação**, **Cloud & Sincronização** e **Excluir Lançamentos** |

---

## 3. ✅ Passo a passo para começar

1. Crie sua(s) **conta(s) corrente(s)** e carteira.
2. Cadastre seus **cartões de crédito**.
3. Dê uma olhada nas **Categorias** e personalize **Tags** se desejar.
4. Faça seus primeiros lançamentos.
5. Acompanhe o **Dashboard Geral**, o **Fluxo de Caixa** e os **Relatórios**.

---

## 4. 🏦 Criar uma conta corrente (ou carteira / investimento)

1. Na barra lateral, clique em **+ Nova Conta** (ou acesse **Módulos › Gestão de Contas**).
2. Preencha:
   - **Nome da Conta:** ex.: *Itaú*, *Nubank*, *Carteira*.
   - **Tipo de Conta:** **Corrente**, **Poupança**, **Investimento**, **Dinheiro** ou **Cartão de crédito**.
   - **Moeda:** padrão **BRL (`R$`)**, ou qualquer uma das 11 moedas suportadas (`USD`, `EUR`, `CAD`, `AUD`, `GBP`, `PYG`, `ARS`, `UYU`, `CHF`, `CLP`).
   - **Saldo Inicial de Abertura:** quanto havia na conta na data em que você começou a controlar.
   - **Favoritar Conta** *(opcional)*: fixa a conta no grupo **Favoritas ★** no topo da barra lateral e do Dashboard.
3. Clique em **Salvar**.

> 💡 **Dica:** Abra o app do seu banco e informe o saldo real da data de início. Assim o saldo do OpenMoney bate exatamente com o banco desde o primeiro dia.

---

## 5. ✍️ Fazer lançamentos

Entre em uma conta e use a **barra de inserção rápida** no topo do extrato, ou clique em **+ Novo Lançamento** (no cabeçalho ou barra lateral):

1. **Tipo:** escolha **`− Despesa`**, **`+ Receita`** ou **`⇄ Transferência`**.
   - *Dica:* quando a barra rápida de inserção estiver oculta no extrato da conta, três botões rápidos coloridos (**−**, **+**, **⇄**) ficam disponíveis no cabeçalho ao lado do ícone de edição da conta, abrindo o formulário já com a opção selecionada.
2. **Data:** conta com **preenchimento automático da barra (`/`)**: basta digitar os números do dia e mês (ex.: `15112026`) que o app insere as barras instantaneamente. Em dispositivos móveis (smartphone, iPad e tablets), tocar no campo abre diretamente o **teclado numérico** do sistema. O campo possui validação de calendário estrita (impede dias ou meses impossíveis como 31/02 ou mês 13) e exibe um alerta preventivo se a data for anterior a mais de 30 dias ou posterior a mais de 12 meses da data atual, solicitando confirmação para evitar lançamentos acidentais em datas incorretas.
3. **Favorecido / Descrição:** ex.: *Supermercado*. Ao digitar, o app busca no histórico respeitando o tipo ativo (despesas mostram apenas despesas; receitas mostram apenas receitas), exclui automaticamente previsões do histórico de sugestões, remove números de parcela antigos (como `1/3`, `8/12`, `(7/24)`) para sugerir apenas o nome limpo e preenche a categoria correspondente. Em **Ajustes**, você pode personalizar o tempo de verificação do histórico (ex.: últimos 90 dias) e o escopo de sugestão. Ao selecionar **Transferência**, a descrição é preenchida automaticamente como *"Transferência"*.
4. **Categoria** (ou **Conta de Destino**, no caso de transferência).
5. **Valor:** conta com **calculadora integrada** e acionamento direto do **teclado numérico** (com separador decimal) em smartphones, iPads e tablets. Você pode digitar expressões matemáticas diretamente no teclado físico (ex.: `10 + 10`, `150 / 3`, `80,50 * 2`) — ao pressionar `Enter` ou mudar de campo, o resultado é calculado e formatado automaticamente — ou clicar no ícone de calculadora dentro do campo para abrir a **Mini Calculadora** interativa com teclado de apoio.
6. **Tags** *(opcional)*: digite etiquetas separadas por vírgula (`,`) ou `Enter` (ex.: `#Viagem`, `#Reembolso`).
7. **Nota / Observação** *(opcional)*.
8. Use **Salvar** para fechar ou **Salvar e Criar Outro** para lançar vários itens em sequência.

### Modos de repetição
- **Único:** uma compra ou receita avulsa.
- **Parcelado:** informe o número de parcelas (de 2x a 120x). O app divide os centavos com exatidão e identifica cada parcela como *(1/10)*, *(2/10)*...
- **Recorrente:** ideal para salário, aluguel e assinaturas. Escolha a **Frequência** (*diária, semanal, quinzenal, mensal, bimestral, trimestral, semestral ou anual*) e, se desejar, uma **Data de Término** (sem data, segue por tempo indeterminado).

### Transferência entre contas
Ao selecionar **`⇄ Transferência`**, escolha a **Conta de Destino**. Isso movimenta o dinheiro entre suas contas (ex.: da Conta Corrente para a Poupança ou pagamento para Cartão) sem distorcer receitas e despesas nos relatórios. Em transferências entre moedas diferentes, você pode ajustar o valor recebido e a taxa efetiva da operação.

### Editar, copiar, excluir e mudar visualização
- No extrato, alterne entre **Lista Diária** e **Tabela (Datagrid)** ou clique no cabeçalho **DIA** para ordenar do mais antigo para o mais recente (ou vice-versa).
- Passe o mouse (ou deslize no celular) sobre um lançamento para **Editar**, **Copiar** (duplicar como novo na data atual) ou **Excluir**. Em séries parceladas ou recorrentes, escolha se a alteração vale para: *Apenas este*, *Este e futuros não conciliados* ou *Toda a série*.

### O que é "conciliado" (✔)?
É marcar que o lançamento já foi efetivado/compensado no extrato bancário. Lançamentos conciliados compõem o **Saldo Atual (Real)** e ficam protegidos contra alterações ou exclusões em série.

---

## 6. 💳 Cartão de crédito e faturas

### Criar o cartão
Escolha **Tipo de Conta: Cartão de crédito** e preencha os três campos adicionais:

| Campo | O que colocar |
|---|---|
| **Dia de Fechamento** | O dia de corte das compras da fatura (veja no app do cartão) |
| **Dia de Vencimento** | O dia em que você paga a fatura |
| **Conta Padrão para Débito da Fatura** | De qual conta corrente sai o pagamento |

### A regra oficial da fatura (por mês de vencimento — Schema v7)
No OpenMoney, toda fatura é identificada pelo **mês da sua data de vencimento**:
- Compras realizadas **até o dia de fechamento** entram na fatura cujo ciclo está fechando naquele período.
- Compras realizadas **após o dia de fechamento** entram no ciclo da fatura seguinte.
- **Virada de mês (`dueDay <= closeDay`):** se o cartão fecha no dia **23** e vence no dia **03** do mês seguinte, as compras de 24/09 a 23/10 compõem a **Fatura de Novembro** (pois o vencimento ocorre em `03/11`). Compras a partir de 24/10 vão para a **Fatura de Dezembro** (`03/12`).
- **Quando `dueDay > closeDay`:** se o cartão fecha no dia **05** e vence no dia **15** do mesmo mês, compras até 05/11 entram na **Fatura de Novembro** (`15/11`), e compras após 05/11 vão para a **Fatura de Dezembro** (`15/12`).

> Se a administradora do cartão lançar alguma compra em outra fatura, basta editar o lançamento e ajustar manualmente o campo **Competência da Fatura**.

### Lançar compras e pagar a fatura
- Entre na conta do cartão e registre despesas normalmente (à vista ou parceladas).
- Para registrar adiantamentos ou pagamentos parciais/totais, use **Pagar / Adiantar Fatura** informando conta pagadora, valor e data.
- A conciliação automática (`syncCards`) abate todos os pagamentos parciais já feitos e agenda no dia do vencimento **apenas o saldo restante**. Quando paga integralmente, a fatura exibe o status verde **LIQUIDADA**.
- Use **Fatura PDF** para imprimir ou salvar em PDF A4 a conferência da fatura.

---

## 7. 🏷️ Categorias e Tags (`#tags`)

- **Categorias e Subcategorias:** organizadas em dois níveis para **Despesas** e **Receitas** (ex.: *Alimentação › Mercado*, *Moradia › Aluguel*). Categorias antigas que você não deseja mais usar podem ser **bloqueadas** sem perder o histórico dos anos anteriores.
- **Tags (`#tags`):** funcionam em paralelo às categorias para agrupar gastos transversais (ex.: `#Viagem`, `#Reembolso`, `#Obra`). Você pode gerenciar todas na tela **Tags** e filtrar por tag em **Lançamentos** e **Relatórios** (veja o [Guia de Tags](guia-tags.md)).

---

## 8. 🔔 Contas a Pagar & Receber (Vencimentos)

A tela **Contas a Pagar & Receber** funciona como sua agenda financeira, listando faturas de cartão e lançamentos pendentes atrasados, vencendo hoje ou dentro da janela configurada (padrão: **3 dias**, ajustável em **Ajustes & Personalização**). Você pode conciliar com 1 clique ou clicar em **Ver** para abrir o extrato no lançamento exato.

---

## 9. 📊 Fluxo de Caixa

Em **Fluxo de Caixa**, você visualiza uma matriz completa (**Diária, Mensal, Trimestral, Semestral ou Anual**) com:
- **Saldo Anterior Acumulado**
- **Total de Rendimentos** e **Total de Despesas**
- **Rendimento menos Despesas** (resultado do período)
- **Saldo Final Acumulado** (com suporte a adicionar comentários/anotações clicando em qualquer célula da linha final)
- **Detalhamento Interativo de Lançamentos:** clique em qualquer valor numérico da matriz (seja em um determinado mês, na categoria ou no totalizador) para abrir a tela de detalhe completo com busca, filtros rápidos de conciliação e edição direta de cada lançamento.
- **Recolher / Expandir Categorias:** botão dedicado no cabeçalho da matriz para alternar com 1 clique entre exibir apenas as categorias principais ou todas as subcategorias detalhadas (o estado é salvo de forma persistente).

Você pode filtrar por todas as contas, selecionar contas específicas, alternar entre **Data do Lançamento** vs. **Data de Pagamento da Fatura** e exportar para Excel/Numbers em CSV.

---

## 10. 📈 Relatórios

Em **Relatórios**, acompanhe receitas, despesas, saldo líquido e **Taxa de Poupança (%)** no mês ou no ano completo, com filtros de conta, status de conciliação e tag. Clique em qualquer categoria ou subcategoria para abrir o detalhamento dos lançamentos (com busca, filtro rápido de conciliação e exportação CSV) ou exporte o resumo executivo em **PDF A4 de 1 página**.

> Transferências entre contas e categorias marcadas como *"Oculta de relatórios"* não distorcem seus totais de gastos e receitas.

---

## 11. 🎯 Limite de Gastos e Previsões Orçamentárias

- **Limite de Gastos:** defina tetos mensais por categoria. Ao cadastrar uma nova despesa que ultrapasse o teto da categoria no mês, o OpenMoney exibe um **alerta preventivo** antes de salvar (veja o [Guia de Limite de Gastos e Alertas](guia-limite-de-gastos-e-alertas.md)).
- **Previsões Orçamentárias:** crie reservas planejadas com nome iniciado por **`Previsão`** (ex.: *Previsão Mercado*, *Previsão Combustível*). O sistema vincula a previsão ao mês com base na sua **data de lançamento** (mesmo em contas de cartão de crédito). Na tela **Previsões** ou no botão da barra do extrato, o botão **Ajustar** abate os gastos reais da categoria sem duplicar descontos.
  - **Dois Regimes de Abatimento:** escolha entre **Por Mês** (despesas com data no mês civil) e **Por Fatura** (despesas de banco com data no mês + compras de cartão cuja fatura vence no mês).
  - **Horizonte de Meses Configurável e Mês Atual Real:** em **Ajustes & Personalização**, configure se a rotina avalia **1 mês**, **2 meses**, **3 meses (Padrão)**, **6 meses** ou **12 meses** consecutivos. Ao rodar o abatimento, o sistema considera sempre o **mês atual real** como ponto de partida; caso o mês selecionado na tela seja maior que o horizonte configurado (`predMonths`), o app pergunta se você deseja considerar a partir do mês atual ou do mês selecionado.
  - Se o teto for totalmente consumido, a previsão é mantida com valor **R$ 0,00** e badge **ESGOTADA** para preservar o histórico contábil (veja o [Guia de Gestão de Previsões](guia-gestao-de-previsoes.md)).

---

## 12. 🔍 Busca Global, Filtros e Edição em Massa

- **Pesquisa Global (`Cmd + Shift + F`):** encontra qualquer lançamento em todo o histórico por descrição, categoria, observação, tag ou valor e navega direto para a linha correspondente.
- **Lançamentos (Visão Consolidada):** permite combinar filtros de **Período (Dia/Mês/Ano)**, **Contas**, **Regime de Cartão**, **Categoria**, **Tag**, **Tipo** e **Conciliação**, além de ativar **Selecionar** para conciliar, editar ou excluir vários lançamentos em lote com backup preventivo automático (veja o [Guia de Edição em Massa](guia-edicao-em-massa.md)).

---

## 13. 🛡️ Segurança, Backups e Boas Práticas

- **Backups Automáticos em `.zip`:** no Desktop e Mobile, o sistema gera de **3 a 4 snapshots automáticos ao dia** ao abrir o aplicativo e durante o uso, mantendo retenção mínima de 7 dias / 28 arquivos na pasta de backups (inclusive para contas do Modo Online). Na nuvem, o OpenMoney Cloud mantém **3 a 4 snapshots por dia durante 15 dias** (gerados ao abrir o app ou o site) e **Logs de Alterações** por 30 dias.
- **Proteção Anti-Wipe:** o aplicativo impede abertura zerada ou sobrescrita acidental vazia de bases populadas.
- **Conta com lançamentos não pode ser excluída:** use **Desativar / Arquivar conta** para ocultá-la dos seletores de novos lançamentos preservando todo o histórico contábil.
- **Exclusão em lote** gera obrigatoriamente um backup preventivo antes de apagar qualquer registro.

---

## 14. ❓ Perguntas frequentes

- **O saldo não bate com o banco:** confira o *Saldo Inicial de Abertura* da conta e verifique se há lançamentos não conciliados ou faltantes.
- **Lancei errado, e agora?** Clique no lançamento para **Editar**, **Copiar** ou **Excluir** (ou selecione vários em **Lançamentos** para editar em lote).
- **Posso lançar gastos pelo celular na rua?** Sim — usando a versão Web/Mobile sincronizada via OpenMoney Cloud (`https://openmoney.app.br`), o app nativo no iOS ou o [OpenMoney Coletor PWA](https://fsf77.github.io/openmoney-new/coletor/) com leitura de recibos por câmera e importação via `openmoney_inbox.json`.
- **Já usava outro programa financeiro (como Microsoft Money 99 ou planilhas):** use **Módulos › Importação / Exportação** para importar arquivos `.csv`, `.qif` ou `.ofx` e transferir contas, categorias e lançamentos (veja o [Guia de Importação e Exportação](guia-importacao-e-exportacao-csv-ofx.md)).
- **Quer personalizar a tela e a cor do app?** Acesse **Ajustes & Personalização** (`Cmd + ,` / `Ctrl + ,`) para escolher a tela inicial, widgets do Dashboard, modo *Mini Rail*, visualização em *Datagrid*, moeda padrão e paleta de cores.
