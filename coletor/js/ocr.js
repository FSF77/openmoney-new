// OpenMoney Coletor - Receipt OCR & Scanner Engine (Apple Live Text & Tesseract Fallback)
import { parseCurrencyToCents, todayISO, normalizeStr } from './models.js';

class ReceiptScanner {
  constructor() {
    this.tesseractLoaded = false;
  }

  // Dynamically load Tesseract.js only if user explicitly requests legacy browser scan
  async loadTesseract() {
    if (window.Tesseract) {
      this.tesseractLoaded = true;
      return window.Tesseract;
    }
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js';
      script.onload = () => {
        this.tesseractLoaded = true;
        resolve(window.Tesseract);
      };
      script.onerror = () => reject(new Error('Não foi possível carregar o motor de OCR offline.'));
      document.head.appendChild(script);
    });
  }

  // Resize and compress image for fast local OCR and light thumbnail
  async processImage(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = (e) => {
        const img = new Image();
        img.onload = () => {
          const maxDim = 1600;
          let width = img.width;
          let height = img.height;
          if (width > maxDim || height > maxDim) {
            if (width > height) {
              height = Math.round((height * maxDim) / width);
              width = maxDim;
            } else {
              width = Math.round((width * maxDim) / height);
              height = maxDim;
            }
          }

          const canvas = document.createElement('canvas');
          canvas.width = width;
          canvas.height = height;
          const ctx = canvas.getContext('2d');
          ctx.drawImage(img, 0, 0, width, height);

          // Generate base64 thumbnail from original photo (max 300px)
          const thumbCanvas = document.createElement('canvas');
          const thumbScale = Math.min(300 / width, 300 / height);
          thumbCanvas.width = Math.round(width * thumbScale);
          thumbCanvas.height = Math.round(height * thumbScale);
          const thumbCtx = thumbCanvas.getContext('2d');
          thumbCtx.drawImage(img, 0, 0, thumbCanvas.width, thumbCanvas.height);
          const thumbDataUrl = thumbCanvas.toDataURL('image/jpeg', 0.6);

          // OCR Preprocessing: Grayscale + Dynamic Contrast Boost to make thermal receipts legible
          try {
            const imgData = ctx.getImageData(0, 0, width, height);
            const d = imgData.data;
            const contrast = 36; // boost contrast
            const factor = (259 * (contrast + 255)) / (255 * (259 - contrast));
            for (let i = 0; i < d.length; i += 4) {
              const gray = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
              const adjusted = factor * (gray - 128) + 128;
              const val = adjusted < 0 ? 0 : (adjusted > 255 ? 255 : adjusted);
              d[i] = val;
              d[i + 1] = val;
              d[i + 2] = val;
            }
            ctx.putImageData(imgData, 0, 0);
          } catch (e) {
            console.warn('Canvas pre-processing skipped:', e);
          }

          resolve({
            dataUrl: canvas.toDataURL('image/jpeg', 0.85),
            thumbUrl: thumbDataUrl,
            width,
            height
          });
        };
        img.onerror = () => reject(new Error('Falha ao processar a imagem do comprovante.'));
        img.src = e.target.result;
      };
      reader.onerror = () => reject(new Error('Falha ao ler o arquivo.'));
      reader.readAsDataURL(file);
    });
  }

  // Scan receipt image with Tesseract (fallback)
  async scanReceipt(imageFile, onProgress = null, structure = null) {
    if (onProgress) onProgress('Preparando imagem...');
    const processed = await this.processImage(imageFile);

    if (onProgress) onProgress('Iniciando reconhecimento ótico (OCR)...');
    const Tesseract = await this.loadTesseract();

    const worker = await Tesseract.createWorker('por', 1, {
      logger: m => {
        if (m.status === 'recognizing text' && onProgress) {
          const pct = Math.round((m.progress || 0) * 100);
          onProgress(`Reconhecendo texto... ${pct}%`);
        }
      }
    });

    const ret = await worker.recognize(processed.dataUrl);
    await worker.terminate();

    const fullText = ret.data.text || '';
    if (onProgress) onProgress('Analisando dados do comprovante...');

    const parsed = this.parseReceiptText(fullText, structure);
    parsed.thumbnail = processed.thumbUrl;
    parsed.rawText = fullText;

    return parsed;
  }

  // High-accuracy parsing of receipt text (Live Text Apple or Tesseract)
  parseReceiptText(text, structure = null) {
    if (!text || typeof text !== 'string') {
      return {
        payee: 'Comprovante Escaneado',
        amt: 0,
        date: todayISO(),
        cat: '',
        accId: null
      };
    }

    const raw = text.trim();
    const lines = raw.split('\n').map(l => l.trim()).filter(Boolean);
    const lowerFull = raw.toLowerCase();
    const normFull = normalizeStr(lowerFull);

    // 1. Extract Amount (Cents)
    let detectedAmount = 0;
    const amountCandidates = [];

    for (const line of lines) {
      const lower = line.toLowerCase();
      const isKeywordLine = lower.includes('total') || lower.includes('valor') || lower.includes('pago') || lower.includes('debito') || lower.includes('credito') || lower.includes('subtotal') || lower.includes('pix');

      const matches = line.match(/(?:R\$)?\s*([0-9]{1,4}(?:[.,][0-9]{3})*[.,][0-9]{2})/gi);
      if (matches) {
        for (const m of matches) {
          const cents = parseCurrencyToCents(m);
          if (cents > 0) {
            amountCandidates.push({
              cents,
              priority: isKeywordLine ? 2 : 1
            });
          }
        }
      }
    }

    if (amountCandidates.length > 0) {
      const highPriority = amountCandidates.filter(c => c.priority === 2);
      if (highPriority.length > 0) {
        detectedAmount = Math.max(...highPriority.map(c => c.cents));
      } else {
        const sensible = amountCandidates.filter(c => c.cents >= 50 && c.cents <= 5000000);
        detectedAmount = sensible.length > 0 ? Math.max(...sensible.map(c => c.cents)) : amountCandidates[0].cents;
      }
    }

    // 2. Extract Date (DD/MM/AAAA or DD/MM/AA)
    let detectedDate = todayISO();
    for (const line of lines) {
      const dateMatch = line.match(/(\d{2})[\/\.-](\d{2})[\/\.-](\d{2,4})/);
      if (dateMatch) {
        let day = dateMatch[1];
        let month = dateMatch[2];
        let year = dateMatch[3];
        if (year.length === 2) year = `20${year}`;

        const dNum = parseInt(day, 10);
        const mNum = parseInt(month, 10);
        const yNum = parseInt(year, 10);

        if (dNum >= 1 && dNum <= 31 && mNum >= 1 && mNum <= 12 && yNum >= 2020 && yNum <= 2035) {
          detectedDate = `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
          break;
        }
      }
    }

    // 3. Match Payee & Category from Frequent Payees (Smart Association)
    let matchedPayee = '';
    let matchedCat = '';
    let matchedAccId = null;

    if (structure && Array.isArray(structure.frequentPayees)) {
      const sortedPayees = [...structure.frequentPayees].sort((a, b) => b.payee.length - a.payee.length);
      for (const p of sortedPayees) {
        const normPayee = normalizeStr(p.payee);
        if (normPayee && normFull.includes(normPayee)) {
          matchedPayee = p.payee;
          matchedCat = p.cat || '';
          break;
        }
      }
    }

    // 4. Keyword Category Fallback
    const CATEGORY_KEYWORDS = [
      { words: ['almoco', 'almoço', 'jantar', 'refeicao', 'refeição', 'restaurante', 'mcdonalds', 'burguer', 'burger', 'pizza', 'ifood', 'lanche', 'bar', 'churrascaria'], catContains: ['Restaurante', 'Alimentação'] },
      { words: ['supermercado', 'mercado', 'compras', 'acougue', 'açougue', 'hortifruti', 'atacadista', 'hipermercado'], catContains: ['Supermercado', 'Alimentação'] },
      { words: ['posto', 'gasolina', 'combustivel', 'combustível', 'etanol', 'abastecer', 'auto posto'], catContains: ['Combustível', 'Transporte'] },
      { words: ['farmacia', 'farmácia', 'drogaria', 'remedio', 'remédio', 'medicamento', 'drogasil', 'raia'], catContains: ['Farmácia', 'Saúde'] },
      { words: ['padaria', 'pao', 'pão', 'cafe', 'café', 'confeitaria'], catContains: ['Padaria', 'Alimentação'] },
      { words: ['uber', 'taxi', 'táxi', 'corrida', 'estacionamento', 'pedagio', 'pedágio'], catContains: ['Transporte'] },
      { words: ['cinema', 'filme', 'teatro', 'show', 'ingresso', 'lazer'], catContains: ['Lazer'] }
    ];

    if (!matchedCat && structure && Array.isArray(structure.cats)) {
      for (const rule of CATEGORY_KEYWORDS) {
        const hasWord = rule.words.some(w => normFull.includes(normalizeStr(w)));
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

    // 5. Account Detection (Card, Cash or Bank Name)
    if (structure && Array.isArray(structure.accounts)) {
      const activeAccs = structure.accounts.filter(a => !a.inactive);

      // Check account names mentioned in receipt
      for (const acc of activeAccs) {
        const normAccName = normalizeStr(acc.name);
        if (normAccName && normFull.includes(normAccName)) {
          matchedAccId = acc.id;
          break;
        }
      }

      if (!matchedAccId) {
        if (normFull.includes('dinheiro') || normFull.includes('especie')) {
          const cashAcc = activeAccs.find(a => a.type === 'Dinheiro');
          if (cashAcc) matchedAccId = cashAcc.id;
        } else if (normFull.includes('cartao') || normFull.includes('cartão') || normFull.includes('credito') || normFull.includes('crédito') || normFull.includes('debito') || normFull.includes('débito')) {
          const cardAcc = activeAccs.find(a => a.type === 'Cartão de crédito');
          if (cardAcc) matchedAccId = cardAcc.id;
        }
      }

      if (!matchedAccId) {
        const fav = activeAccs.find(a => a.favorite);
        matchedAccId = fav ? fav.id : (activeAccs[0]?.id || null);
      }
    }

    // 6. Payee Fallback (Clean first meaningful header line)
    if (!matchedPayee) {
      const ignoreKeywords = [
        'cupom', 'fiscal', 'danfe', 'nfc-e', 'sat', 'extrato', 'comprovante', 'via', 'cliente',
        'cnpj', 'ie:', 'im:', 'endereco', 'rua', 'av.', 'avenida', 'cpf', 'consumidor', 'data', 'hora',
        'caixa', 'operador', 'numero', 'nº', 'terminal', 'aut', 'autorizacao', 'doc'
      ];

      for (let i = 0; i < Math.min(lines.length, 8); i++) {
        const line = lines[i];
        const lower = line.toLowerCase();
        const hasIgnore = ignoreKeywords.some(k => lower.includes(k));
        const hasNumbersOnly = /^[\d\s\.\-\/:]+$/.test(line);

        if (!hasIgnore && !hasNumbersOnly && line.length >= 3 && line.length <= 45) {
          matchedPayee = line.replace(/[^a-zA-Z0-9À-ÿ\s&.-]/g, '').trim();
          break;
        }
      }
    }

    return {
      payee: matchedPayee || 'Comprovante Escaneado',
      amt: detectedAmount,
      date: detectedDate,
      cat: matchedCat,
      accId: matchedAccId,
      rawText: raw
    };
  }
}

export const receiptScanner = new ReceiptScanner();
