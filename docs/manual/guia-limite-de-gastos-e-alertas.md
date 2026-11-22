# Guia do Usuário: Limite de Gastos e Alerta Preventivo de Orçamento

O módulo de **Limite de Gastos** do OpenMoney permite planejar tetos mensais de despesas por categoria e conta com um sistema ativo de **alerta preventivo de estouro de orçamento** durante o cadastro de lançamentos.

---

## 1. Como Definir e Acompanhar os Limites Mensais

1. Acesse o menu **Limite de Gastos** na barra lateral.
2. Selecione o mês de referência no seletor de competência.
3. **Painel Superior de Métricas (Cards de Fácil Visualização):**
   - **Limite Previsto:** Soma total de todos os tetos de gastos configurados para o mês selecionado.
   - **Realizado:** Total efetivamente despendido no mês nas categorias orçadas.
   - **Saldo:** Diferença entre o limite previsto e o total realizado. Se o gasto exceder o teto, o saldo é apresentado em destaque vermelho.
4. **Listagem e Status por Categoria:**
   - Clique sobre o valor da categoria ou subcategoria que deseja configurar.
   - Digite o teto mensal desejado em reais (moeda padrão) e clique em **Salvar Limite**.
   - **Tag "ACIMA DO LIMITE":** Quando os gastos acumulados de uma categoria ou subcategoria ultrapassam o teto estabelecido, o sistema exibe uma tag compacta vermelha **`ACIMA DO LIMITE`** ao lado do nome da categoria (no mesmo padrão visual compacto e discreto da gestão de previsões), permitindo identificar imediatamente despesas que estouraram o orçamento.
   - **Categorias com subcategorias**: Você pode definir o limite individualmente em cada subcategoria ou no total da categoria pai. As categorias principais totalizam automaticamente as subcategorias.

---

## 2. Alerta Preventivo ao Inserir Lançamentos

Ao registrar uma nova despesa (seja pelo botão **Novo Lançamento**, pelo atalho de **Duplicar** ou pela **Inserção Rápida** do extrato), o OpenMoney verifica automaticamente se a categoria utilizada possui um limite mensal definido (> R$ 0,00).

### Como Funciona a Verificação:
1. O sistema soma todas as despesas já lançadas no mesmo mês para aquela categoria.
2. Compara o total acumulado mais o valor do novo lançamento com o teto definido.
3. Se o novo lançamento fizer o total de gastos ultrapassar o limite, uma janela de confirmação é exibida imediatamente:

> ⚠️ **Limite de Gastos Excedido**  
> A categoria *"[Nome da Categoria]"* ultrapassará o limite de gastos definido para o mês de *[Mês/Ano]*.  
> 
> • **Limite definido:** R$ X,XX  
> • **Gasto atual no mês:** R$ Y,YY  
> • **Saldo disponível:** R$ Z,ZZ (ou Esgotado)  
> • **Valor deste lançamento:** R$ W,WW  
> • **Valor excedente:** R$ E,EE  
> 
> *Deseja realmente continuar com este lançamento?*

### Opções:
- **Cancelar**: Interrompe a inclusão e mantém os dados na tela, permitindo ajustar o valor, alterar a categoria ou desistir da despesa.
- **Continuar**: Confirma o registro mesmo com o teto ultrapassado, gravando o lançamento normalmente no extrato.

---

## 3. Regras Importantes
- **Previsões Desconsideradas**: Lançamentos com descrição/favorecido iniciando por "Previsão" (e.g. `Previsão Mercado`, `Previsão Combustível`) representam estimativas de planejamento e **nunca são somados como despesas realizadas**, garantindo que não consumam indevidamente o limite disponível da categoria.
- **Receitas e Transferências**: Não são afetadas pela validação de limite.
- **Subcategorias**: Se a subcategoria não tiver limite próprio, o OpenMoney valida o limite da categoria pai somando todos os gastos daquela família de categorias.
- **Compras Parceladas**: O sistema avalia o valor da **primeira parcela** contra o orçamento do mês do lançamento, respeitando o impacto real do mês.
