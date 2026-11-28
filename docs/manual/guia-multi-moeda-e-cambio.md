# Guia do Usuário: Contas Multi-Moeda, Câmbio e Cotações Históricas

Este guia explica como operar com múltiplas moedas no **OpenMoney** (Desktop macOS/Windows, Web e Mobile iOS/Android), garantindo saldos corretos por moeda, conversão consolidada na moeda padrão e fidelidade histórica mesmo para lançamentos de anos anteriores.

---

## 1. 🌍 Moedas Disponíveis no Sistema

O OpenMoney oferece suporte nativo a **11 moedas**:
- 🇧🇷 **BRL** — Real Brasileiro (`R$`)
- 🇺🇸 **USD** — Dólar Americano (`US$`)
- 🇪🇺 **EUR** — Euro (`€`)
- 🇨🇦 **CAD** — Dólar Canadense (`C$`)
- 🇦🇺 **AUD** — Dólar Australiano (`A$`)
- 🇬🇧 **GBP** — Libra Esterlina (`£`)
- 🇵🇾 **PYG** — Guarani Paraguaio (`₲`, sem centavos)
- 🇦🇷 **ARS** — Peso Argentino (`ARS$`)
- 🇺🇾 **UYU** — Peso Uruguaio (`$U`)
- 🇨🇭 **CHF** — Franco Suíço (`CHF`)
- 🇨🇱 **CLP** — Peso Chileno (`CLP$`, sem centavos)

---

## 2. ⚙️ Configurando Moeda Padrão e Cotações (`Moedas & Cotações`)

Acesse **Ajustes & Personalização** (na barra lateral ou via `Cmd + ,` / `Ctrl + ,`) e role até a seção **Moedas & Cotações** (no final da tela):

1. **Moeda Base / Padrão do Sistema:**
   - O padrão inicial é **Real Brasileiro (BRL)**, mas você pode escolher qualquer uma das 11 moedas suportadas como sua moeda consolidada.
   - Todas as visões consolidadas (Patrimônio Consolidado, relatórios com todas as contas e somatórios multi-moeda) serão convertidas para a moeda padrão escolhida.
2. **Atualização Automática Diária vs Manual:**
   - Para economizar consultas e evitar bloqueios na API gratuita, o app consulta as cotações online **no máximo 1 vez por dia** e **apenas se existir alguma conta ativa em moeda diferente da moeda base**.
   - Ao lado de cada moeda, é exibida a taxa atual, a origem (`Auto` ou `Manual`) e a **data/hora da última atualização**.
   - Clique em **Atualizar Agora** quando quiser buscar imediatamente as cotações correntes online.
   - Clique no ícone de **lápis** ao lado de uma moeda se desejar travar uma **cotação manual** (o refresh diário automático respeitará valores manuais até que você clique em **Auto** novamente).

---

## 3. 🏦 Criando e Editando Contas em Outra Moeda

No cadastro ou edição de conta (**Nova Conta** / **Editar Conta**):
- Selecione o campo **Moeda** da conta (padrão `BRL` ou qualquer moeda estrangeira, como `USD`, `EUR`, `PYG`, etc.).
- O campo **Saldo Inicial** e **todos os lançamentos** dessa conta serão sempre registrados na **moeda própria da conta** (ex.: lançamentos em conta `USD` são digitados em `US$`).
- Na tela do extrato da conta e no Dashboard, o sistema mostra o saldo na moeda oficial da conta e, logo abaixo, o equivalente aproximado (`≈`) na sua **Moeda Padrão**.

---

## 4. 💱 Lançamentos em Conta Estrangeira e Cotação Histórica Editável

Ao incluir, copiar ou editar um lançamento comum (despesa ou receita) em uma conta estrangeira (diferente do `BRL` e da sua moeda base):

### A. Como o sistema sugere a cotação automaticamente
Ao selecionar a conta e a **data** do lançamento, o campo **Cotação do Lançamento (`1 <moeda> = ? <base>`)** é preenchido automaticamente seguindo esta ordem de prioridade:
1. **Última transferência de câmbio da conta até a data do lançamento:** Se você comprou dólar transferindo de uma conta `R$` para a conta `US$` naquela época informando o câmbio real (com IOF/spread), o sistema usa essa taxa como referência prioritária para os gastos seguintes até a próxima compra de câmbio.
2. **Cotação Oficial Histórica (Banco Central PTAX / AwesomeAPI):** Caso não haja transferência de câmbio anterior e a data for anterior a hoje (ex.: um gasto de `2012-06-15`), o app consulta automaticamente a PTAX oficial do Banco Central do Brasil da época (ou o dia útil imediatamente anterior em fins de semana/feriados).
3. **Cotação Atual do Sistema:** Usada como fallback para lançamentos de hoje/futuros sem transferência prévia ou quando não há acesso à internet.

### B. Editando a taxa ou escolhendo sugestões com 1 clique
Nos modais de **Novo Lançamento**, **Editar** e **Copiar**, abaixo do campo de cotação aparecem:
- **Preview ao vivo:** Mostra na hora quanto aquele valor equivale na sua moeda padrão (`≈ R$ ...`) conforme você digita o valor ou ajusta a taxa.
- **Atalhos em chips/botões:**
  - `Transf. DD/MM/AAAA`: aplica a taxa efetiva da última transferência de câmbio da conta até aquela data;
  - `Buscar BCB (DD/MM/AAAA)`: consulta online a cotação oficial da data exata no Banco Central (PTAX) / AwesomeAPI;
  - `Atual`: volta para a cotação do dia configurada em *Moedas & Cotações*.
- **Edição livre:** Você pode digitar manualmente qualquer taxa desejada (útil para taxa fechada no cartão ou câmbio paralelo/casa de câmbio).
- **Ao editar um lançamento antigo:** A taxa que já estava salva nele é **preservada** ao abrir a tela (o sistema não sobrescreve sua taxa gravada sem que você peça ou altere a data/conta).

### C. Lançamento Rápido dentro da Conta (Desktop)
Na barra de inclusão rápida no topo do extrato de contas em moeda estrangeira, aparece o campo compacto **Taxa (`<Moeda Base>`)** logo ao lado do campo **Valor**, também preenchido automaticamente pela data escolhida e editável antes de clicar em **Adicionar**.

---

## 5. 🔄 Transferências Entre Contas de Moedas Diferentes

Ao criar ou editar uma **Transferência** entre contas com moedas diferentes (ex.: conta `R$` → conta `US$`):
1. O painel **Câmbio da Transferência** sugere o valor convertido pela cotação do dia.
2. Você pode **ajustar o valor em ambas as moedas** ou editar diretamente o campo **Taxa**:
   - Se alterar o valor recebido (por causa de IOF, tarifas ou spread), o sistema recalcula e exibe a **taxa efetiva** real da operação.
   - Se a transferência tiver data passada, o botão **BCB (`data`)** busca a cotação oficial daquele dia.
3. Essa taxa efetiva fica salva na operação e passa a servir automaticamente de referência para os gastos futuros feitos com aquele saldo comprado!

---

## 6. 🛠️ Corrigindo Lançamentos Antigos já Cadastrados (`Corrigir Passados`)

Se você já cadastrou lançamentos passados (por exemplo, histórico de **2012** ou anos anteriores) antes dessa atualização e percebeu que eles ficaram gravados com a taxa de hoje:

1. Vá em **Ajustes & Personalização → Moedas & Cotações**.
2. No final da seção, clique em **Corrigir Passados (`N`)**.
3. Confirme na janela de aviso.

**O que a ferramenta faz automaticamente:**
- Percorre seus lançamentos passados (`data < hoje`) em moeda estrangeira (exceto transferências entre contas, que preservam os valores debitados/creditados originais);
- Para cada um, aplica primeiro a **transferência de câmbio da época** naquela conta (se existir até a data do gasto) ou busca a **cotação histórica oficial da época** no Banco Central / AwesomeAPI;
- Atualiza somente os registros cuja taxa divergir da taxa histórica resolvida e registra a operação no log de auditoria.

---

## 7. 📊 Relatórios, Fluxo de Caixa e Exportação CSV

### Como os valores são exibidos nos Relatórios e Fluxo de Caixa
- **Todas as contas (ou múltiplas moedas selecionadas):**
  - As linhas de **Receitas**, **Despesas** e **Categorias** são consolidadas na **Moeda Padrão** convertendo cada lançamento pela **taxa histórica gravada nele** (preservando o poder de compra/câmbio da data da operação).
  - As linhas de **Saldo Anterior Acumulado** e **Saldo Final Acumulado** do Fluxo de Caixa acumulam o saldo de cada conta na sua **moeda original** (ex.: `US$`) e convertem pela **cotação atual** configurada em *Moedas & Cotações*, garantindo que o **Saldo Final Acumulado** bata exatamente com o **Saldo Real Atualizado** mesmo quando você mistura contas em `R$` e `US$`.
- **Filtro por uma conta ou contas da mesma moeda estrangeira (ex.: só contas `US$`):**
  - Os valores principais na tabela e nos cards aparecem na **moeda da conta** (`US$`).
  - Os subtítulos `≈` nos cards de totais (`Receitas`, `Despesas`, `Resultado Líquido`) somam o equivalente convertido na **Moeda Padrão** respeitando a **taxa histórica individual de cada transação** (assim despesas de 2012 continuam aparecendo pelo dólar de 2012, não pelo dólar de hoje).

### Exportação e Importação CSV
Ao exportar ou importar arquivos CSV, o OpenMoney grava **17 colunas** que preservam os valores em ambas as moedas:
- **`Valor` e `Moeda`:** Valor oficial e código da moeda da conta.
- **`Moeda Padrão`, `Valor Moeda Padrão` e `Taxa Câmbio`:** Equivalente convertido na moeda base pela taxa histórica do lançamento.
- **`Valor Contrapartida`, `Moeda Contrapartida` e `Taxa Transferência`:** Em transferências entre moedas diferentes, preservam exatamente o valor de compra/venda na conta destino e a taxa efetiva utilizada para que a reimportação mantenha os saldos exatos nas duas moedas.
