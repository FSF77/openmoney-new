# ADR 037 — Preenchimento Automático (Autofill), Chaves-senha (Passkeys / WebAuthn / FIDO2) e Bloqueio Biométrico

## Status
Aprovado e Implementado (Novembro/2026).

---

## 1. Contexto e Motivação
A modernização da experiência de autenticação e segurança do ecossistema OpenMoney demandava três pilares fundamentais:
1. **Reconhecimento por Gerenciadores de Senhas (Autofill)**:
   Usuários de ferramentas como 1Password, Bitwarden, Apple Chaves (Keychain) e Google Password Manager enfrentavam atritos na tela de login por falta de dicas semânticas e grupos de preenchimento padronizados W3C/Flutter.
2. **Autenticação Passwordless via Chaves-senha (Passkeys / WebAuthn / FIDO2)**:
   Permitir que usuários façam login com 1 clique através de biometria de hardware (Touch ID, Windows Hello, Face ID) sem depender de digitação de senhas ou códigos pontuais por e-mail, utilizando criptografia assimétrica segura.
3. **Bloqueio Biométrico Opcional do Aplicativo**:
   Atender à necessidade de usuários que compartilham computadores ou dispositivos móveis e desejam exigir confirmação biométrica para abrir o aplicativo, com configuração desativada por padrão e flexibilidade total.

---

## 2. Decisões de Arquitetura

### 2.1. Preenchimento Automático W3C / Flutter Autofill
- **Agrupamento Semântico (`AutofillGroup`)**:
  - Envolvimento dos formulários de login, registro e redefinição em `AutofillGroup` em `auth_view.dart` e `cloud_account_modal.dart`.
- **Dicas Semânticas de Sistema (`autofillHints`)**:
  - Nome: `[AutofillHints.name]`.
  - E-mail: `[AutofillHints.email, AutofillHints.username]`.
  - Senha no Login: `[AutofillHints.password]`.
  - Senha no Cadastro / Redefinição: `[AutofillHints.newPassword]`.
  - Código de Confirmação: `[AutofillHints.oneTimeCode]`.
- **Finalização de Contexto e Solicitação de Salvamento**:
  - Execução compulsória de `TextInput.finishAutofillContext(shouldSave: true)` após validação bem-sucedida de credenciais, acionando o prompt nativo de salvar/atualizar senha nos gerenciadores.

### 2.2. Arquitetura de Chaves-senha (WebAuthn / FIDO2)
- **Criptografia Assimétrica de Hardware**:
  - Geração de pares de chave pública/privada no Secure Enclave (Apple) ou TPM (Windows).
  - Algoritmos negociados: `ES256` (ECDSA P-256 com SHA-256, COSE `-7`) e `RS256` (RSASSA-PKCS1-v1_5, COSE `-257`).
- **Tabelas Relacionais no Cloudflare D1**:
  - `user_passkeys`: vincula `credential_id`, `public_key` (SPKI Base64URL), `user_id` e contador de assinaturas contra replay attacks.
  - `passkey_challenges`: desafios criptográficos efêmeros de 32 bytes gerados via `crypto.getRandomValues` com TTL estrito de 5 minutos.
  - `passkey_desktop_sessions`: sessões temporárias para handshake Desktop ↔ Navegador Web.
- **Validação Criptográfica Serverless (Cloudflare Pages Functions)**:
  - Verificação de assinatura nativa com `crypto.subtle.verify()` sobre `authenticatorData + SHA-256(clientDataJSON)`.
  - Conversão automatizada de assinaturas DER ASN.1 para IEEE P1363 raw (`derToP1363`).
- **Desktop Session Bridge**:
  - Ponte de autenticação permitindo que os apps Desktop (macOS e Windows) deleguem a asserção biométrica ao navegador padrão via `https://openmoney.app.br/?passkey_session=<id>` com recuperação automatizada de sessão por polling e expiração em 90 segundos.
- **Segmentação Estrita de Rotas Públicas vs. Privadas**:
  - As rotas de login (`/api/auth/passkey/login-options`, `login-verify`, `desktop-session`) são posicionadas no bloco público desprovido de token JWT prévio.
  - As rotas de gerenciamento (`register-options`, `register-verify`, `list`, `delete`) exigem sessão autenticada do usuário.

### 2.3. Bloqueio Biométrico Nativo e Persistência
- **Gerenciador Centralizado (`BiometricService`)**:
  - Singleton encapsulando o plugin oficial `local_auth`.
  - Detecção dinâmica de hardware e rótulo do SO (`Touch ID / Senha do Mac`, `Face ID / Touch ID`, `Windows Hello`, `Biometria`).
- **Parâmetro de Configuração (`requireBiometricUnlock`)**:
  - Tipo: `bool`, valor padrão `false` (abertura direta sem senha).
  - Persistido no arquivo de preferências locais `config.json` via `MoneyStore`.
  - Verificação biométrica prévia obrigatória antes de salvar a ativação nas Configurações, prevenindo bloqueio acidental.
  - Tela de desbloqueio elegante em Liquid Glass com fallback para a senha da máquina em caso de falha mecânica do sensor.

---

## 3. Consequências e Benefícios
- **Redução Drástica de Fricção no Login**: Acesso instantâneo sem necessidade de digitar credenciais ou consultar cofres externos.
- **Segurança Criptográfica Elevada**: Chaves privadas isoladas em hardware, imunes a ataques de phishing ou vazamento de banco de dados centralizado.
- **Privacidade Local Aumentada**: Proteção dos dados financeiros em máquinas compartilhadas via biometria com controle total do usuário.
- **Conformidade com Diretrizes do Ecossistema**: Registro compulsório no Dicionário de Dados oficial e testes automatizados dedicados.
