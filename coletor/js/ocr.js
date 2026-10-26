// OpenMoney Coletor - Receipt OCR & Scanner Engine
import { parseCurrencyToCents, todayISO } from './models.js';

class ReceiptScanner {
  constructor() {
    this.tesseractLoaded = false;
  }

  // Dynamically load Tesseract.js only when scanning
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
          // Max dimension for OCR
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

          // Generate base64 thumbnail (max 300px)
          const thumbCanvas = document.createElement('canvas');
          const thumbScale = Math.min(300 / width, 300 / height);
          thumbCanvas.width = Math.round(width * thumbScale);
          thumbCanvas.height = Math.round(height * thumbScale);
          const thumbCtx = thumbCanvas.getContext('2d');
          thumbCtx.drawImage(img, 0, 0, thumbCanvas.width, thumbCanvas.height);
          const thumbDataUrl = thumbCanvas.toDataURL('image/jpeg', 0.6);

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

  // Scan receipt image and extract Payee, Amount and Date
  async scanReceipt(imageFile, onProgress = null) {
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

    const parsed = this.parseReceiptText(fullText);
    parsed.thumbnail = processed.thumbUrl;
    parsed.rawText = fullText;

    return parsed;
  }

  // Parse raw OCR text to detect Payee, Date and Amount
  parseReceiptText(text) {
    const lines = text.split('\n').map(l => l.trim()).filter(Boolean);

    // 1. Extract Amount
    let detectedAmount = 0;
    const amountCandidates = [];

    // Check specific keywords first
    for (const line of lines) {
      const lower = line.toLowerCase();
      if (lower.includes('total') || lower.includes('valor') || lower.includes('pago') || lower.includes('debito') || lower.includes('subtotal')) {
        const matches = line.match(/(?:R\$)?\s*([0-9]{1,4}(?:[.,][0-9]{3})*[.,][0-9]{2})/gi);
        if (matches) {
          for (const m of matches) {
            const cents = parseCurrencyToCents(m);
            if (cents > 0) amountCandidates.push({ cents, priority: 2 });
          }
        }
      } else {
        // Any monetary pattern
        const matches = line.match(/(?:R\$)?\s*([0-9]{1,4}(?:[.,][0-9]{3})*[.,][0-9]{2})/gi);
        if (matches) {
          for (const m of matches) {
            const cents = parseCurrencyToCents(m);
            if (cents > 50 && cents < 5000000) { // filter noise
              amountCandidates.push({ cents, priority: 1 });
            }
          }
        }
      }
    }

    if (amountCandidates.length > 0) {
      // Prefer priority 2 (near total/valor keyword), else max sensible amount
      const highPriority = amountCandidates.filter(c => c.priority === 2);
      if (highPriority.length > 0) {
        detectedAmount = Math.max(...highPriority.map(c => c.cents));
      } else {
        detectedAmount = Math.max(...amountCandidates.map(c => c.cents));
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

        if (dNum >= 1 && dNum <= 31 && mNum >= 1 && mNum <= 12 && yNum >= 2020 && yNum <= 2030) {
          detectedDate = `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
          break;
        }
      }
    }

    // 3. Extract Payee / Store Name
    let detectedPayee = '';
    const ignoreKeywords = ['cupom', 'fiscal', 'danfe', 'nfc-e', 'sat', 'extrato', 'comprovante', 'via', 'cliente', 'cnpj', 'ie:', 'im:', 'endereco', 'rua', 'av.', 'avenida', 'cpf', 'consumidor'];
    
    for (let i = 0; i < Math.min(lines.length, 6); i++) {
      const line = lines[i];
      const lower = line.toLowerCase();
      const hasIgnore = ignoreKeywords.some(k => lower.includes(k));
      const hasNumbersOnly = /^[\d\s\.\-\/]+$/.test(line);

      if (!hasIgnore && !hasNumbersOnly && line.length >= 3 && line.length <= 40) {
        detectedPayee = line.replace(/[^a-zA-Z0-9À-ÿ\s&.-]/g, '').trim();
        break;
      }
    }

    return {
      payee: detectedPayee || 'Comprovante Escaneado',
      amt: detectedAmount,
      date: detectedDate
    };
  }
}

export const receiptScanner = new ReceiptScanner();
