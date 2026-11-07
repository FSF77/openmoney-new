// OpenMoney Coletor - Voice Recognition & Local NLP Parser Engine
import { normalizeStr, todayISO, parseCurrencyToCents } from './models.js';

export class VoiceExpenseEngine {
  constructor() {
    this.recognition = null;
    this.isListening = false;
    this.hasFinished = false;
    this.currentTranscript = '';
    this.callbacks = null;
  }

  // Check if browser supports Web Speech API
  isSupported() {
    return 'webkitSpeechRecognition' in window || 'SpeechRecognition' in window;
  }

  // Set transcript manually (e.g. from textarea input / iOS keyboard dictation)
  setTranscript(text) {
    this.currentTranscript = (text || '').trim();
  }

  // Release previous recognition safely
  async cleanup() {
    if (this.recognition) {
      try {
        this.recognition.onstart = null;
        this.recognition.onresult = null;
        this.recognition.onerror = null;
        this.recognition.onend = null;
        this.recognition.stop();
      } catch (e) {}
      this.recognition = null;
    }
    this.isListening = false;
  }

  // Start Voice Recognition
  async startListening({ onTranscript, onFinal, onError, onStart, onEnd, onEmpty }) {
    await this.cleanup();

    if (!this.isSupported()) {
      if (onError) onError(new Error('Reconhecimento de voz não suportado neste navegador.'));
      return;
    }

    this.callbacks = { onTranscript, onFinal, onError, onStart, onEnd, onEmpty };
    this.hasFinished = false;
    this.currentTranscript = '';

    // Workaround for Safari iOS Audio Session lock:
    // Briefly acquire and release audio stream to reset the audio hardware pipeline
    if (navigator.mediaDevices && typeof navigator.mediaDevices.getUserMedia === 'function') {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        stream.getTracks().forEach(track => track.stop());
      } catch (e) {
        // If user already granted or if restricted, continue
      }
    }

    const SpeechClass = window.SpeechRecognition || window.webkitSpeechRecognition;

    try {
      this.recognition = new SpeechClass();
    } catch (e) {
      if (onError) onError(new Error('Não foi possível iniciar o microfone no navegador.'));
      return;
    }

    this.recognition.lang = 'pt-BR';
    // CRITICAL: continuous MUST be false on iOS Safari to prevent audio pipeline deadlocks
    this.recognition.continuous = false;
    this.recognition.interimResults = true;
    this.recognition.maxAlternatives = 1;

    let finalSpokenText = '';

    this.recognition.onstart = () => {
      this.isListening = true;
      if (this.callbacks?.onStart) this.callbacks.onStart();
    };

    this.recognition.onresult = (event) => {
      let interimStr = '';
      for (let i = 0; i < event.results.length; i++) {
        const item = event.results[i];
        if (item && item[0]) {
          const text = item[0].transcript || '';
          if (item.isFinal) {
            finalSpokenText += text + ' ';
          } else {
            interimStr += text;
          }
        }
      }

      const combined = (finalSpokenText + interimStr).trim().replace(/\s+/g, ' ');
      if (combined) {
        this.currentTranscript = combined;
        if (this.callbacks?.onTranscript) {
          this.callbacks.onTranscript(combined);
        }
      }
    };

    this.recognition.onerror = (event) => {
      const err = event.error || '';
      console.warn('SpeechRecognition onerror:', err);

      if (err === 'aborted') {
        return;
      }

      // If we already have captured text, finish with success
      if (this.currentTranscript && this.currentTranscript.trim()) {
        this.commitSpeech();
        return;
      }

      if (err === 'no-speech') {
        // Just let it close or stay ready for keyboard input
        return;
      }

      if (err === 'not-allowed') {
        if (this.callbacks?.onError) {
          this.callbacks.onError(new Error('Permissão negada. Verifique os Ajustes do iPhone > Safari > Microfone.'));
        }
        return;
      }

      if (this.callbacks?.onError) {
        this.callbacks.onError(new Error(`Reconhecimento finalizado (${err || 'áudio ocupado'}).`));
      }
    };

    this.recognition.onend = () => {
      this.isListening = false;
      const finished = this.hasFinished;

      if (!finished && this.currentTranscript && this.currentTranscript.trim()) {
        // Natural end of speech detected by iOS
        this.commitSpeech();
      }
    };

    try {
      this.recognition.start();
    } catch (err) {
      console.warn('Initial recognition.start() failed:', err);
      // Give iOS 250ms breathing room and retry once
      setTimeout(() => {
        if (!this.hasFinished && this.recognition) {
          try {
            this.recognition.start();
          } catch (retryErr) {
            if (this.callbacks?.onError) {
              this.callbacks.onError(new Error('Microfone reiniciando. Aguarde 1 segundo e tente novamente.'));
            }
          }
        }
      }, 250);
    }
  }

  // Commit what was captured and trigger completion
  commitSpeech(fallbackText = '') {
    if (this.hasFinished) return;
    this.hasFinished = true;

    const text = (this.currentTranscript || fallbackText || '').trim();
    const onFinal = this.callbacks?.onFinal;

    if (this.recognition) {
      try {
        this.recognition.stop();
      } catch (e) {}
    }
    this.isListening = false;

    if (text && onFinal) {
      onFinal(text);
    }
  }

  // Stop listening manually (called when user clicks Concluir Fala)
  stopListening(fallbackText = '') {
    const text = (this.currentTranscript || fallbackText || '').trim();
    if (text) {
      this.commitSpeech(text);
    } else {
      this.cancelListening();
      if (this.callbacks?.onEmpty) {
        this.callbacks.onEmpty();
      }
    }
  }

  // Cancel flow (called when user clicks Cancelar)
  cancelListening() {
    this.hasFinished = true;
    if (this.recognition) {
      try {
        this.recognition.abort();
      } catch (e) {}
    }
    this.isListening = false;
  }

  // Parse natural language spoken phrase into OpenMoney fields
  parseVoiceExpense(spokenText, structure) {
    if (!spokenText || typeof spokenText !== 'string') {
      return {
        amt: 0,
        payee: '',
        cat: '',
        accId: null,
        date: todayISO(),
        isExpense: true,
        memo: ''
      };
    }

    try {
      const raw = spokenText.trim();
      const lower = raw.toLowerCase();
      const norm = normalizeStr(lower);

      // 1. Detect Type (Receita vs Despesa)
      const incomeWords = ['recebi', 'recebido', 'salario', 'salário', 'reembolso', 'rendimento', 'venda', 'deposito', 'depósito', 'pix recebido', 'estorno'];
      const isExpense = !incomeWords.some(w => norm.includes(normalizeStr(w)));

      // 2. Detect Date
      let date = todayISO();
      if (norm.includes('anteontem')) {
        const d = new Date();
        d.setDate(d.getDate() - 2);
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        date = `${y}-${m}-${day}`;
      } else if (norm.includes('ontem')) {
        const d = new Date();
        d.setDate(d.getDate() - 1);
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        date = `${y}-${m}-${day}`;
      }

      // 3. Detect Amount (Cents)
      let cents = 0;
      // Try currency format: "R$ 45,90", "45,50", "45.50", "45 reais e 50 centavos", "45 e 50"
      const regexCurrency = /(?:r\$\s*)?(\d{1,5})(?:[.,](\d{1,2}))?\s*(?:reais|real)?(?:\s*e\s*(\d{1,2})\s*(?:centavos)?)?/i;
      const matchCurr = lower.match(regexCurrency);

      if (matchCurr) {
        const reals = parseInt(matchCurr[1], 10) || 0;
        let centPart = 0;
        if (matchCurr[2]) {
          centPart = parseInt(matchCurr[2].padEnd(2, '0').slice(0, 2), 10);
        } else if (matchCurr[3]) {
          centPart = parseInt(matchCurr[3].padEnd(2, '0').slice(0, 2), 10);
        }
        cents = (reals * 100) + centPart;
      }

      // Fallback: search for stand-alone numbers e.g. "almoço 45", "gasolina 100"
      if (cents === 0) {
        const numberMatch = lower.match(/\b(\d{1,6}(?:[.,]\d{2})?)\b/);
        if (numberMatch) {
          cents = parseCurrencyToCents(numberMatch[1]);
        }
      }

      // 4. Detect Account
      let matchedAccId = null;
      if (structure && Array.isArray(structure.accounts)) {
        const activeAccs = structure.accounts.filter(a => !a.inactive);

        // Check account names in spoken text
        for (const acc of activeAccs) {
          const normAccName = normalizeStr(acc.name);
          if (normAccName && norm.includes(normAccName)) {
            matchedAccId = acc.id;
            break;
          }
        }

        // Check generic keywords if still not matched
        if (!matchedAccId) {
          if (norm.includes('dinheiro') || norm.includes('carteira') || norm.includes('especie')) {
            const cashAcc = activeAccs.find(a => a.type === 'Dinheiro');
            if (cashAcc) matchedAccId = cashAcc.id;
          } else if (norm.includes('cartao') || norm.includes('cartão') || norm.includes('credito') || norm.includes('crédito')) {
            const cardAcc = activeAccs.find(a => a.type === 'Cartão de crédito');
            if (cardAcc) matchedAccId = cardAcc.id;
          } else if (norm.includes('poupanca') || norm.includes('poupança')) {
            const savAcc = activeAccs.find(a => a.type === 'Poupança');
            if (savAcc) matchedAccId = savAcc.id;
          }
        }

        // Default account: favorite account or first active
        if (!matchedAccId) {
          const fav = activeAccs.find(a => a.favorite);
          matchedAccId = fav ? fav.id : (activeAccs[0]?.id || null);
        }
      }

      // 5. Detect Favorecido and Category from Frequent Payees & Context
      let matchedPayee = '';
      let matchedCat = '';

      if (structure && Array.isArray(structure.frequentPayees)) {
        const sortedPayees = [...structure.frequentPayees].sort((a, b) => b.payee.length - a.payee.length);
        for (const p of sortedPayees) {
          const normPayee = normalizeStr(p.payee);
          if (normPayee && norm.includes(normPayee)) {
            matchedPayee = p.payee;
            matchedCat = p.cat || '';
            break;
          }
        }
      }

      // Keyword Category Fallback Mapping
      const CATEGORY_KEYWORDS = [
        { words: ['almoco', 'almoço', 'jantar', 'refeicao', 'refeição', 'restaurante', 'mcdonalds', 'burguer', 'burger', 'pizza', 'ifood', 'lanche'], catContains: ['Restaurante', 'Alimentação'] },
        { words: ['supermercado', 'mercado', 'compras', 'acougue', 'açougue', 'hortifruti'], catContains: ['Supermercado', 'Alimentação'] },
        { words: ['posto', 'gasolina', 'combustivel', 'combustível', 'etanol', 'abastecer', 'abasteci'], catContains: ['Combustível', 'Transporte'] },
        { words: ['farmacia', 'farmácia', 'drogaria', 'remedio', 'remédio', 'medicamento'], catContains: ['Farmácia', 'Saúde'] },
        { words: ['padaria', 'pao', 'pão', 'cafe', 'café'], catContains: ['Padaria', 'Alimentação'] },
        { words: ['uber', 'taxi', 'táxi', 'corrida', 'estacionamento', 'pedagio', 'pedágio'], catContains: ['Transporte'] },
        { words: ['cinema', 'filme', 'teatro', 'show', 'ingresso', 'lazer'], catContains: ['Lazer'] },
        { words: ['salario', 'salário', 'pagamento', 'pro-labore'], catContains: ['Salário', 'Receita'] }
      ];

      if (!matchedCat && structure && Array.isArray(structure.cats)) {
        for (const rule of CATEGORY_KEYWORDS) {
          const hasWord = rule.words.some(w => norm.includes(normalizeStr(w)));
          if (hasWord) {
            const found = structure.cats.find(c => {
              const p = normalizeStr(c.path || c.name || '');
              return rule.catContains.some(kw => p.includes(normalizeStr(kw)));
            });
            if (found) {
              matchedCat = found.path || found.name;
              break;
            }
          }
        }
      }

      // 6. Extract Payee Name from clean remaining text if not matched to frequent payee
      if (!matchedPayee) {
        let cleanWords = lower
          .replace(/r\$\s*[\d,.]+/g, '')
          .replace(/\b\d+([.,]\d+)?\b/g, '')
          .replace(/\b(reais|real|centavos|paguei|gastei|comprei|recebi|no|na|nos|nas|de|do|da|dos|das|com|em|para|por|hoje|ontem|anteontem|cartao|cartão|dinheiro|debito|débito|credito|crédito|conta)\b/gi, ' ')
          .replace(/\s+/g, ' ')
          .trim();

        // Safe removal of account names without regex crash on special characters like () or /
        if (structure && Array.isArray(structure.accounts)) {
          for (const acc of structure.accounts) {
            if (!acc || !acc.name) continue;
            const accLower = acc.name.toLowerCase().trim();
            if (accLower && cleanWords.includes(accLower)) {
              cleanWords = cleanWords.split(accLower).join(' ').trim();
            }
          }
        }

        if (cleanWords.length >= 2) {
          matchedPayee = cleanWords
            .split(' ')
            .filter(Boolean)
            .map(w => w.charAt(0).toUpperCase() + w.slice(1))
            .join(' ');
        }
      }

      return {
        rawText: raw,
        amt: cents,
        payee: matchedPayee || 'Lançamento por Voz',
        cat: matchedCat,
        accId: matchedAccId,
        date: date,
        isExpense: isExpense,
        memo: `Voz: "${raw}"`
      };
    } catch (parseErr) {
      console.warn('parseVoiceExpense error, falling back:', parseErr);
      return {
        rawText: spokenText,
        amt: 0,
        payee: 'Lançamento por Voz',
        cat: '',
        accId: null,
        date: todayISO(),
        isExpense: true,
        memo: `Voz: "${spokenText}"`
      };
    }
  }
}

export const voiceExpenseEngine = new VoiceExpenseEngine();
