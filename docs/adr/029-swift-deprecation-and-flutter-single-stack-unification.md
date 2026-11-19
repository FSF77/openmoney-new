# ADR 029: Descontinuação da Stack Swift e Unificação Oficial na Stack Flutter Multiplataforma

**Status:** ✅ Aceito e Implementado  
**Data:** 2026-11-19  
**Escopo:** Governança multiplataforma, repositórios GitHub e consolidação da documentação em `OpenMoneyFlutter/docs`

---

## 1. Contexto

Até a versão **`v2.5.0`** (18/11/2026), o ecossistema **OpenMoney** manteve duas stacks paralelas operando em equivalência funcional estrita 1:1 sobre o Schema `v: 7` e o motor Cloud Sync v2:

1. **`OpenMoneySwift`** (Swift/SwiftUI nativo para macOS e iOS/iPadOS — historicamente em `FSF77/openmoney` e `FSF77/openmoney-releases`).
2. **`OpenMoneyFlutter`** (Flutter/Dart multiplataforma para macOS, Windows, Web PWA e Mobile iOS/Android — em `FSF77/openmoney-new`).

Com a entrega integral da `v2.5.0`, a stack **OpenMoney Flutter** atingiu paridade funcional completa e maturidade plena em produção em todas as plataformas-alvo:
- Aplicativos Desktop nativos de alto desempenho para **macOS (`arm64`/`x64`)** e **Windows (`x64`)** com auto-update e verificação `SHA-256`;
- Aplicação **Web PWA** responsiva hospedada na Cloudflare Pages (`https://openmoney.app.br`);
- Suporte **Mobile (iOS/iPadOS e Android)** e integração contínua com o **OpenMoney Coletor PWA**;
- Motor contábil unificado (`MoneyStore` + `CashFlowEngine` + `OfxReconciliationService`), **Cloud Sync v2** em tempo real (Cloudflare D1 + Durable Objects + criptografia `AES-256-GCM`), isolamento atômico de cache (`cloud_cache/`), backups diários em `.zip` e **Anti-Wipe Guard em 3 camadas**;
- OCR local nativo (`Apple Vision` / `PDFKit` no macOS via `/usr/bin/swift` e `Windows.Media.Ocr` no Windows) combinado com **IA Multimodal Google Gemini (BYOK)**.

Manter uma segunda base de código paralela em Swift implicava duplicação constante de esforço de implementação, revisão e testes sem entregar plataformas ou capacidades adicionais ao usuário final.

---

## 2. Decisão Arquitetural

1. **Descontinuação e Congelamento da Stack Swift (`v2.5.0`):**
   - O projeto `OpenMoneySwift` é oficialmente descontinuado e congelado na versão **`v2.5.0` (Build 190)**.
   - Os repositórios Swift legados passam a ser identificados com banners explícitos de descontinuação/arquivamento e renomeados no GitHub para:
     - Código-fonte legado: `FSF77/openmoney-swift`
     - Canal de releases legado: `FSF77/openmoney-swift-releases`

2. **Unificação na Stack Única Flutter (`OpenMoneyFlutter`):**
   - O projeto **`/Users/fabiano/Developer/OpenMoneyFlutter`** torna-se a **única fonte da verdade** para todas as regras de negócio, modelos de dados, interface de usuário, sincronização e distribuição oficial (**macOS, Windows, Web e Mobile**).
   - O diretório `AGENTS.md` passa a refletir exclusivamente o ciclo de desenvolvimento, testes (`flutter analyze` / `flutter test`) e publicação da stack Flutter + backend Cloudflare.

3. **Manutenção do Nome do Repositório `FSF77/openmoney-new`:**
   - O repositório oficial do OpenMoney Flutter **permanece como `FSF77/openmoney-new`**.
   - Motivo técnico: os binários Desktop (macOS e Windows) já instalados nas máquinas dos usuários consultam diretamente `https://raw.githubusercontent.com/FSF77/openmoney-new/.../version.json` no `UpdateService`; como o domínio `raw.githubusercontent.com` não garante redirecionamento confiável após troca de nome de repositório (retornando `HTTP 404`), alterar o nome interromperia a atualização automática dos clientes existentes, além de impactar instaladores e a integração com a Cloudflare Pages (`openmoney.app.br`).

4. **Consolidação da Documentação em `/Users/fabiano/Developer/OpenMoneyFlutter/docs`:**
   - Toda a documentação oficial (ADRs, diagramas de arquitetura, dicionário de dados e manuais do usuário) passa a residir diretamente e unicamente em **`/Users/fabiano/Developer/OpenMoneyFlutter/docs`**, eliminando o diretório separado `/Users/fabiano/Developer/OpenMoneyDocs` e o passo de cópia manual/script entre repositórios.

---

## 3. Consequências

- **Positivas:**
  - Eliminação total de retrabalho e risco de divergência entre stacks;
  - Ciclo de entrega mais rápido e uniforme para macOS, Windows, Web e Mobile a partir de uma única base Dart/Flutter;
  - Documentação, ADRs e `README.md` versionados atomicamente junto com o código-fonte e os scripts de release no mesmo repositório (`FSF77/openmoney-new`);
  - Retrocompatibilidade 100% preservada para o Schema `v: 7`, bases `openmoney.json` existentes e auto-update Desktop.
- **Cuidados Mantidos:**
  - O serviço [local_ocr_service.dart](../../lib/services/local_ocr_service.dart) utiliza apenas `/usr/bin/swift` nativo do macOS para invocar `PDFKit` e `Apple Vision`, sem qualquer dependência do repositório `OpenMoneySwift`, permanecendo plenamente funcional.
