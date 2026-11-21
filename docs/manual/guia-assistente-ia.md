# Guia do Usuário: Assistente Financeira com IA (Gemini, Claude, ChatGPT, Apple Intelligence e Siri)

A **Assistente Financeira do OpenMoney** combina a inteligência de modelos de linguagem de ponta com um motor financeiro local determinístico e seguro para ajudar você a **lançar gastos por texto ou voz**, **ler comprovantes e faturas em PDF/foto**, **organizar lançamentos sem categoria** e **entender detalhadamente seus hábitos financeiros** com base nos dados reais do seu arquivo `openmoney.json`.

---

## 1. Ativação Global e Personalização

Você tem controle total sobre o uso de recursos de Inteligência Artificial no OpenMoney:

- **Ativação / Desativação Mestre:**
  - Em **Ajustes & Personalização › Assistente Financeira & IA**, utilize o switch **"Ativar Assistente Financeira & IA"**.
  - **Desativação Total:** Quando desativado, o aplicativo desativa por completo o ecossistema de IA e **remove todos os botões, atalhos e referências visuais** em todas as telas (botão da barra superior, botões contextuais de extratos, relatórios, faturas, previsões, atalho global e o card de Insights Financeiros no Dashboard Geral).
- **Etiqueta de Privacidade (`Privado`):**
  - No cabeçalho do painel da Assistente, a etiqueta verde discreta e centralizada indica que seus dados sensíveis e sua base bruta nunca são expostos na íntegra a terceiros.

---

## 2. Como Abrir a Assistente (Quando Ativada)

- **Atalho Global (Desktop e Web):** Pressione **`Cmd + J`** (macOS) ou **`Ctrl + J`** (Windows/Web) em qualquer tela para abrir ou recolher o painel lateral da Assistente.
- **Barra Superior:** Clique no botão **`✨ Assistente IA`** no topo da janela (ou no ícone compacto `✨` em smartphones e telas estreitas).
- **Botões Contextuais nas Telas:**
  - **Relatórios:** clique em **`✨ Explicar Variações`** para analisar aumentos em categorias e descobrir os estabelecimentos responsáveis.
  - **Extrato de Cartão de Crédito:** clique no ícone **`✨`** ao lado do botão OFX para abrir o **Raio-X da Fatura** (compras à vista vs parceladas e impacto contratado para os próximos meses).
  - **Contas a Pagar & Receber:** clique em **`✨ Detectar Recorrências`** para identificar assinaturas e contas periódicas com possíveis reajustes ou ainda não automatizadas.
  - **Previsões Orçamentárias:** clique em **`✨ Analisar IA`** para avaliar envelopes de previsão esgotados ou com desvios.
  - **Lançamentos Gerais:** clique em **`✨ Organizar com IA`** para auditar lançamentos sem categoria ou inconsistências.

---

## 3. Formas de Consumo: Minha Chave, Nuvem Cloud e Modo Sem Chave

O OpenMoney oferece três formas flexíveis e transparentes para atender a todos os perfis de usuário, com explicações contextuais via tooltip em cada opção:

| Forma de Consumo | Descrição Operacional | Privacidade & Requisitos |
| :--- | :--- | :--- |
| **Minha Chave (BYOK)** | Usa sua própria chave de API configurada no aplicativo (Google Gemini Flash, Anthropic Claude ou OpenAI ChatGPT). | **Gratuito / Baixo Custo:** O Google Gemini possui camada gratuita no Google AI Studio. A chave fica gravada exclusivamente no seu aparelho (`config.json` ou `localStorage`). |
| **Nuvem Cloud** | Utiliza a infraestrutura de IA gerenciada do OpenMoney Cloud através do Cloudflare Workers & D1. | **Zero Configuração:** Requer apenas estar conectado à sua conta OpenMoney Cloud. Cota diária inclusa na conta sem necessidade de obter chaves de terceiros. |
| **Modo Sem Chave (Prompt Bridge)** | Gera um resumo compacto e seguro dos seus dados para você copiar e colar na versão web do ChatGPT, Claude ou Gemini no navegador. | **Zero Custo e Sem Chaves:** A barra de **Copiar Contexto** e **Colar Resposta** fica visível no rodapé do painel da Assistente com botões compactos e tooltips. Se a IA externa responder com ações em JSON, o OpenMoney as interpreta automaticamente em cartões de confirmação! |

> [!NOTE]
> No macOS e iOS, você também pode selecionar **Apple Intelligence Local** como provedor, processando os comandos no próprio hardware Apple Silicon sem qualquer envio de dados para a internet.

---

## 4. Barra de Ações Rápidas (Ícones com Tooltip)

No topo do painel da Assistente, uma barra compacta de ferramentas com ícones elegantes e tooltips oferece diagnósticos imediatos em 1 clique, sem poluicão visual ou badges numéricos vermelhos:

- 📈 **Explicar Aumentos:** Avalia o mês atual contra o mês anterior e a média trimestral. O tooltip indica quantas categorias registraram variações expressivas de gastos.
- 💳 **Analisar Faturas:** Raio-X detalhado da fatura aberta do cartão principal, separando compras à vista de parcelas e antecipações.
- 🔁 **Detectar Recorrências:** Detecta cobranças periódicas nos últimos 12 meses. O tooltip informa a contagem de assinaturas e recorrências identificadas.
- 🪄 **Organizar Base:** Localiza lançamentos pendentes de classificação e possíveis inconsistências.
  - **Filtro Anti-Falso-Positivo:** A rotina inteligente de deduplicação **exclui automaticamente transações já conciliadas** (`rec == true`), **compras parceladas** (`plan` ou parcelas `pn`/`pt`) e **pagamentos antecipados**, garantindo que compras legítimas parceladas ou adiantadas não sejam sugeridas indevidamente como duplicidades.
- 📑 **Diagnóstico Geral:** Apresenta uma síntese financeira completa da posição corrente.

---

## 5. O Que Você Pode Pedir à Assistente

### Lançamentos Rápidos por Linguagem Natural
Digite ou dite comandos diretos em linguagem do cotidiano:
- *"Almoço executivo 48,50 no débito Itaú hoje #Alimentação"*
- *"Comprei tênis 600 em 3x no Nubank ontem #Vestuário"*
- *"Recebimento de consultoria 3.500 no BB dia 10/11"*
- *"Transferir 800 da NuConta para a Poupança Caixa"*

A Assistente apresenta um **Cartão de Proposta de Ação** com conta, categoria aprendida pelo histórico, `#tags` e alertas preventivos se a categoria estiver próxima do limite de gastos. Basta clicar em **Confirmar** para registrar ou **Editar** para ajustar.

### Leitura de Comprovantes e Faturas (PDF e Foto)
- Clique no ícone de anexo (`📎` / `📄`) na caixa de texto da Assistente.
- Selecione um arquivo PDF de fatura, cupom fiscal, foto de recibo ou extrato.
- O sistema extrai automaticamente favorecido, data, valor e itens, comparando contra o que você já lançou na conta para marcar itens já existentes e evitar duplicações.

### Integração com Siri e Atalhos da Apple
No macOS e iOS, execute o comando direto pela Siri ou configure rotinas no app **Atalhos (Shortcuts)**:
- Diga: *"E aí Siri, perguntar ao OpenMoney: gastei 35 reais no posto hoje"*
- Ou acione URLs estruturadas para automações externas:
  - `openmoney://?prompt=Gastei%2035%20no%20posto`
  - `https://openmoney.app.br/?prompt=Qual%20meu%20saldo%20previsto`

---

## 6. Desempenho e Fluidez em Tempo Real

A Assistente foi desenvolvida com foco em alta responsividade:
- **Cache Reativo Inteligente (`AiInsightsCache`):** Análises analíticas pesadas (como aumentos de categorias e detecção de recorrências) são calculadas em segundo plano com *debounce* de 1500ms e verificação de assinatura por revisão de dados (`dataRevision`).
- **Zero Travamento:** Digitar mensagens na caixa de texto ou adicionar, editar e excluir lançamentos com o painel da Assistente aberto não gera congelamentos nem aciona a rodinha de espera do sistema.
