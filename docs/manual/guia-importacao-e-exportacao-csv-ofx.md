# Guia do Usuário: Importação e Exportação (CSV, OFX e Contas)

Este manual apresenta todas as ferramentas de **Importação e Exportação** do **OpenMoney**, permitindo migrar dados de outros sistemas, manter planilhas atualizadas e automatizar o controle financeiro.

---

## 1. 📂 Central de Importação e Exportação

Acesse pelo menu lateral em **Módulos › Importação / Exportação** ou pelos atalhos:
- `Cmd + Option + I` (macOS) / `Ctrl + Alt + I` (Windows)
- Botões de importação e exportação de CSV nos cabeçalhos de **Extratos**, **Categorias**, **Relatórios** e **Fluxo de Caixa**.

A janela central é organizada em duas abas:
- **Importar:** Extratos Bancários (OFX), Arquivos QIF (Microsoft Money 99), Catálogo de Categorias em CSV, Contas Cadastradas em CSV e Comprovantes/Recibos.
- **Exportar:** Lançamentos em CSV, Catálogo de Categorias em CSV e Contas Cadastradas em CSV.

---

## 2. 📄 Exportação de Lançamentos em CSV (com Saldo Inicial)

Ao exportar o extrato em CSV:
1. **Filtro de Contas:** escolha uma conta individual ou **Todas as Contas (Consolidado)**.
2. **Filtro de Período:** todo o histórico, um mês específico ou intervalo personalizado com data inicial e final.
3. **Inclusão Automática do Saldo Inicial (`SALDO INICIAL`):**
   - Para qualquer conta que possua saldo inicial diferente de zero (seja positivo ou negativo), o OpenMoney inclui automaticamente um lançamento de abertura na data inicial do extrato:
     - **Descrição:** `SALDO INICIAL`
     - **Categoria:** vazia
     - **Valor:** valor exato do saldo de abertura da conta
     - **Conciliado:** `Sim`
   - Isso garante que a soma matemática na planilha (Excel, Numbers, Google Planilhas) feche no centavo com o saldo real do banco.
4. **Colunas Exportadas:**
   `"Data";"Conta";"Descrição";"Categoria";"Nota";"Valor";"Conciliado";"Fatura";"Conta Favorita";"Conta Ativa";"Moeda";"Moeda Padrão";"Valor Moeda Padrão";"Taxa Câmbio";"Valor Contrapartida";"Moeda Contrapartida";"Taxa Transferência";"Tags"`
5. **Compatibilidade Total:** Arquivos gerados com codificação **UTF-8 com BOM** e separador ponto e vírgula (`;`), abrindo perfeitamente no Excel sem distorcer caracteres acentuados.

---

## 3. 🏦 Exportação e Importação de Contas em CSV

O OpenMoney permite exportar e importar o cadastro completo de contas bancárias, carteiras e cartões de crédito em arquivo CSV padronizado.

### Exportar Contas
Na aba **Exportar**, localize o quadro **Exportar Contas Cadastradas** e clique em **Exportar Contas...**. O sistema gera um arquivo com todos os atributos das contas:
- **ID:** identificador interno da conta.
- **Nome:** nome da conta (ex.: *Itaú Personalité*, *Nubank Mastercard*).
- **Tipo:** `Corrente`, `Cartão de Crédito`, `Investimento`, `Poupança`, `Dinheiro` ou `Outro`.
- **Saldo Inicial:** saldo de abertura em formato monetário (ex.: `1.500,00` ou `-200,00`).
- **Moeda:** código ISO de 3 letras da moeda da conta (ex.: `BRL`, `USD`, `EUR`).
- **Favorita / Inativa:** indicadores booleanos (`Sim` ou `Não`).
- **Entidade / Negócio:** classificação (ex.: `PF` ou `PJ`).
- **Dados Bancários:** Código do Banco, Agência e Número da Conta.
- **Observações:** anotações e notas da conta.
- **Saldo Mínimo:** limite de segurança ou saldo de reserva planejado.
- **Logo:** identificador do logotipo da instituição.
- **Configurações de Cartão:** Dia de Fechamento (`closeDay`), Dia de Vencimento (`dueDay`) e Conta para Débito de Fatura (`pay`).
- **Atalhos da Carteira:** aliases configurados para captura automática via Apple Wallet.

### Importar Contas
Na aba **Importar**, clique em **Importar Contas...** no quadro **Contas Cadastradas**:
1. O sistema lê o arquivo CSV reconhecendo delimitadores automáticos (`;` ou `,`) e cabeçalhos flexíveis sem distinção de maiúsculas ou acentos.
2. **Atualização Inteligente:** se uma conta do arquivo já existir na base (mesmo ID ou mesmo Nome), seus atributos cadastrais são atualizados sem apagar o histórico de lançamentos. Contas inéditas são criadas automaticamente.
3. Ao término, um resumo exibe a quantidade de novas contas cadastradas e contas existentes atualizadas.

---

## 4. 🏷️ Exportação e Importação de Categorias em CSV

Permite transferir árvores completas de categorias e subcategorias entre bases de dados:
- **Exportação:** gera arquivo com as colunas `"Tipo"`, `"Categoria Principal"`, `"Subcategoria"` e `"Categoria Completa"` formatada com separador hierárquico `›` (ex.: `"Alimentação › Restaurantes"`).
- **Importação:** cria automaticamente as categorias principais e suas respectivas subcategorias, identificando separadores (`›`, `>`, `/`, `:`) e ignorando duplicatas existentes.

---

## 5. 🏦 Conciliação Bancária via OFX

Permite importar extratos de contas correntes e faturas de cartão de crédito no formato padrão do mercado financeiro (`.ofx`):
1. Acesse **Extrato da Conta** e clique no ícone **OFX** no cabeçalho (ou via **Módulos › Importação / Exportação › Conciliar OFX...**).
2. O OpenMoney analisa todas as transações do arquivo, compara com os lançamentos já cadastrados no mês e exibe a tela de conciliação:
   - **Pareamento Automático:** lançamentos com mesma data e valor são pré-vinculados para conciliação em 1 clique.
   - **Sugestão de Categorias e Transferências:** o sistema reconhece históricos anteriores para sugerir a classificação adequada.
   - **Conferência de Saldo:** validação matemática entre o saldo final do extrato OFX e o saldo apurado no OpenMoney.

---

## 6. 📱 Integração Apple Wallet & Atalhos iOS

Para usuários de iPhone e iPad, o OpenMoney oferece integração direta com o app Carteira da Apple:
1. Ao exportar lançamentos de cartões via Atalhos do iOS, utilize a opção **Importar Carteira iOS** no menu de importação.
2. O sistema reconhece os aliases vinculados a cada cartão de crédito (`Atalhos Carteira`), associando as compras diretamente à conta e à fatura correta.
