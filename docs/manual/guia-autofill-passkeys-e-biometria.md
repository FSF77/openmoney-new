# Guia do Usuário: Preenchimento Automático (Autofill), Chaves-senha (Passkeys) e Bloqueio Biométrico

Este guia orienta sobre como utilizar os recursos modernos de autenticação e proteção no **OpenMoney**: o **preenchimento automático nativo por gerenciadores de senhas**, o acesso passwordless por **Chaves-senha (Passkeys / WebAuthn / FIDO2)** e o **bloqueio biométrico por Touch ID, Windows Hello ou Face ID**.

---

## 🚀 1. Passo a Passo Prático de Uso (Visão do Usuário)

### A. Preenchimento Automático com Gerenciadores de Senha (Autofill)
Disponível nativamente na **Web (`https://openmoney.app.br`)**, **macOS**, **Windows**, **iOS** e **Android**. Compatível com **1Password, Bitwarden, Apple Chaves (iCloud Keychain), Google Password Manager** e navegadores modernos.

1. **Ao acessar a tela de Login ou Cadastro Online:**
   - Clique no campo **E-mail** ou **Senha**.
   - O seu gerenciador de senhas (ou navegador) exibirá automaticamente uma lista flutuante sugerindo as credenciais salvas para o domínio do OpenMoney.
   - Clique na credencial sugerida: o e-mail e a senha serão preenchidos instantaneamente.
2. **Ao criar uma nova conta ou alterar senha:**
   - O gerenciador reconhece a intenção de cadastro e sugere senhas fortes aleatórias de alta segurança.
3. **Ao confirmar o acesso ou cadastro:**
   - O sistema dispara a solicitação nativa do sistema operacional perguntando se deseja **Salvar** ou **Atualizar** a credencial no seu cofre de senhas.

---

### B. Como Cadastrar sua Chave-senha (Passkey)
A Chave-senha substitui completamente a digitação de senhas por biometria no seu hardware (**Touch ID no Mac/iPhone, Windows Hello no PC ou Biometria no Android**).

1. **Crie ou acesse sua conta no OpenMoney:**
   - Faça login na sua conta da nuvem (Web ou aplicativo Desktop).
2. **Abra o Gerenciador de Chaves-senha:**
   - Clique em **Cloud & Sincronização** na barra lateral.
   - Na aba **Configurações da Conta**, localize a seção **"Gerenciar Chaves-senha (Passkeys)"**.
3. **Cadastre este dispositivo:**
   - Clique no botão **"+ Cadastrar Chave-senha neste Dispositivo"**.
   - O sistema operacional abrirá o prompt nativo de confirmação biométrica:
     - *No Mac:* Encoste o dedo no sensor **Touch ID** ou confirme com a senha do Mac.
     - *No Windows:* Olhe para a câmera ou encoste o dedo no sensor do **Windows Hello**.
     - *No iPhone / iPad:* Olhe para a tela (**Face ID**) ou use o **Touch ID**.
4. **Pronto!**
   - Sua chave-senha será registrada com o nome do seu aparelho (ex: *MacBook Pro de Fabiano*, *Chrome no macOS*) e a data de criação.

---

### C. Como Fazer Login com Chave-senha (1 Clique)

#### 1. Na Web (`openmoney.app.br` ou Mobile)
1. Na tela inicial de boas-vindas / login, clique no botão destacado:
   ```
   ┌────────────────────────────────────────────────────────┐
   │  [ 🔑 Entrar com Chave-senha (Passkey) ]               │
   └────────────────────────────────────────────────────────┘
   ```
2. O navegador solicitará instantaneamente o seu **Touch ID, Face ID ou Windows Hello**.
3. Encoste o dedo ou olhe para a câmera: **o login é concluído imediatamente, sem digitar nenhuma senha**.

#### 2. Nos Aplicativos Desktop (macOS e Windows) — Desktop Session Bridge
Nos aplicativos de computador instalados, a autenticação por Chave-senha ocorre de forma transparente com o seu navegador padrão:
1. Na tela de login, clique em **"Entrar com Chave-senha (Passkey)"**.
2. O aplicativo abre automaticamente uma aba no seu navegador padrão (`openmoney.app.br/?passkey_session=...`) e exibe a mensagem no app: *"Aguardando confirmação biométrica no navegador..."*.
3. No navegador, valide o seu Touch ID / Windows Hello.
4. Assim que validado, o navegador exibe *"Autenticação concluída"* e o aplicativo desktop faz login sozinho, carregando seus dados imediatamente.

---

### D. Bloqueio Biométrico ao Abrir o Aplicativo (Opcional)
Para impedir que outras pessoas com acesso ao seu computador ou celular vejam suas finanças ao abrir o app:

1. Acesse o menu lateral e clique em **Ajustes & Personalização** (ou abra as Configurações).
2. Na seção **Geral & Inicialização**, localize a opção:
   - **"Bloqueio por Touch ID / Face ID / Windows Hello ao abrir o aplicativo"**.
3. **Por padrão, esta opção vem DESATIVADA** (o app abre direto sem pedir senha).
4. Para ativar:
   - Mude a chave para **Ativado**.
   - O sistema solicitará uma confirmação biométrica prévia no ato (para garantir que seu sensor está cadastrado e funcionando, evitando que você se tranque para fora).
5. **Ao abrir o app:**
   - Uma tela de proteção translúcida (Liquid Glass) será exibida com o botão para autenticar via biometria nativa. Assim que validado, a interface é liberada.

---

## 💡 2. Casos Reais de Uso e Exemplos do Dia a Dia

### Caso 1: Usuário que usa 1Password ou Bitwarden no Mac e Windows
- Ao abrir o OpenMoney na Web ou no Desktop, basta pressionar o atalho do seu cofre (ex: `Cmd + \` no Mac ou `Ctrl + \` no Windows) ou clicar no ícone do gerenciador que surge automaticamente nos campos de login. O e-mail e a senha são inseridos e a verificação é instantânea.

### Caso 2: Login rápido no dia a dia sem lembrar senhas (Passkey)
- Cadastre o Touch ID do seu notebook. Toda manhã, ao abrir o OpenMoney, basta 1 clique em **"Entrar com Chave-senha"** e repousar o dedo no sensor do teclado. Não há necessidade de consultar senhas nem de digitar códigos de SMS/e-mail.

### Caso 3: Computador compartilhado em casa ou no escritório
- Em um Mac ou PC usado por mais familiares ou colegas de trabalho, ative o **"Bloqueio por Touch ID / Windows Hello"** nas Configurações. Sempre que o aplicativo for iniciado, somente quem possui biometria cadastrada no computador conseguirá visualizar os saldos e lançamentos.

---

## 🔒 3. Gestão de Acessos, Segurança e FAQ

### Como desativar o bloqueio biométrico de abertura?
- Basta acessar **Ajustes & Personalização > Geral & Inicialização** e desmarcar a chave. A preferência é salva imediatamente no arquivo de configuração local (`config.json`).

### E se meu Touch ID ou Windows Hello falhar na tela de bloqueio?
- O prompt nativo do sistema operacional oferece automaticamente a opção de fallback: você pode digitar a **senha de usuário da máquina** (senha de login do Mac ou PIN do Windows) para liberar o aplicativo.

### O que acontece se eu perder ou trocar de aparelho?
- Como as Chaves-senha operam em conjunto com o seu e-mail cadastrado, você nunca perde o acesso à sua conta. Em um novo dispositivo, você pode entrar utilizando seu **e-mail e senha** (ou recuperar o acesso com o código de 6 dígitos enviado para seu e-mail) e, em seguida, cadastrar a Chave-senha do novo aparelho.

### Posso cadastrar mais de uma Chave-senha?
- **Sim!** Você pode registrar múltiplas chaves (ex.: seu MacBook de trabalho, seu computador pessoal com Windows e seu iPhone). Todas ficam listadas no painel **Cloud & Sincronização**, onde você pode visualizar a data do último uso de cada uma e remover chaves de aparelhos que não utiliza mais.

---

## ⚙️ 4. Detalhamento Técnico e Arquitetura Interna

Esta seção destina-se a desenvolvedores, auditores de segurança e administradores de sistema:

### A. Padrão WebAuthn / FIDO2 e Criptografia
- **Criptografia Assimétrica de Chave Pública:** Utiliza pares de chaves gerados pelo hardware de segurança (Apple Secure Enclave, TPM 2.0 no Windows). A chave privada nunca sai do dispositivo do usuário.
- **Algoritmos Suportados:**
  - `ES256` (ECDSA sobre curva NIST P-256 com SHA-256, algoritmo COSE `-7`).
  - `RS256` (RSASSA-PKCS1-v1_5 com SHA-256, algoritmo COSE `-257`).
- **Validação de Assinatura no Cloudflare Pages:**
  - As assertivas são validadas via `crypto.subtle.verify()` utilizando Web Crypto API nativa do Cloudflare Workers. Assinaturas no formato DER ASN.1 são convertidas para IEEE P1363 (formato padrão raw `r || s` de 64 bytes) pela rotina `derToP1363()`.

### B. Tabelas no Banco Relacional Cloudflare D1
1. **`user_passkeys`**:
   - `id` (UUID `pk_...`), `user_id` (FK), `credential_id` (identificador único da credencial em Base64URL), `public_key` (chave pública em formato SPKI Base64URL), `counter` (contador de assinaturas para prevenção de replay), `device_name`, `created_at`, `last_used_at`.
2. **`passkey_challenges`**:
   - `id` (UUID `ch_...`), `challenge` (32 bytes aleatórios via `crypto.getRandomValues`), `user_id` (opcional no login), `type` (`register` ou `login`), `created_at`, `expires_at` (expiração de 5 minutos).
3. **`passkey_desktop_sessions`**:
   - `id` (UUID `ds_...`), `token` (JWT de sessão emitido), `user_id`, `status` (`pending` ou `completed`), `created_at`, `expires_at` (expiração de 5 minutos).

### C. Desktop Session Bridge (Handshake Desktop ↔ WebAuthn)
- Como os motores nativos de Flutter Desktop não expõem a API W3C `navigator.credentials` do navegador, o aplicativo compõe uma sessão efêmera segura:
  1. Desktop chama `POST /api/auth/passkey/desktop-session` e obtém `sessionId`.
  2. Abre a URL de autenticação no navegador padrão do sistema: `https://openmoney.app.br/?passkey_session=<sessionId>`.
  3. O usuário autentica no navegador com Touch ID ou Windows Hello via `web/passkey.js`.
  4. O servidor associa o token JWT à sessão temporária e o aplicativo desktop recupera o token via polling com timeout de 90 segundos.
  5. A sessão temporária é apagada imediatamente após o consumo (`DELETE`).

### D. Bloqueio Biométrico Nativo (`local_auth`)
- Integrado via pacote oficial `local_auth: ^2.3.0`.
- Controlado pela preferência booleana `requireBiometricUnlock` no `config.json` local (armazenada de forma isolada do banco de dados).
- Suporta fallback nativo pelo sistema operacional em caso de erro físico de leitura biométrica.
