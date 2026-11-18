# Guia de Conciliação Bancária e Faturas via OFX

O **OpenMoney** oferece uma rotina completa de **Conciliação Bancária e de Faturas de Cartão de Crédito** usando arquivos **`.ofx` / `.qfx`** exportados diretamente do aplicativo ou internet banking do seu banco (em **macOS**, **Windows**, **Web**, **iOS** e **Android**).

---

## 1. Onde Acessar o Conciliador OFX

Você pode iniciar a conciliação a partir de qualquer um destes pontos:
- **Extrato da Conta ou Fatura do Cartão:** clique no botão/ícone de conciliação OFX (**Conciliar OFX**) no cabeçalho da conta desejada (a conta e a fatura atual já vêm pré-selecionadas automaticamente).
- **Central de Importação / Exportação:** acesse o menu de importação e clique em **Conciliar OFX...** (funciona também na versão Web).
- **Atalho de Teclado:** pressione `⌘⇧O` (macOS) ou `Ctrl+Shift+O` (Windows/Web) ou busque *Conciliar Extrato ou Fatura (OFX)* na **Command Palette** (`⌘K` / `Ctrl+K`).

---

## 2. Como o Assistente Classifica Cada Lançamento

Ao carregar um arquivo `.ofx` ou `.qfx`, o OpenMoney identifica automaticamente a conta (e, no caso de cartões, a competência da fatura `MM/AAAA`) e divide os itens do arquivo em três grupos:

1. **Conciliar (Pareados com a sua Base):**
   - O sistema localiza lançamentos existentes na conta com mesmo valor e data próxima (ou dentro da mesma fatura do cartão, incluindo parcelas `X/Y` e o lançamento automático de pagamento de fatura).
   - **Sua descrição e categoria originais são preservadas.**
   - O lançamento é marcado como **Conciliado** (`rec = true`) e recebe o vínculo **`FITID`** do banco.
   - Você decide (globalmente em *Opções* ou item a item) se deseja **atualizar a data** para a data efetiva do banco (`<DTPOSTED>`) ou manter a data original digitada.
   - *Nota:* Envelopes de **Previsão** nunca são substituídos automaticamente — permanecem intactos para o ajuste de previsões.

2. **Novos Lançamentos:**
   - Movimentações inéditas encontradas no extrato (tarifas, compras não lançadas, PIX avulsos, rendimentos).
   - O OpenMoney limpa prefixos bancários longos (como *"Transferência enviada pelo Pix - ..."*) mantendo os detalhes originais na **Nota/Memo**, e sugere automaticamente:
     - **Transferência entre Contas (`⇄`)**, quando identifica agência/conta de outro banco seu cadastrado no OpenMoney;
     - **Categoria** baseada no histórico de lançamentos do mesmo favorecido.
   - Em compras parceladas no cartão (`Parcela X/Y`), é possível marcar **Projetar parcelas futuras** para criar automaticamente as parcelas restantes nas faturas seguintes.

3. **Ignorados / Já Conciliados:**
   - **Reimportação Idempotente (`FITID`):** qualquer item já importado ou vinculado anteriormente pelo `FITID` é ignorado automaticamente — você pode importar o mesmo mês várias vezes sem risco de duplicação.
   - **Pagamento da Fatura Anterior (Cartão):** créditos como *"Pagamento recebido"* são reconhecidos para não distorcerem o saldo das compras da fatura atual.

---

## 3. Conferência de Saldo (`LEDGERBAL`) e Lançamento de Ajuste

Sempre que o arquivo OFX informar o saldo final do extrato (ou o total fechado da fatura), o painel superior exibe:
- **Saldo OFX** (valor oficial do banco na data de referência)
- **Saldo Conciliado Projetado** (como a sua conta ficará após aplicar as ações marcadas)
- **Diferença** (`✓ R$ 0,00 (Convergido)` quando fecha exatamente)

Se houver qualquer diferença residual (por exemplo, saldo inicial de meses anteriores), basta marcar **Criar lançamento de ajuste** no próprio painel para gerar automaticamente um lançamento conciliado com o valor exato da diferença.

---

## 4. Dicas para Melhor Aproveitamento

- **Cadastre Banco e Número da Conta** nas configurações de cada conta do OpenMoney: isso permite que o sistema detecte a conta do arquivo OFX na primeira importação e reconheça automaticamente transferências PIX entre suas próprias contas.
- **Memorização automática:** ao confirmar a conciliação, a opção *"Memorizar conta para próximas importações OFX"* vincula o identificador OFX diretamente à conta selecionada.
- **Troca manual de vínculo:** no painel de revisão de qualquer item, você pode alternar livremente entre **Conciliar**, **Criar Novo** ou **Ignorar**, inclusive vinculando manualmente um item OFX a um lançamento pendente cujo valor estimado era diferente (com opção de atualizar para o valor exato do banco).
