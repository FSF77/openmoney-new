# Guia: Lançamentos e Transferências Recorrentes

Este guia explica como funcionam os lançamentos recorrentes no **OpenMoney**, com foco especial na configuração, projeção e gerenciamento de **Transferências Recorrentes** entre contas.

---

## 1. O que são Transferências Recorrentes?

Uma **Transferência Recorrente** é uma programação automática que projeta e gera periodicamente a movimentação financeira entre duas contas distintas cadastradas no sistema.

Exemplos comuns de uso:
- **Aplicações e Investimentos**: Transferência mensal automática da conta corrente para a conta de corretora ou poupança.
- **Mesadas e Custeios**: Envio periódico de valores para dependentes ou contas auxiliares.
- **Reserva de Emergência**: Aporte recorrente quinzenal ou mensal.
- **Cobrimento de Limite**: Transferências automáticas entre contas bancárias do mesmo titular.

---

## 2. Como Criar uma Transferência Recorrente

1. Abra a tela de **Novo Lançamento** (botão `+` ou atalho rápido na barra lateral).
2. No seletor de tipo de lançamento, escolha **⇄ Transferência**.
3. Selecione a **Conta de Origem** (de onde o valor sai) e a **Conta de Destino** (para onde o valor vai).
4. Informe o **Valor** da transferência.
5. No campo **Modo do Lançamento**, selecione **Recorrente**.
   *(Nota: A opção "Parcelado" é automaticamente omitida para transferências, pois o conceito de parcelamento financeiro de fatura se aplica apenas a despesas).*
6. Escolha a **Frequência** desejada:
   - *Diário*
   - *Semanal*
   - *Quinzenal*
   - *Mensal* (padrão mais comum)
   - *Bimestral*
   - *Trimestral*
   - *Semestral*
   - *Anual*
7. (Opcional) Marque **Definir Data de Término** se a programação tiver prazo final determinado. Se desmarcado, a regra permanece por tempo indeterminado com projeção contínua.
8. Clique em **Salvar Lançamento**.

---

## 3. Comportamento no Sistema e nas Duas Contas

Ao salvar uma transferência recorrente:
- O motor de sincronização (`syncRecs`) gera automaticamente os lançamentos correspondentes no extrato de **ambas as contas**:
  - Na **Conta de Origem**: Lançamento de saída (débito negativo) com descrição `"Transferência: [Nome da Conta Destino]"`.
  - Na **Conta de Destino**: Lançamento espelho de entrada (crédito positivo) com descrição `"Transferência: [Nome da Conta Origem]"`.
- Ambos os lançamentos ficam interligados pela chave de transferência (`xfer: xrec:...`).
- Caso as contas possuam moedas diferentes (ex: transferência de conta em BRL para conta em USD), o sistema aplica a conversão cambial calculada no momento da geração para creditar o valor na moeda correta da conta receptora.
- Caso a conta de destino seja um Cartão de Crédito, a competência da fatura (`ik`) é calculada automaticamente conforme as datas de fechamento e vencimento do cartão.

---

## 4. Edição e Exclusão em Série

Ao editar ou excluir qualquer uma das parcelas de uma transferência recorrente, uma janela de escopo é apresentada:

1. **Apenas Este Lançamento (`only`)**:
   - Altera ou remove exclusivamente a data ou valor daquela competência específica.
   - A contrapartida na outra conta é atualizada/removida simultaneamente, mantendo os saldos perfeitamente conciliados.
2. **Deste em Diante (`forward`)**:
   - Ajusta o encerramento da regra atual e remove/atualiza as ocorrências futuras a partir da data selecionada.
   - Os lançamentos do passado já consolidados permanecem intactos.
3. **Toda a Série (`all`)**:
   - Remove a regra de recorrência e todos os lançamentos gerados nas duas contas, limpando o histórico completo daquela programação.

---

## 5. Projeção no Fluxo de Caixa

As transferências recorrentes integram-se nativamente à visualização de **Fluxo de Caixa**:
- O valor transferido afeta adequadamente os saldos projetados de cada conta individualmente.
- Na visão consolidada (todas as contas), a transferência entre contas internas anula-se na receita/despesa líquida patrimonial, garantindo que o patrimônio líquido total do mês não sofra distorção contábil por simples realocação de recursos.
