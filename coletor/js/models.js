// OpenMoney Coletor - Models & Helpers
export const SEP = " › ";
export const CARD_TYPE = "Cartão de crédito";

export function uid() {
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
  let result = "";
  for (let i = 0; i < 7; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

export function formatCurrency(cents, showSign = false) {
  if (typeof cents !== 'number' || isNaN(cents)) cents = 0;
  const isNegative = cents < 0;
  const absVal = Math.abs(cents);
  const reals = Math.floor(absVal / 100);
  const remainder = absVal % 100;
  
  const formattedReals = reals.toLocaleString('pt-BR');
  const formattedCents = remainder.toString().padStart(2, '0');
  const str = `R$ ${formattedReals},${formattedCents}`;
  
  if (isNegative) return `-${str}`;
  if (showSign && cents > 0) return `+${str}`;
  return str;
}

export function parseCurrencyToCents(raw) {
  if (!raw) return 0;
  let clean = raw.toString().trim()
    .replace(/^R\$\s?/, '')
    .replace(/\s/g, '');

  if (!clean) return 0;

  if (clean.includes(',') && clean.includes('.')) {
    clean = clean.replace(/\./g, '').replace(',', '.');
  } else if (clean.includes(',')) {
    clean = clean.replace(',', '.');
  }

  const num = parseFloat(clean);
  if (isNaN(num)) return 0;
  return Math.round(num * 100);
}

export function todayISO() {
  const d = new Date();
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function formatDateBR(iso) {
  if (!iso || iso.length < 10) return iso || '';
  const [y, m, d] = iso.split('-');
  return `${d}/${m}/${y}`;
}

export function normalizeStr(str) {
  if (!str) return '';
  return str.toString()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim();
}
