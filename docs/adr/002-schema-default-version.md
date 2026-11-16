# ADR 002: Histórico de Versões do Schema e Alinhamento de Versão Padrão

**Status:** 🏛️ Suplantado pelo ADR 001 / Resolvido  
**Suplantado por:** [ADR 001: Adoção do Schema v: 7](./001-schema-v7-adoption.md)  
**Data Original:** 31/10/2026 (Auditoria inicial)  
**Data de Resolução:** 31/10/2026  
**Autores:** Equipe OpenMoney (Engenharia Swift & Flutter)  

---

## 1. Contexto Histórico do Problema

Durante a análise comparativa entre as bases de código do **OpenMoneySwift** e do **OpenMoneyFlutter**, identificou-se uma discrepância no valor atribuído à versão padrão do arquivo de banco de dados (`openmoney.json`):

| Plataforma | Versão Padrão no Código | Inicializador de Base Vazia | Versão Alvo Suportada |
| :--- | :--- | :--- | :--- |
| **Swift (iOS/macOS)** | `v: 6` (legado) | `Database(v: 6, ...)` em `Models.swift` | `v: 7` (suporte a decodificação parcial) |
| **Flutter (Desktop/Web/Mobile)** | `v: 7` (moderno) | `Database(schemaVersion: 7, ...)` | `v: 7` (suporte integral) |

### Impacto Identificado na Época:
1. Se uma base de dados fosse criada do zero no Swift, o campo `"v"` era salvo como `6`.
2. Se a mesma base fosse salva posteriormente pelo Flutter, o campo `"v"` era promovido para `7`.
3. Essa alternância desnecessária gerava dúvidas sobre a paridade de funcionalidades e o suporte formal de campos modernos do Schema `v: 7` no cliente nativo Swift.

---

## 2. Linha do Tempo de Evolução do Schema

```
v:1 (2023) ──► v:2 (2024) ──► v:3 (2024) ──► v:4 (2025) ──► v:5 (2025) ──► v:6 (2025) ──► v:7 (2026)
 [Básico]      [Orçamentos]   [Relatórios]   [Tags/Recorr]  [Ajustes]     [Cartões v1]   [Schema Unificado]
```

### O que foi introduzido no Schema v: 7:
- **Centavos Inteiros:** `amt` e `opening` expressos como inteiros em todas as coleções, evitando imprecisão de frações decimais IEEE-754.
- **Configuração Completa de Cartões (`cardCfg`):**
  - `limit`: Limite do cartão em centavos.
  - `closeDay`: Dia de fechamento da fatura (corte).
  - `dueDay`: Dia de vencimento da fatura.
  - `payAccId`: Identificador da conta padrão para débito/pagamento da fatura.
- **Competência de Fatura (`ik` / Invoice Key):** Armazenamento explícito da competência nas transações de cartão e nas transações automáticas de conciliação (`inv:$cardId:$k`).
- **Tabela de Faturas Personalizadas (`invoices`):** Mapeamento por chave de competência (`YYYY-MM`) com datas customizadas de corte e vencimento quando alteradas pelo usuário.
- **Regra de Virada de Mês:** Ajuste de competência nos casos onde `dueDay <= closeDay`.

---

## 3. Resolução e Conclusão

A divergência foi formalmente encerrada através da decisão unânime documentada no [ADR 001](./001-schema-v7-adoption.md):

1. **O Swift teve seu construtor padrão atualizado para `v: 7`** em [Models.swift](file:///Users/fabiano/Developer/OpenMoneySwift/Sources/OpenMoney/Models.swift#L480).
2. O Flutter manteve `schemaVersion: 7` como padrão único.
3. Ambas as plataformas passaram a carregar, migrar e salvar bases exclusivamente no Schema `v: 7`.

Este documento permanece no repositório exclusivamente como registro histórico de auditoria e contexto técnico.
