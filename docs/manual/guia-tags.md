# Guia do Usuário: Sistema de Tags (`#tags`)

Este manual apresenta o guia operacional para uso do **Sistema de Tags (`#tags`)** nos lançamentos e relatórios do **OpenMoney** (Desktop macOS/Windows, Web e Mobile).

---

## 1. 🏷️ O que são Tags e quando usar

As **Tags** funcionam como etiquetas livres que complementam suas **Categorias e Subcategorias**. Enquanto uma categoria responde *"o que é o gasto"* (ex.: `Alimentação`, `Transporte`, `Hospedagem`), uma tag permite agrupar movimentações transversais por projeto, evento ou finalidade (ex.: `#Viagem`, `#Reembolso`, `#Trabalho`, `#Imposto`).

---

## 2. ➕ Como criar e gerenciar Tags

### Opção A — Pela Tela Dedicada de Tags
1. No menu lateral (abaixo de **Categorias**), acesse **Tags** (no iOS, disponível na aba **Mais > Tags**).
2. Clique no botão **`+` / Nova Tag**.
3. Digite o nome da tag e confirme.
4. Na listagem de tags você pode:
   - **Clicar na linha de qualquer tag** para abrir a tela de detalhamento com todos os lançamentos vinculados (mesma tela de auditoria usada em Categorias, com busca, ordenação e exportação CSV).
   - **Renomear** uma tag (atualiza automaticamente o catálogo e todos os lançamentos associados).
   - **Excluir** uma tag (remove do catálogo e desvincula dos lançamentos).

### Opção B — Diretamente ao Criar ou Editar um Lançamento
1. Abra o formulário de **Novo Lançamento**, **Editar** ou **Copiar**.
2. No campo **Tags**, digite o nome da tag desejada.
3. Para confirmar e transformar em chip (`#tag`), basta **digitar uma vírgula (`,`)** ou **pressionar `Enter`**.
4. Você também pode clicar em qualquer uma das **sugestões** exibidas abaixo do campo com tags já existentes na sua base.
5. Ao salvar o lançamento, novas tags digitadas são registradas automaticamente no catálogo global de Tags e sincronizadas via **Cloud Sync v2**.

---

## 3. 🔎 Onde as Tags aparecem e como filtrar

- **Extrato da Conta / Cartão:** cada lançamento exibe seus chips `#tag` diretamente na linha.
- **Lançamentos Gerais (Consolidado):** exibe chips `#tag`, permite buscar pelo nome da tag no campo de busca textual e traz o filtro dedicado **Tag** (`Todas`, `Sem tag` ou `#tag` específica).
- **Relatórios (Mensal e Anual):** possui o seletor **Tag** no cabeçalho de filtros; ao filtrar por uma tag, os totais, gráficos e o detalhamento ao clicar em qualquer categoria respeitam a tag selecionada.
- **Exportação CSV:** a coluna **`Tags`** é exportada ao final do arquivo CSV.
