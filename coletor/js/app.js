// OpenMoney Coletor - Mobile Application Controller
import { coletorStorage } from './db.js';
import { receiptScanner } from './ocr.js';
import { voiceExpenseEngine } from './voice.js';
import { formatCurrency, parseCurrencyToCents, todayISO, formatDateBR, uid, SEP } from './models.js';

let currentTxType = 'despesa';

// Service Worker Registration
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').then((reg) => {
      reg.update().catch(() => {});
      reg.addEventListener('updatefound', () => {
        const newWorker = reg.installing;
        if (newWorker) {
          newWorker.addEventListener('statechange', () => {
            if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
              showToast('🔄 Coletor atualizado! Recarregando...');
              setTimeout(() => window.location.reload(), 1500);
            }
          });
        }
      });
    }).catch(err => console.warn('SW registration failed:', err));
  });
}

// Toast Notification Helper
function showToast(msg, duration = 3000) {
  const toast = document.getElementById('toast');
  if (!toast) return;
  toast.textContent = msg;
  toast.classList.add('show');
  setTimeout(() => toast.classList.remove('show'), duration);
}

// Modal open/close helpers
function openModal(modal) {
  if (!modal) return;
  document.body.classList.add('modal-open');
  modal.classList.add('active');
}

function closeAllModals() {
  document.body.classList.remove('modal-open');
  document.querySelectorAll('.modal-overlay').forEach(m => m.classList.remove('active'));
  const dropdown = document.getElementById('payeeDropdown');
  if (dropdown) dropdown.classList.remove('show');
  if (voiceExpenseEngine && voiceExpenseEngine.isListening) {
    voiceExpenseEngine.cancelListening();
  }
}

// App Initialization
function initApp() {
  setupEventListeners();
  renderApp();

  const structure = coletorStorage.getStructure();
  if (!structure) {
    openSetupModal();
  }

  // Handle URL query parameters for Apple Shortcuts (?recibo=... or ?ocr_text=...)
  try {
    const urlParams = new URLSearchParams(window.location.search);
    const receiptParam = urlParams.get('recibo') || urlParams.get('ocr_text');
    if (receiptParam) {
      window.history.replaceState({}, document.title, window.location.pathname);
      processReceiptText(receiptParam);
    }
  } catch (e) {
    console.warn('URL param parse error:', e);
  }
}

// Main Render Routine
function renderApp() {
  const structure = coletorStorage.getStructure();
  const pending = coletorStorage.getPendingTransactions();

  // 1. Header Info (File Name on its own row)
  const headerBaseName = document.getElementById('headerBaseName');
  const headerBaseDot = document.getElementById('headerBaseDot');
  if (headerBaseName) {
    headerBaseName.textContent = structure ? structure.baseName : 'Nenhuma base vinculada';
  }
  if (headerBaseDot) {
    if (structure) {
      headerBaseDot.classList.remove('disconnected');
    } else {
      headerBaseDot.classList.add('disconnected');
    }
  }

  // 2. Accounts Overview (Summary Button on Home Screen + Modal Details)
  const accountsSummaryCount = document.getElementById('accountsSummaryCount');
  const modalAccountsContainer = document.getElementById('modalAccountsListContainer');
  const accountsTotalBalance = document.getElementById('accountsTotalBalance');

  if (!structure || !structure.accounts || structure.accounts.length === 0) {
    if (accountsSummaryCount) {
      accountsSummaryCount.textContent = 'Toque para vincular suas contas';
    }
    if (modalAccountsContainer) {
      modalAccountsContainer.innerHTML = `
        <div style="font-size:0.85rem;color:var(--text-muted);padding:24px 16px;text-align:center;">
          Nenhuma base de contas vinculada.<br><br>Toque no ícone ⚙️ acima para importar o <strong>openmoney.json</strong> gerado no seu Mac.
        </div>
      `;
    }
    if (accountsTotalBalance) {
      accountsTotalBalance.textContent = '0,00';
    }
  } else {
    // Calculate pending transactions for each account
    const pendingByAcc = {};
    for (const t of pending) {
      if (t.rec !== false) {
        pendingByAcc[t.acc] = (pendingByAcc[t.acc] || 0) + t.amt;
      }
    }

    const activeAccs = structure.accounts.filter(a => !a.inactive);
    let totalConsolidated = 0;
    let modalHtml = '';

    for (const a of activeAccs) {
      const liveBalance = a.balance + (pendingByAcc[a.id] || 0);
      const isNeg = liveBalance < 0;
      totalConsolidated += liveBalance;

      modalHtml += `
        <div class="account-row-card" data-acc-id="${a.id}">
          <div class="account-row-info">
            <div class="account-row-name">${a.favorite ? '★ ' : ''}${a.name}</div>
            <div class="account-row-type">${a.type || 'Conta'}</div>
          </div>
          <div class="account-row-balance ${isNeg ? 'text-negative' : 'text-positive'}">
            ${formatCurrency(liveBalance, false, false)}
          </div>
        </div>
      `;
    }

    if (accountsSummaryCount) {
      accountsSummaryCount.textContent = `${activeAccs.length} contas cadastradas · Toque para ver saldos`;
    }

    if (accountsTotalBalance) {
      accountsTotalBalance.textContent = formatCurrency(totalConsolidated, false, false);
      accountsTotalBalance.className = `total-amount ${totalConsolidated < 0 ? 'text-negative' : ''}`;
    }

    if (modalAccountsContainer) {
      modalAccountsContainer.innerHTML = modalHtml;

      // Allow tapping an account card to start a transaction in that account
      modalAccountsContainer.querySelectorAll('.account-row-card').forEach(card => {
        card.addEventListener('click', () => {
          const accId = card.getAttribute('data-acc-id');
          closeAllModals();
          openTransactionForm({ accId });
        });
      });
    }
  }

  // 3. Pending Transactions Queue
  const pendingContainer = document.getElementById('pendingListContainer');
  const badgePendingCount = document.getElementById('badgePendingCount');
  const exportCard = document.getElementById('exportCardContainer');

  if (badgePendingCount) {
    badgePendingCount.textContent = pending.length;
  }

  if (pendingContainer) {
    if (pending.length === 0) {
      pendingContainer.innerHTML = `
        <div style="background:var(--bg-card);border:1px solid var(--border-glass);border-radius:var(--radius-md);padding:24px 16px;text-align:center;color:var(--text-muted);font-size:0.88rem;">
          <div style="font-size:1.8rem;margin-bottom:8px;">📥</div>
          Nenhum lançamento pendente na fila.<br>
          Use <strong>Escanear</strong> ou <strong>Novo Lançamento</strong> para registrar compras na rua.
        </div>
      `;
      if (exportCard) exportCard.style.display = 'none';
    } else {
      let html = '';
      for (const t of pending) {
        const isNeg = t.amt < 0;
        const acc = structure?.accounts?.find(a => a.id === t.acc);

        html += `
          <div class="pending-card">
            <div class="pending-info">
              <div style="font-size:1.4rem;">🧾</div>
              <div class="pending-details">
                <div class="name">${t.payee}</div>
                <div class="sub">${formatDateBR(t.date)} · ${acc?.name || 'Conta'} · ${t.cat || 'Geral'}</div>
              </div>
            </div>
            <div class="pending-balances">
              <div class="pending-amount ${isNeg ? 'text-negative' : 'text-positive'}">
                ${formatCurrency(t.amt)}
              </div>
              <button class="btn-delete-pending" data-id="${t.id}" title="Excluir da fila">&times;</button>
            </div>
          </div>
        `;
      }

      pendingContainer.innerHTML = html;

      // Attach delete click
      pendingContainer.querySelectorAll('.btn-delete-pending').forEach(btn => {
        btn.addEventListener('click', (e) => {
          e.stopPropagation();
          const id = btn.getAttribute('data-id');
          if (confirm('Remover este lançamento da fila de envio?')) {
            coletorStorage.deletePendingTransaction(id);
            renderApp();
            showToast('Lançamento removido.');
          }
        });
      });

      if (exportCard) {
        exportCard.style.display = 'block';
      }
    }
  }
}

// Open Setup Modal
function openSetupModal() {
  const structure = coletorStorage.getStructure();
  const infoEl = document.getElementById('setupCurrentBaseInfo');
  if (infoEl) {
    if (structure) {
      infoEl.innerHTML = `
        <strong>${structure.baseName}</strong> (${structure.accounts?.length || 0} contas, ${structure.cats?.length || 0} categorias)<br>
        <span style="font-size:0.72rem;">Última leitura: ${new Date(structure.updatedAt).toLocaleString('pt-BR')}</span>
      `;
    } else {
      infoEl.textContent = 'Nenhuma base vinculada ainda.';
    }
  }
  openModal(document.getElementById('modalSetup'));
}

// Transaction Type Switcher (Despesa / Receita)
function setTransactionType(type) {
  currentTxType = type;
  const btnExpense = document.getElementById('btnTypeExpense');
  const btnIncome = document.getElementById('btnTypeIncome');
  const amtInput = document.getElementById('formAmount');

  if (btnExpense && btnIncome) {
    btnExpense.className = `segmented-btn ${type === 'despesa' ? 'active despesa' : ''}`;
    btnIncome.className = `segmented-btn ${type === 'receita' ? 'active receita' : ''}`;
  }

  if (amtInput) {
    amtInput.style.color = (type === 'despesa' ? 'var(--om-red)' : 'var(--om-green)');
  }

  // Update categories matching the type
  const catSelect = document.getElementById('formCategory');
  const curVal = catSelect ? catSelect.value : '';
  renderCategoryOptions(curVal, type);
}

// Render Category Options (INCLUDES PARENT/PRINCIPAL CATEGORY!)
function renderCategoryOptions(selectedCat = '', type = null) {
  const catSelect = document.getElementById('formCategory');
  if (!catSelect) return;

  const structure = coletorStorage.getStructure();
  if (!structure || !Array.isArray(structure.cats)) {
    catSelect.innerHTML = '<option value="">(Sem categoria)</option>';
    return;
  }

  const catTargetType = type === 'receita' ? 'Receita' : (type === 'despesa' ? 'Despesa' : null);
  let cats = structure.cats;
  if (catTargetType) {
    cats = cats.filter(c => !c.type || c.type === catTargetType);
  }

  let catOpts = '<option value="">(Sem categoria)</option>';
  const parents = cats
    .filter(c => !c.parent || c.parent.trim() === '')
    .sort((a, b) => a.name.localeCompare(b.name, 'pt-BR'));

  for (const p of parents) {
    const subs = cats
      .filter(c => c.parent === p.name)
      .sort((a, b) => a.name.localeCompare(b.name, 'pt-BR'));

    if (subs.length === 0) {
      catOpts += `<option value="${p.name}">${p.name}</option>`;
    } else {
      // Always allow selecting the parent category itself!
      catOpts += `<option value="${p.name}" style="font-weight:700;">📁 ${p.name} (Principal)</option>`;
      for (const s of subs) {
        const full = `${p.name}${SEP}${s.name}`;
        catOpts += `<option value="${full}">&nbsp;&nbsp;&nbsp;↳ ${s.name}</option>`;
      }
    }
  }

  catSelect.innerHTML = catOpts;
  if (selectedCat) {
    catSelect.value = selectedCat;
  }
}

// Apply selected Payee from Autocomplete
function applyPayeeSelection(payeeName, catName, isExpense) {
  const payeeInput = document.getElementById('formPayee');
  const catSelect = document.getElementById('formCategory');
  const dropdown = document.getElementById('payeeDropdown');

  if (payeeInput) payeeInput.value = payeeName;
  if (isExpense !== undefined && isExpense !== null) {
    setTransactionType(isExpense ? 'despesa' : 'receita');
  }
  if (catName && catSelect) {
    catSelect.value = catName;
  }
  if (dropdown) dropdown.classList.remove('show');
}

// Open Form Modal (New or Scan)
function openTransactionForm(preset = null) {
  const structure = coletorStorage.getStructure();
  if (!structure) {
    openSetupModal();
    return;
  }

  const modal = document.getElementById('modalTxForm');
  const title = document.getElementById('txModalTitle');
  const txIdInput = document.getElementById('formTxId');
  const previewWrap = document.getElementById('receiptPreviewWrap');
  const previewImg = document.getElementById('receiptPreviewImg');

  const amtInput = document.getElementById('formAmount');
  const payeeInput = document.getElementById('formPayee');
  const accSelect = document.getElementById('formAccount');
  const dateInput = document.getElementById('formDate');
  const memoInput = document.getElementById('formMemo');
  const dropdown = document.getElementById('payeeDropdown');

  if (dropdown) dropdown.classList.remove('show');

  // Fill accounts dropdown
  let accOpts = '';
  for (const a of structure.accounts.filter(acc => !acc.inactive)) {
    accOpts += `<option value="${a.id}">${a.name} (${a.type})</option>`;
  }
  accSelect.innerHTML = accOpts;

  if (preset) {
    if (preset.isScan) {
      title.textContent = 'Confirmar Dados do Recibo';
    } else if (preset.isVoice) {
      title.textContent = 'Confirmar Lançamento por Voz';
    } else {
      title.textContent = 'Novo Lançamento';
    }
    txIdInput.value = preset.id || '';

    if (preset.thumbnail) {
      previewImg.src = preset.thumbnail;
      previewWrap.style.display = 'flex';
    } else {
      previewWrap.style.display = 'none';
    }

    if (preset.amt) {
      const absCents = Math.abs(preset.amt);
      const reals = Math.floor(absCents / 100);
      const cents = absCents % 100;
      amtInput.value = `${reals.toLocaleString('pt-BR')},${cents.toString().padStart(2, '0')}`;
    } else {
      amtInput.value = '';
    }

    payeeInput.value = preset.payee || '';
    dateInput.value = preset.date || todayISO();
    memoInput.value = preset.memo || '';

    // Set account if passed
    if (preset.accId && accSelect) {
      accSelect.value = preset.accId;
    }

    // Set initial type
    const initialType = preset.isExpense === false ? 'receita' : 'despesa';
    setTransactionType(initialType);

    // If category explicitly passed (e.g. from voice parser)
    if (preset.cat) {
      const catSelect = document.getElementById('formCategory');
      if (catSelect) catSelect.value = preset.cat;
    } else if (preset.payee && structure.frequentPayees) {
      // Auto-match category based on payee
      const norm = preset.payee.toLowerCase().trim();
      const match = structure.frequentPayees.find(p => p.payee.toLowerCase().trim() === norm) ||
                    structure.frequentPayees.find(p => p.payee.toLowerCase().includes(norm));
      if (match) {
        if (match.isExpense !== undefined) {
          setTransactionType(match.isExpense ? 'despesa' : 'receita');
        }
        if (match.cat) {
          const catSelect = document.getElementById('formCategory');
          if (catSelect) catSelect.value = match.cat;
        }
      }
    }
  } else {
    title.textContent = 'Novo Lançamento';
    txIdInput.value = '';
    previewWrap.style.display = 'none';

    amtInput.value = '';
    payeeInput.value = '';
    dateInput.value = todayISO();
    memoInput.value = '';

    setTransactionType('despesa');
  }

  openModal(modal);
  setTimeout(() => amtInput.focus(), 300);
}

// Open Scan Receipt Modal (Apple Live Text & Options)
function openScanReceiptModal() {
  const structure = coletorStorage.getStructure();
  if (!structure) {
    openSetupModal();
    return;
  }
  const modal = document.getElementById('modalScanReceipt');
  const input = document.getElementById('scanReceiptTextInput');
  if (input) input.value = '';
  openModal(modal);
}

// Process Receipt Text (from Apple Live Text, Clipboard, or Apple Shortcut URL)
function processReceiptText(rawText) {
  if (!rawText || !rawText.trim()) return;
  const structure = coletorStorage.getStructure();
  const parsed = receiptScanner.parseReceiptText(rawText, structure);

  closeAllModals();

  openTransactionForm({
    isScan: true,
    payee: parsed.payee,
    amt: parsed.amt,
    date: parsed.date,
    accId: parsed.accId,
    cat: parsed.cat,
    isExpense: true,
    memo: `OCR: "${(parsed.payee || '').slice(0, 30)}"`
  });

  showToast('✓ Comprovante reconhecido com sucesso!');
}

// Handle Camera / Receipt Image Selection (Tesseract Fallback)
async function handleReceiptImageSelected(e) {
  const file = e.target.files[0];
  if (!file) return;

  const structure = coletorStorage.getStructure();
  const loadingModal = document.getElementById('modalOcrLoading');
  const statusEl = document.getElementById('ocrProgressStatus');

  closeAllModals();
  openModal(loadingModal);

  try {
    const parsed = await receiptScanner.scanReceipt(file, (msg) => {
      if (statusEl) statusEl.textContent = msg;
    }, structure);

    closeAllModals();

    openTransactionForm({
      isScan: true,
      payee: parsed.payee,
      amt: parsed.amt,
      date: parsed.date,
      accId: parsed.accId,
      cat: parsed.cat,
      thumbnail: parsed.thumbnail,
      isExpense: true,
      memo: 'Comprovante escaneado via OCR'
    });

    showToast('✓ Comprovante reconhecido com sucesso!');
  } catch (err) {
    closeAllModals();
    alert(`Não foi possível ler o comprovante: ${err.message}`);
  } finally {
    e.target.value = ''; // reset input
  }
}

// Handle Voice Expense Flow
function startVoiceExpenseFlow() {
  const structure = coletorStorage.getStructure();
  if (!structure) {
    openSetupModal();
    return;
  }

  if (!voiceExpenseEngine.isSupported()) {
    alert('O reconhecimento de voz pelo navegador não está ativo. Dica: você pode abrir a tela de "Novo Lançamento", tocar no campo e usar a tecla de microfone do teclado do seu iPhone para ditar diretamente!');
    return;
  }

  const modal = document.getElementById('modalVoiceListening');
  const preview = document.getElementById('voiceTranscriptPreview');
  if (preview) {
    preview.value = '';
    preview.placeholder = 'Ouvindo... pode falar (ou toque para ditar)';
    preview.oninput = () => {
      voiceExpenseEngine.setTranscript(preview.value);
    };
  }

  openModal(modal);

  voiceExpenseEngine.startListening({
    onStart: () => {
      if (preview && !preview.value) {
        preview.placeholder = 'Ouvindo... pode falar agora';
      }
    },
    onTranscript: (interimText) => {
      if (preview) {
        preview.value = interimText;
      }
    },
    onFinal: (finalText) => {
      try {
        closeAllModals();
        const parsed = voiceExpenseEngine.parseVoiceExpense(finalText, structure);
        openTransactionForm({
          isVoice: true,
          payee: parsed.payee,
          amt: parsed.amt,
          date: parsed.date,
          accId: parsed.accId,
          cat: parsed.cat,
          isExpense: parsed.isExpense,
          memo: parsed.memo
        });
        showToast('✓ Áudio interpretado com sucesso!');
      } catch (err) {
        console.error('Erro ao interpretar voz:', err);
        closeAllModals();
        openTransactionForm({
          isVoice: true,
          payee: finalText || 'Lançamento por Voz',
          amt: 0,
          date: todayISO(),
          isExpense: true,
          memo: `Voz: "${finalText}"`
        });
        showToast('⚠️ Preencha os campos da despesa.');
      }
    },
    onEmpty: () => {
      closeAllModals();
      showToast('Nenhuma fala capturada. Toque no microfone e tente novamente.', 3500);
    },
    onError: (err) => {
      closeAllModals();
      const msg = err?.message || 'Reconhecimento de voz finalizado.';
      showToast(`⚠️ ${msg}`, 4000);
    }
  });
}

// Handle OpenMoney Structure JSON file selection
async function handleStructureFileSelected(e) {
  const file = e.target.files[0];
  if (!file) return;

  try {
    const text = await file.text();
    const fullDb = JSON.parse(text);
    coletorStorage.importFromFullDB(fullDb, file.name);

    closeAllModals();
    renderApp();
    showToast(`✓ Base ${file.name} vinculada com sucesso!`);
  } catch (err) {
    alert(`Erro ao ler base: ${err.message}`);
  } finally {
    e.target.value = '';
  }
}

// Save Transaction into Pending Queue
function submitTransactionForm() {
  const amtRaw = document.getElementById('formAmount').value;
  const cents = parseCurrencyToCents(amtRaw);
  if (cents <= 0) {
    alert('Informe um valor monetário válido maior que zero.');
    return;
  }

  const payee = document.getElementById('formPayee').value.trim();
  if (!payee) {
    alert('Informe o nome do estabelecimento ou favorecido.');
    return;
  }

  const accId = document.getElementById('formAccount').value;
  const cat = document.getElementById('formCategory').value;
  const date = document.getElementById('formDate').value || todayISO();
  const memo = document.getElementById('formMemo').value.trim();

  const signedAmt = currentTxType === 'despesa' ? -cents : cents;

  const newTx = {
    id: uid(),
    acc: accId,
    date: date,
    payee: payee,
    cat: cat,
    memo: memo,
    amt: signedAmt,
    rec: date <= todayISO(),
    createdAt: new Date().toISOString()
  };

  coletorStorage.addPendingTransaction(newTx);

  closeAllModals();
  renderApp();
  showToast('✓ Lançamento adicionado à fila para o Mac!');
}

// Export Pending Queue to Mac (openmoney_inbox.json)
async function exportPendingToMac() {
  try {
    const res = await coletorStorage.exportPendingToMac();
    if (res.success) {
      setTimeout(() => {
        if (confirm(`Arquivo openmoney_inbox.json gerado (${res.count} lançamentos)!\n\nDeseja limpar a fila de novos lançamentos agora?`)) {
          coletorStorage.clearPendingTransactions();
          renderApp();
          showToast('✓ Fila de envio limpa com sucesso!');
        }
      }, 600);
    }
  } catch (err) {
    alert(`Erro ao exportar: ${err.message}`);
  }
}

// Event Listeners Setup
function setupEventListeners() {
  // Modal overlay tap to close
  document.querySelectorAll('.modal-overlay').forEach(modal => {
    modal.addEventListener('click', (e) => {
      if (e.target === modal) closeAllModals();
    });
    modal.addEventListener('touchmove', (e) => {
      if (e.target === modal) e.preventDefault();
    }, { passive: false });
  });

  document.querySelectorAll('.sheet-close').forEach(btn => {
    btn.addEventListener('click', closeAllModals);
  });

  // Header Setup Buttons (Gear or Base Row)
  const btnHeaderSetup = document.getElementById('btnHeaderSetup');
  if (btnHeaderSetup) {
    btnHeaderSetup.addEventListener('click', openSetupModal);
  }
  const headerBaseRow = document.getElementById('headerBaseRow');
  if (headerBaseRow) {
    headerBaseRow.addEventListener('click', openSetupModal);
  }

  // Open Accounts & Balances Modal
  const btnOpenAccountsModal = document.getElementById('btnOpenAccountsModal');
  if (btnOpenAccountsModal) {
    btnOpenAccountsModal.addEventListener('click', () => {
      const structure = coletorStorage.getStructure();
      if (!structure) {
        openSetupModal();
        return;
      }
      openModal(document.getElementById('modalAccountsList'));
    });
  }

  // Type Switcher Buttons
  const btnTypeExpense = document.getElementById('btnTypeExpense');
  const btnTypeIncome = document.getElementById('btnTypeIncome');
  if (btnTypeExpense) {
    btnTypeExpense.addEventListener('click', () => setTransactionType('despesa'));
  }
  if (btnTypeIncome) {
    btnTypeIncome.addEventListener('click', () => setTransactionType('receita'));
  }

  // Live Autocomplete for Payee Input
  const payeeInput = document.getElementById('formPayee');
  const payeeDropdown = document.getElementById('payeeDropdown');
  if (payeeInput && payeeDropdown) {
    payeeInput.addEventListener('input', () => {
      const q = payeeInput.value.trim();
      if (q.length < 2) {
        payeeDropdown.classList.remove('show');
        return;
      }
      const matches = coletorStorage.searchPayees(q);
      if (matches.length === 0) {
        payeeDropdown.classList.remove('show');
        return;
      }

      let html = '';
      for (const m of matches) {
        html += `
          <div class="autocomplete-item" data-payee="${m.payee}" data-cat="${m.cat || ''}" data-type="${m.isExpense ? 'despesa' : 'receita'}">
            <span class="name">${m.payee}</span>
            <span class="cat-badge">${m.cat || 'Geral'}</span>
          </div>
        `;
      }
      payeeDropdown.innerHTML = html;
      payeeDropdown.classList.add('show');

      payeeDropdown.querySelectorAll('.autocomplete-item').forEach(item => {
        item.addEventListener('click', () => {
          applyPayeeSelection(
            item.getAttribute('data-payee'),
            item.getAttribute('data-cat'),
            item.getAttribute('data-type') === 'despesa'
          );
        });
      });
    });

    // Close autocomplete on click outside
    document.addEventListener('click', (e) => {
      if (!payeeInput.contains(e.target) && !payeeDropdown.contains(e.target)) {
        payeeDropdown.classList.remove('show');
      }
    });
  }

  // Format currency on typing amount
  const amtInput = document.getElementById('formAmount');
  if (amtInput) {
    amtInput.addEventListener('input', (e) => {
      let v = e.target.value.replace(/\D/g, '');
      if (!v) {
        e.target.value = '';
        return;
      }
      const cents = parseInt(v, 10);
      const reals = Math.floor(cents / 100);
      const c = cents % 100;
      e.target.value = `${reals.toLocaleString('pt-BR')},${c.toString().padStart(2, '0')}`;
    });
  }

  // Choose structure file
  const btnChooseStructureFile = document.getElementById('btnChooseStructureFile');
  const fileStructureInput = document.getElementById('fileStructureInput');
  if (btnChooseStructureFile && fileStructureInput) {
    btnChooseStructureFile.addEventListener('click', () => fileStructureInput.click());
    fileStructureInput.addEventListener('change', handleStructureFileSelected);
  }

  // Action: Scan Receipt (Direct camera capture & OCR)
  const btnScanReceipt = document.getElementById('btnScanReceipt');
  const fileCameraInput = document.getElementById('fileCameraInput');
  if (btnScanReceipt && fileCameraInput) {
    btnScanReceipt.addEventListener('click', () => {
      const structure = coletorStorage.getStructure();
      if (!structure) {
        openSetupModal();
        return;
      }
      fileCameraInput.click();
    });
    fileCameraInput.addEventListener('change', handleReceiptImageSelected);
  }

  // Action: Voice Expense Flow
  const btnVoiceTx = document.getElementById('btnVoiceTx');
  if (btnVoiceTx) {
    btnVoiceTx.addEventListener('click', startVoiceExpenseFlow);
  }

  const btnCancelVoice = document.getElementById('btnCancelVoice');
  if (btnCancelVoice) {
    const handleCancel = (e) => {
      if (e) {
        e.preventDefault();
        e.stopPropagation();
      }
      voiceExpenseEngine.cancelListening();
      closeAllModals();
    };
    btnCancelVoice.addEventListener('click', handleCancel);
    btnCancelVoice.addEventListener('touchend', handleCancel);
  }

  const btnStopVoice = document.getElementById('btnStopVoice');
  if (btnStopVoice) {
    const handleStop = (e) => {
      if (e) {
        e.preventDefault();
        e.stopPropagation();
      }
      const preview = document.getElementById('voiceTranscriptPreview');
      const text = preview ? preview.value : '';
      voiceExpenseEngine.stopListening(text);
    };
    btnStopVoice.addEventListener('click', handleStop);
    btnStopVoice.addEventListener('touchend', handleStop);
  }

  // Action: Manual Transaction
  const btnManualTx = document.getElementById('btnManualTx');
  if (btnManualTx) {
    btnManualTx.addEventListener('click', () => openTransactionForm());
  }

  // Save to Queue
  const btnSaveToQueue = document.getElementById('btnSaveToQueue');
  if (btnSaveToQueue) {
    btnSaveToQueue.addEventListener('click', submitTransactionForm);
  }

  // Export to Mac
  const btnExportToMac = document.getElementById('btnExportToMac');
  if (btnExportToMac) {
    btnExportToMac.addEventListener('click', exportPendingToMac);
  }
}

document.addEventListener('DOMContentLoaded', initApp);
