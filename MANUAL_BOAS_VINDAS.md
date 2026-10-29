# 💰 OpenMoney — Manual de Boas-Vindas

Guia para quem nunca usou um programa de finanças. Leia na ordem e em 15 minutos você estará usando.

---

## 1. O que é o OpenMoney?

Um caderninho de finanças no computador. Você registra o que **entra** (receitas) e o que **sai** (despesas), e ele mostra seu saldo, suas faturas e para onde o dinheiro vai.

- 🔒 **Seus dados ficam só com você**: tudo é guardado em um arquivo no seu computador (`openmoney.json`). Não há cadastro nem servidor.
- 💾 **Backups automáticos** são feitos por segurança.
- ☁️ Quer usar em dois computadores? Guarde o arquivo numa pasta de nuvem (iCloud, OneDrive, Dropbox ou Google Drive).

**Primeira abertura:** o app pergunta onde fica sua base de dados. Escolha **Criar Nova Base** (se for iniciante) ou **Procurar Base** (se já tiver uma).

---

## 2. Conhecendo a tela

No menu lateral você encontra:

| Menu | Para que serve |
|---|---|
| **Extrato** | Lista de tudo que você lançou em cada conta (o principal) |
| **Vencimentos** (Contas a Pagar & Receber) | O que vence nos próximos dias |
| **Fluxo** (Fluxo de Caixa) | Quadro mês a mês de entradas, saídas e saldo |
| **Relatórios** | Quanto você gastou por categoria |
| **Orçamento** | Metas de gasto por categoria |
| **Categorias** | Organizar tipos de gasto e receita |
| **Buscar** | Achar qualquer lançamento |

Contas ficam na lista da barra lateral. O botão **Nova Conta** cria uma conta.

---

## 3. Passo a passo para começar

✅ 1. Crie sua(s) conta(s) corrente(s)
✅ 2. Crie seus cartões de crédito
✅ 3. Dê uma olhada nas categorias
✅ 4. Faça seus primeiros lançamentos
✅ 5. Veja o Fluxo e os Relatórios

---

## 4. Criar uma conta corrente

1. Clique em **Nova Conta** (barra lateral).
2. Preencha:
   - **Nome da Conta**: ex.: *Itaú*, *Nubank*.
   - **Tipo de Conta**: escolha **Corrente** (outras opções: Poupança, Investimento, Dinheiro, Cartão de crédito).
   - **Saldo Inicial de Abertura**: quanto tinha na conta **hoje**, ao começar.
   - **Favoritar Conta** (opcional): fixa no topo da lista.
3. Clique em **Salvar**.

> 💡 **Dica:** abra o app do seu banco e use o saldo real de hoje. Assim o saldo do OpenMoney bate com o do banco desde o primeiro dia.

Crie também uma conta tipo **Dinheiro** para a carteira, se quiser controlar gastos em espécie.

---

## 5. Fazer lançamentos

Clique na conta no menu lateral e use a **barra de inserção rápida** no topo do Extrato.

1. **Data**.
2. **− Despesa** ou **+ Receita**.
3. **Favorecido / Descrição**: ex.: *Supermercado*. Ao digitar, o app sugere nomes já usados e preenche a categoria automaticamente.
4. **Categoria**.
5. **Valor**.
6. **Nota / Observação** (opcional).

### Tipos de lançamento
- **Único**: uma compra comum.
- **Parcelado**: informe o **Número de Parcelas** (ex.: 10x). O app cria todas, marcadas como *(1/10)*, *(2/10)*...
- **Recorrente**: para contas fixas como salário e aluguel. Escolha a **Frequência** (mensal, anual etc.) e, se quiser, uma **Data de Término**. Sem data, vale por tempo indeterminado.

### Transferência entre contas
No campo categoria, escolha **⇄ Transferência: nome da conta**. Isso move dinheiro entre suas contas (ex.: da corrente para a poupança) sem contar como gasto.

### Corrigir ou apagar
Clique no lançamento para **Editar**. Você pode **Copiar** ou **Excluir**. Em lançamentos parcelados ou recorrentes, o app pergunta se vale para: *Apenas este*, *Este e futuros não conciliados* ou *Toda a série*.

### O que é "conciliado" (✔)?
É marcar que o lançamento já apareceu no extrato do banco. Lançamentos conciliados ficam protegidos contra alterações em lote.

---

## 6. Cartão de crédito e faturas

### Criar o cartão
**Nova Conta** → **Tipo de Conta: Cartão de crédito**. Aparecem três campos extras:

| Campo | O que colocar |
|---|---|
| **Dia de Fechamento** | O dia em que a fatura "vira" (veja no app do cartão) |
| **Dia de Vencimento** | O dia em que você paga a fatura |
| **Conta Padrão para Débito da Fatura** | De qual conta corrente sai o pagamento |

### A regra da fatura (importante!)
A fatura é decidida pela **data da compra** em relação ao **dia de fechamento**:

- Compra **até** o dia de fechamento → entra na fatura **deste mês**.
- Compra **depois** do fechamento → entra na fatura do **mês seguinte**.

**Exemplo:** fechamento dia **10**.
- Compra em 08/03 → fatura de março.
- Compra em 10/03 → fatura de março.
- Compra em 11/03 → fatura de **abril**.

> Se o banco colocou uma compra em outra fatura, abra o lançamento e mude **Competência da Fatura do Cartão**.

### Lançar compras no cartão
Entre na conta do cartão e lance como despesa normal. Parcelamentos funcionam igual (ex.: 6x).

### Pagar a fatura
No cartão, use **Pagar / Adiantar Fatura**:
- **Debitar da Conta**: escolha a corrente.
- **Valor a Pagar**: o total ou só uma parte.
- **Data do Pagamento**.
- **Confirmar Pagamento**.

Se você não pagar manualmente, o app registra o pagamento automático no vencimento, **apenas do valor que ainda falta**. Fatura paga por completo recebe o selo verde **LIQUIDADA**.

---

## 7. Categorias

Em **Categorias** você organiza gastos e receitas em dois níveis, por exemplo: **Moradia › Aluguel**, **Alimentação › Mercado**. Cada categoria é de **Despesa** ou **Receita**. Quanto melhor categorizar, mais úteis os relatórios.

---

## 8. Vencimentos

A tela **Vencimentos** mostra o que está para vencer e para receber, incluindo faturas de cartão. Use como sua "agenda do dinheiro".

---

## 9. Fluxo de Caixa

Em **Fluxo** você vê um quadro mês a mês com:

- **Saldo anterior**: o que sobrou até o mês passado.
- **Receitas** e **Despesas** do mês.
- **Resultado**: receitas menos despesas.
- **Saldo final**: saldo anterior + resultado.

Você pode ver **todas as contas juntas** ou **uma conta específica**. Como lançamentos futuros (parcelas, recorrências) já aparecem, dá para **prever** os próximos meses.

---

## 10. Relatórios

Em **Relatórios** escolha o mês e veja quanto gastou e ganhou, por categoria. Clique numa categoria para ver os lançamentos que a compõem.

> Transferências entre contas **não** entram nos relatórios (não são gasto nem renda).

---

## 11. Orçamento e Previsões

Em **Orçamento** você define quanto pretende gastar por categoria. Também é possível criar lançamentos com nome iniciado por **"Previsão"** (ex.: *Previsão Mercado*) como reserva do mês. Ao usar **Ajustar Previsões**, o app desconta os gastos reais da reserva.

---

## 12. Buscar

**Buscar** (Pesquisa Global) encontra qualquer lançamento por descrição, valor ou categoria.

---

## 13. Segurança e boas práticas

- **Backups**: ficam em *Backups de Segurança*. Copie o arquivo `openmoney.json` de vez em quando para um pendrive ou nuvem.
- **Conta com lançamentos não pode ser excluída**: use **Conta Inativa (Arquivada)** para escondê-la sem perder o histórico.
- **Limpeza em lote** exige que você salve um backup antes.
- **Atualizações**: o app avisa ao abrir; basta um clique para atualizar.

---

## 14. Perguntas frequentes

**O saldo não bate com o banco.** Confira o *Saldo Inicial* da conta e se há lançamentos faltando.

**Lancei errado, e agora?** Clique no lançamento, **Editar** ou **Excluir**.

**Posso usar no celular?** Há importação de lançamentos do celular (*Importar do Celular*).

**Já usava outro programa.** Use **Importar / Exportar (CSV / QIF)**.

**Meus dados estão seguros?** Ficam só no seu arquivo local. Faça backups.

---

Dúvidas ou sugestões? Fale com quem te enviou o app. Bom controle financeiro! 🎉
