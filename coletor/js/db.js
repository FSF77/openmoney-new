// OpenMoney Coletor - Local Storage & Export Engine
import { normalizeStr } from './models.js';

const STORAGE_KEY_STRUCTURE = 'om_coletor_structure';
const STORAGE_KEY_PENDING = 'om_coletor_pending_txs';

class ColetorStorage {
  // Load cached accounts, categories and payees
  getStructure() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY_STRUCTURE);
      return raw ? JSON.parse(raw) : null;
    } catch {
      return null;
    }
  }

  // Save structure extracted from full openmoney.json
  saveStructure(structure) {
    localStorage.setItem(STORAGE_KEY_STRUCTURE, JSON.stringify(structure));
  }

  // Live Autocomplete for Payee (as user types)
  searchPayees(query) {
    if (!query) return [];
    const normQ = normalizeStr(query);
    if (!normQ) return [];
    const structure = this.getStructure();
    if (!structure || !Array.isArray(structure.frequentPayees)) return [];

    const matches = [];
    for (const item of structure.frequentPayees) {
      const normP = normalizeStr(item.payee);
      if (normP.includes(normQ)) {
        matches.push(item);
      }
    }
    return matches.slice(0, 15);
  }

  // Import structure from openmoney.json (lightweight extraction)
  importFromFullDB(fullDb, fileName = 'openmoney.json') {
    if (!fullDb || !Array.isArray(fullDb.accounts)) {
      throw new Error('Arquivo JSON inválido: não contém a chave "accounts".');
    }

    const txs = Array.isArray(fullDb.txs) ? fullDb.txs : [];

    // Calculate current reconciled balance for each account (only t.rec === true)
    const accounts = fullDb.accounts.map(acc => {
      let balance = acc.opening || 0;
      for (const t of txs) {
        if (t.acc === acc.id && t.rec === true) {
          balance += t.amt;
        }
      }
      return {
        id: acc.id,
        name: acc.name,
        type: acc.type || 'Corrente',
        favorite: Boolean(acc.favorite),
        inactive: Boolean(acc.inactive),
        balance: balance
      };
    });

    // Extract categories
    const cats = Array.isArray(fullDb.cats) ? fullDb.cats : [];

    // Extract frequent payees with their latest category and type
    const payeeMap = new Map();
    for (const t of txs) {
      if (t.auto || t.xfer || !t.payee) continue;
      const clean = t.payee.replace(/\s\(\d+\/\d+\)$/, '').trim();
      if (!clean) continue;
      const norm = clean.toLowerCase();
      if (!payeeMap.has(norm)) {
        payeeMap.set(norm, {
          payee: clean,
          cat: t.cat || '',
          isExpense: t.amt < 0,
          count: 1,
          lastDate: t.date
        });
      } else {
        const item = payeeMap.get(norm);
        item.count += 1;
        if (t.date > item.lastDate) {
          item.lastDate = t.date;
          item.cat = t.cat || item.cat;
          item.isExpense = t.amt < 0;
        }
      }
    }

    const frequentPayees = Array.from(payeeMap.values())
      .sort((a, b) => {
        if (b.count !== a.count) return b.count - a.count;
        return (b.lastDate || '').localeCompare(a.lastDate || '');
      })
      .slice(0, 1000);

    const structure = {
      baseName: fileName,
      updatedAt: new Date().toISOString(),
      accounts: accounts,
      cats: cats,
      frequentPayees: frequentPayees
    };

    this.saveStructure(structure);
    return structure;
  }

  // Get pending transactions list
  getPendingTransactions() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY_PENDING);
      return raw ? JSON.parse(raw) : [];
    } catch {
      return [];
    }
  }

  // Save pending transactions list
  savePendingTransactions(list) {
    localStorage.setItem(STORAGE_KEY_PENDING, JSON.stringify(list));
  }

  // Add new transaction to pending queue
  addPendingTransaction(tx) {
    const list = this.getPendingTransactions();
    list.unshift(tx); // most recent first
    this.savePendingTransactions(list);
    return list;
  }

  // Update a pending transaction
  updatePendingTransaction(id, updatedFields) {
    const list = this.getPendingTransactions();
    const idx = list.findIndex(t => t.id === id);
    if (idx >= 0) {
      list[idx] = { ...list[idx], ...updatedFields };
      this.savePendingTransactions(list);
      return true;
    }
    return false;
  }

  // Delete a pending transaction
  deletePendingTransaction(id) {
    let list = this.getPendingTransactions();
    list = list.filter(t => t.id !== id);
    this.savePendingTransactions(list);
    return list;
  }

  // Clear all pending transactions (after successful import on Mac)
  clearPendingTransactions() {
    localStorage.setItem(STORAGE_KEY_PENDING, JSON.stringify([]));
  }

  // Export pending transactions into openmoney_inbox.json
  async exportPendingToMac() {
    const pending = this.getPendingTransactions();
    if (pending.length === 0) {
      throw new Error('Não há lançamentos pendentes para exportar.');
    }

    const payload = {
      v: 6,
      source: "OpenMoney Coletor Mobile",
      exportedAt: new Date().toISOString(),
      count: pending.length,
      txs: pending.map(t => ({
        id: t.id,
        acc: t.acc,
        date: t.date,
        payee: t.payee,
        cat: t.cat,
        memo: t.memo || '',
        amt: t.amt,
        rec: t.rec !== false,
        peer: t.peer || null,
        xfer: t.xfer || null
      }))
    };

    const jsonStr = JSON.stringify(payload, null, 2);
    const blob = new Blob([jsonStr], { type: 'application/json' });
    const filename = 'openmoney_inbox.json';
    const file = new File([blob], filename, { type: 'application/json' });

    // Try Web Share API (Single file only, so iOS doesn't generate texto.txt)
    if (navigator.canShare && navigator.canShare({ files: [file] })) {
      try {
        await navigator.share({
          files: [file]
        });
        return { success: true, count: pending.length, method: 'share' };
      } catch (err) {
        if (err.name === 'AbortError') {
          return { success: false, aborted: true };
        }
      }
    }

    // Direct download fallback
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    return { success: true, count: pending.length, method: 'download' };
  }
}

export const coletorStorage = new ColetorStorage();
