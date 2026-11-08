// OpenMoney Coletor - Smart Account Matcher & Structured Receipt Parser
import { normalizeStr, parseCurrencyToCents, todayISO } from './models.js';
import { coletorStorage } from './db.js';

// Noise words in bank and card notifications that should not cause false positives
const NOISE_WORDS = new Set([
  'mastercard', 'mastercad', 'master', 'mc',
  'visa', 'elo', 'hipercard', 'amex', // amex handled specifically
  'cartao', 'cartao de credito', 'cartao de debito',
  'card', 'credit', 'credito', 'debito', 'debit',
  'banco', 'bank', 'pagamentos', 's.a.', 'sa',
  'de', 'da', 'do', 'dos', 'das', 'e'
]);

// Synonym groups for financial brands & tier indicators
const SYNONYM_GROUPS = [
  ['uv', 'ultravioleta', 'ultra violeta'],
  ['amex', 'american express', 'americanexpress'],
  ['c6', 'c6 bank', 'c6 carbon', 'carbon'],
  ['bb', 'banco do brasil', 'ourocard'],
  ['itau', 'itaucard', 'itaú', 'personnalite', 'personnalité'],
  ['inter', 'banco inter'],
  ['bradesco', 'prime', 'aeternum'],
  ['santander', 'van gogh', 'sx', 'select', 'unlimited'],
  ['cef', 'caixa', 'caixa economica', 'caixa econômica'],
  ['nubank', 'nu'],
  ['plat', 'platinum'],
  ['inf', 'infinite'],
  ['blk', 'black']
];

// Tier keywords for conflict detection
const TIER_WORDS = {
  uv: ['uv', 'ultravioleta', 'ultra violeta'],
  platinum: ['platinum', 'plat'],
  gold: ['gold', 'ouro'],
  black: ['black', 'carbon', 'infinite', 'nanquim']
};

/**
 * Checks if two words/phrases are synonymous based on predefined groups.
 */
function areSynonyms(wordA, wordB) {
  if (!wordA || !wordB) return false;
  const a = normalizeStr(wordA);
  const b = normalizeStr(wordB);
  if (a === b) return true;

  for (const group of SYNONYM_GROUPS) {
    const normGroup = group.map(normalizeStr);
    const hasA = normGroup.some(g => g === a || a.includes(g) || g.includes(a));
    const hasB = normGroup.some(g => g === b || b.includes(g) || g.includes(b));
    if (hasA && hasB) return true;
  }
  return false;
}

/**
 * Cleans and tokenizes text, removing punctuation and short noise.
 */
function tokenize(text) {
  if (!text) return [];
  const norm = normalizeStr(text);
  return norm
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .map(t => t.trim())
    .filter(t => t.length >= 2);
}

/**
 * Parses structured key-value receipts (e.g. from iOS Shortcuts automation URL:
 * Data:03/11/2026;Conta:Nubank Mastercard Ultravioleta;Favorecido:Drogasil;Valor:30,99;
 */
export function parseStructuredReceipt(rawText) {
  if (!rawText || typeof rawText !== 'string') return null;
  const text = rawText.trim();

  // Detect key-value markers
  const hasKeyPattern = /(?:data|date|conta|cart[aã]o|account|card|favorecido|estabelecimento|loja|payee|local|valor|total|amount)\s*:/i.test(text);
  if (!hasKeyPattern) return null;

  const result = {
    isStructured: true,
    rawDate: '',
    rawAccount: '',
    rawPayee: '',
    rawAmount: '',
    rawCategory: '',
    rawMemo: ''
  };

  const segments = text.split(/[\r\n;]+/).map(s => s.trim()).filter(Boolean);
  let matchedCount = 0;

  for (const seg of segments) {
    const colonIdx = seg.indexOf(':');
    if (colonIdx === -1) continue;
    const key = seg.substring(0, colonIdx).trim().toLowerCase();
    const val = seg.substring(colonIdx + 1).trim();
    if (!val) continue;

    if (/^(data|date)$/i.test(key)) {
      result.rawDate = val;
      matchedCount++;
    } else if (/^(conta|cart[aã]o|account|card)$/i.test(key)) {
      result.rawAccount = val;
      matchedCount++;
    } else if (/^(favorecido|estabelecimento|loja|payee|local)$/i.test(key)) {
      result.rawPayee = val;
      matchedCount++;
    } else if (/^(valor|total|amount)$/i.test(key)) {
      result.rawAmount = val;
      matchedCount++;
    } else if (/^(cat|categoria|category)$/i.test(key)) {
      result.rawCategory = val;
      matchedCount++;
    } else if (/^(memo|obs|observacao|observação|nota)$/i.test(key)) {
      result.rawMemo = val;
      matchedCount++;
    }
  }

  if (matchedCount >= 2) {
    return result;
  }
  return null;
}

/**
 * Normalizes date into YYYY-MM-DD format.
 */
export function parseReceiptDate(dateStr) {
  if (!dateStr) return todayISO();
  const clean = dateStr.trim();

  // DD/MM/YYYY or DD-MM-YYYY
  const mBR = clean.match(/^(\d{1,2})[\/\.-](\d{1,2})[\/\.-](\d{2,4})$/);
  if (mBR) {
    let day = mBR[1].padStart(2, '0');
    let month = mBR[2].padStart(2, '0');
    let year = mBR[3];
    if (year.length === 2) year = `20${year}`;
    const dNum = parseInt(day, 10);
    const mNum = parseInt(month, 10);
    const yNum = parseInt(year, 10);
    if (dNum >= 1 && dNum <= 31 && mNum >= 1 && mNum <= 12 && yNum >= 2020 && yNum <= 2035) {
      return `${year}-${month}-${day}`;
    }
  }

  // Already YYYY-MM-DD
  const mISO = clean.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (mISO) return clean;

  return todayISO();
}

/**
 * 4-Tier Smart Account Resolution Hierarchy:
 * Tier 1: User-configured De-Para Aliases
 * Tier 2: Smart Banking Synonym & Token Scorer
 * Tier 3: Payee Habitual Account Memory (lastAcc)
 * Tier 4: Favorite or First Active Account Fallback
 */
export function matchAccount(notificationAccountName, structure, matchedPayee = null) {
  const activeAccs = Array.isArray(structure?.accounts)
    ? structure.accounts.filter(a => !a.inactive)
    : [];

  if (activeAccs.length === 0) return null;

  const rawInput = (notificationAccountName || '').trim();
  const normInput = normalizeStr(rawInput);

  // -------------------------------------------------------------
  // TIER 1: Explicit User-Configured De-Para Aliases
  // -------------------------------------------------------------
  if (normInput) {
    const aliases = coletorStorage.getAccountAliases();
    for (const [aliasPattern, targetAccId] of Object.entries(aliases)) {
      const normAlias = normalizeStr(aliasPattern);
      if (normAlias && (normInput === normAlias || normInput.includes(normAlias) || normAlias.includes(normInput))) {
        const found = activeAccs.find(a => a.id === targetAccId);
        if (found) {
          return { accId: found.id, account: found, tier: 1, method: 'alias' };
        }
      }
    }
  }

  // -------------------------------------------------------------
  // TIER 2: Smart Banking Synonym & Token Scorer
  // -------------------------------------------------------------
  if (normInput) {
    const inputTokens = tokenize(normInput).filter(t => !NOISE_WORDS.has(t));
    let bestScore = -1;
    let bestAcc = null;

    for (const acc of activeAccs) {
      const normAccName = normalizeStr(acc.name);
      let score = 0;

      // Direct full match or substring match
      if (normAccName === normInput) {
        score += 100;
      } else if (normInput.includes(normAccName)) {
        score += 80;
      } else if (normAccName.includes(normInput)) {
        score += 70;
      }

      // Amex specific whole-phrase match
      const isAmexInput = normInput.includes('american express') || normInput.includes('amex');
      const isAmexAcc = normAccName.includes('american express') || normAccName.includes('amex');
      if (isAmexInput && isAmexAcc) {
        score += 60;
      }

      // Token overlap and synonym matching
      const accTokens = tokenize(normAccName).filter(t => !NOISE_WORDS.has(t));

      for (const inTok of inputTokens) {
        for (const accTok of accTokens) {
          if (inTok === accTok) {
            score += 30;
          } else if (areSynonyms(inTok, accTok)) {
            score += 35;
          }
        }
      }

      // Tier-level conflict checking (e.g. UV vs Platinum vs Gold vs Black)
      const inputIsUV = TIER_WORDS.uv.some(w => normInput.includes(w));
      const accIsUV = TIER_WORDS.uv.some(w => normAccName.includes(w));

      const inputIsPlat = TIER_WORDS.platinum.some(w => normInput.includes(w));
      const accIsPlat = TIER_WORDS.platinum.some(w => normAccName.includes(w));

      if (inputIsUV && accIsUV) {
        score += 40; // strong UV bonus
      } else if (inputIsUV && !accIsUV && (accIsPlat || normAccName.includes('black'))) {
        score -= 30; // penalty for non-UV tier when UV specified
      }

      if (inputIsPlat && accIsPlat) {
        score += 40;
      } else if (inputIsPlat && accIsUV) {
        score -= 30; // penalty for UV when Platinum specified
      }

      // Card account preference when notification mentions card terms
      const isCardNotification = /cart[aã]o|credit|credito|debito|master|visa|amex|ourocard|carbon|ultravioleta|platinum|black|gold/i.test(normInput);
      if (isCardNotification && (acc.type === 'Cartão de crédito' || acc.type === 'Cartão pré-pago')) {
        score += 10;
      }

      if (score > bestScore) {
        bestScore = score;
        bestAcc = acc;
      }
    }

    if (bestAcc && bestScore >= 35) {
      return { accId: bestAcc.id, account: bestAcc, tier: 2, method: 'smart_synonym', score: bestScore };
    }
  }

  // -------------------------------------------------------------
  // TIER 3: Payee Habitual Account Memory (lastAcc from full database)
  // -------------------------------------------------------------
  if (matchedPayee && matchedPayee.lastAcc) {
    const habitualAcc = activeAccs.find(a => a.id === matchedPayee.lastAcc);
    if (habitualAcc) {
      return { accId: habitualAcc.id, account: habitualAcc, tier: 3, method: 'payee_habitual' };
    }
  }

  // -------------------------------------------------------------
  // TIER 4: Favorite or First Active Account Fallback
  // -------------------------------------------------------------
  const favAcc = activeAccs.find(a => a.favorite);
  const fallback = favAcc || activeAccs[0];
  return { accId: fallback.id, account: fallback, tier: 4, method: 'fallback_favorite' };
}
