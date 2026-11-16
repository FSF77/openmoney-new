# ADR 001: Adoção do Schema v: 7 como Padrão Unificado Multi-Stack

**Status:** ✅ Aprovado e Implementado  
**Data do Contexto:** 31/10/2026  
**Data de Implementação e Validação:** 31/10/2026  
**Decisores:** Tech Lead / Equipe de Arquitetura OpenMoney  
**Impacto:** Base de dados compartilhada (`openmoney.json`), modelos Swift e modelos Dart/Flutter  

---

## 1. Contexto

O **OpenMoney** é um aplicativo financeiro pessoal multiplataforma com duas bases de código ativas:
- **OpenMoneySwift** (nativo macOS e iOS) — **Fonte da verdade** contábil e de regras de negócio.
- **OpenMoneyFlutter** (multiplataforma macOS, Windows, Web, iOS e Android) — Replicador fiel de comportamento.

Ambas as stacks operam sobre o mesmo arquivo de banco de dados (`openmoney.json`). 

Historicamente, o schema evoluiu pelas seguintes iterações:
- **v:1 a v:5**: Estruturação inicial de contas, transações, categorias e orçamentos.
- **v:6**: Introdução de configurações básicas de cartões de crédito e recorrências.
- **v:7**: Unificação de valores monetários estritamente em centavos inteiros (`amt`, `opening`), suporte completo a faturas e ciclos de corte/vencimento (`cardCfg`, `inv`), identificador de competência de fatura (`ik`), debouncing de persistência atômica de 350ms e migração de competência de cartões quando `dueDay <= closeDay`.

Na auditoria técnica inicial, constatou-se que o Flutter gravava e inicializava bases no formato **v: 7**, enquanto o inicializador padrão de banco vazio no Swift (`Database.init()`) ainda continha fallback para `v: 6`, embora os decodificadores do Swift já suportassem todas as propriedades do v: 7.

---

## 2. Decisão

**Adotou-se o Schema `v: 7` como a versão canônica e obrigatória em todas as plataformas do ecossistema OpenMoney.**

### Ações Executadas:
1. **Swift (`Models.swift`):**
   - O construtor padrão `Database.init()` foi atualizado de `v: 6` para `v: 7`.
   - Garantida a consistência de serialização e desserialização de todos os campos novos (`cardCfg`, chaves de fatura `invoices`, metadados de competência `ik`).
2. **Flutter (`openmoney_models.dart`):**
   - Ratificado o padrão `schemaVersion = 7` no modelo `Database` e em todas as rotinas de carga/exportação.
3. **Regras de Persistência no `AGENTS.md`:**
   - Formalizada a obrigatoriedade de compatibilidade bidirecional com o Schema `v: 7` sem divergências estruturais.

---

## 3. Estrutura do Schema v: 7

Abaixo está a especificação dos campos obrigatórios da base unificada `openmoney.json`:

```json
{
  "v": 7,
  "accounts": [
    {
      "id": "acc-uuid",
      "name": "Conta Corrente",
      "type": "checking",
      "opening": 150000,
      "curr": "BRL",
      "cardCfg": {
        "limit": 500000,
        "closeDay": 25,
        "dueDay": 5,
        "payAccId": "acc-checking-uuid"
      },
      "invoices": {
        "2026-11": {
          "close": "2026-10-25",
          "due": "2026-11-05",
          "manual": false
        }
      }
    }
  ],
  "transactions": [
    {
      "id": "tx-uuid",
      "accId": "acc-uuid",
      "date": "2026-11-01",
      "amt": -12550,
      "desc": "Supermercado",
      "catId": "cat-alimentacao",
      "status": "cleared",
      "ik": "2026-11",
      "auto": false
    }
  ],
  "categories": [],
  "budgets": [],
  "recurrences": []
}
```

---

## 4. Consequências e Benefícios

### Positivas:
- **Interoperabilidade Total:** Um usuário pode abrir exatamente a mesma base `openmoney.json` no Mac (Swift nativo), no Windows (Flutter desktop), no iPhone ou na Web sem qualquer incompatibilidade ou perda de dados.
- **Rigor Monetário:** O uso estrito de centavos inteiros (`amt`, `opening` em `Int` / `int`) elimina erros de arredondamento de ponto flutuante em relatórios e demonstrativos.
- **Previsibilidade de Faturas:** A presença de `cardCfg` e `ik` padronizados garante que as faturas de cartão de crédito fechem e vençam nas datas corretas em qualquer plataforma.

### Riscos Mitigados:
- **Degradação de Schema:** Não é permitida escrita em versões legadas (v:6 ou anteriores). Bases antigas são transparentemente migradas para `v: 7` no carregamento.
- **Perda de Dados:** Mecanismo de backup atômico diário ativado em ambas as plataformas antes de qualquer escrita em disco.

---

## 5. Validação Técnica

- **Swift:** Compilação com `swift build` aprovada sem avisos.
- **Flutter:** Execução da suite de testes `flutter test` com 26/26 testes aprovados, incluindo testes específicos de leitura e escrita do Schema `v: 7`.
