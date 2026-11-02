// OpenMoney Coletor - Gemini Multimodal AI Service (ADR 007 - BYOK)

const CANDIDATE_MODELS = [
  'gemini-3.8-flash',
  'gemini-3.5-flash',
  'gemini-3.5-flash-lite',
  'gemini-2.5-flash',
  'gemini-2.0-flash',
  'gemini-1.5-flash',
  'gemini-flash-latest'
];

const SYSTEM_PROMPT = `Você é um especialista contábil em leitura de comprovantes fiscais e recibos bancários brasileiros (cupons fiscais NFC-e, extratos, comprovantes de máquina POS e Pix).
Analise a imagem do comprovante e extraia rigorosamente um JSON com as chaves:
1. "date": A data da transação/emissão no formato "AAAA-MM-DD" (ex: "2026-10-24" ou "2024-02-12").
2. "payee": O nome do estabelecimento comercial, loja, restaurante ou pessoa favorecida (ex: "LEROY MERLIN", "PERFUMARIA ORQUIDEA", "RESTAURANTE BARDOURO", "COMERCIAL ESPERANCA").
   REGRAS OBRIGATÓRIAS PARA O NOME:
   - NUNCA use o nome da máquina de cartão (ex: "laranjinha", "cielo", "stone", "getnet", "safrapay", "bin", "rede", "pagbank", "sumup").
   - NUNCA use endereços ou cidades (ex: "AV PRESIDENTE CASTELO BRANCO", "SAO PAULO-SP").
   - NUNCA use termos fiscais como "CNPJ do Emitente", "Consumidor", "Via Cliente", "Documento Auxiliar", "NFC-e", "DANFE".
3. "amount_cents": O valor total final pago da transação, em centavos inteiros (ex: R$ 56,97 = 5697; R$ 932,05 = 93205; R$ 208,03 = 20803).
   ATENÇÃO: Ignore valores de tributos incidentes (lei 12.741), parcelas individuais, troco ou descontos. Capture apenas o Total a Pagar / Valor Total / Valor Pago.
4. "is_expense": true se for despesa (compra/pagamento), false se for receita (recebimento).
5. "detected_bank": O nome do banco ou emissor do cartão (ex: "Nubank", "Itaú", "Bradesco", "Santander", "Inter", "C6", "Caixa", "Banco do Brasil", "PagBank", "Mercado Pago", etc.) se identificado, ou string vazia se não houver.`;

class GeminiReceiptService {
  // Test if an API key is valid using ListModels endpoint (dynamic & resilient)
  async testApiKey(apiKey) {
    const cleanKey = (apiKey || '').trim();
    if (!cleanKey) {
      return { success: false, error: 'Chave de API não informada.' };
    }

    try {
      const url = `https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(cleanKey)}`;
      const res = await fetch(url);

      if (res.ok) {
        const data = await res.json().catch(() => ({}));
        let availableModels = [];
        if (Array.isArray(data.models)) {
          availableModels = data.models
            .filter(m => Array.isArray(m.supportedGenerationMethods) && m.supportedGenerationMethods.includes('generateContent'))
            .map(m => m.name.replace(/^models\//, ''))
            .filter(name => name.includes('flash') || name.includes('gemini'));
        }
        const bestModel = availableModels.find(m => m.includes('3.8') || m.includes('3.5')) || availableModels[0] || 'gemini-3.8-flash';
        return { success: true, models: availableModels, bestModel };
      }

      const errData = await res.json().catch(() => ({}));
      const msg = errData?.error?.message || `Erro HTTP ${res.status}`;
      return { success: false, error: msg };
    } catch (err) {
      return { success: false, error: err.message || 'Falha de conexão com a API do Google.' };
    }
  }

  // Analyze single receipt image via Gemini Multimodal Vision
  async analyzeReceipt(dataUrl, apiKey, onProgress = null) {
    const cleanKey = (apiKey || '').trim();
    if (!cleanKey) {
      throw new Error('Chave de API do Gemini não configurada.');
    }

    // Extract base64 and mime type from dataUrl
    const match = dataUrl.match(/^data:([^;]+);base64,(.+)$/);
    if (!match) {
      throw new Error('Formato de imagem inválido para envio.');
    }
    const mimeType = match[1] || 'image/jpeg';
    const base64Data = match[2];

    const payload = {
      contents: [
        {
          parts: [
            { text: SYSTEM_PROMPT },
            {
              inline_data: {
                mime_type: mimeType,
                data: base64Data
              }
            }
          ]
        }
      ],
      generationConfig: {
        temperature: 0.1,
        response_mime_type: 'application/json'
      }
    };

    // Build model list: dynamic account discovery merged with fallback candidates
    let modelsToTry = [...CANDIDATE_MODELS];
    try {
      const listRes = await fetch(`https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(cleanKey)}`);
      if (listRes.ok) {
        const listData = await listRes.json();
        if (Array.isArray(listData.models)) {
          const accountModels = listData.models
            .filter(m => Array.isArray(m.supportedGenerationMethods) && m.supportedGenerationMethods.includes('generateContent'))
            .map(m => m.name.replace(/^models\//, ''))
            .filter(name => name.includes('flash'));

          if (accountModels.length > 0) {
            // Put account's active models in front
            modelsToTry = Array.from(new Set([...accountModels, ...CANDIDATE_MODELS]));
          }
        }
      }
    } catch (_) {}

    let lastError = null;

    for (const model of modelsToTry) {
      if (onProgress) {
        onProgress(`Consultando IA Gemini (${model})...`);
      }

      try {
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(cleanKey)}`;
        const res = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        if (!res.ok) {
          const errBody = await res.json().catch(() => ({}));
          const errMsg = errBody?.error?.message || `HTTP ${res.status}`;
          lastError = new Error(`Modelo ${model}: ${errMsg}`);
          continue;
        }

        const data = await res.json();
        const candidate = data?.candidates?.[0];
        const rawText = candidate?.content?.parts?.[0]?.text;

        if (!rawText || !rawText.trim()) {
          lastError = new Error(`Modelo ${model} retornou resposta vazia.`);
          continue;
        }

        // Clean markdown code blocks if returned
        const cleanJson = rawText.replace(/```json/gi, '').replace(/```/g, '').trim();
        const parsed = JSON.parse(cleanJson);

        const payee = (parsed.payee || '').trim();
        const amountCents = typeof parsed.amount_cents === 'number'
          ? Math.round(parsed.amount_cents)
          : parseInt(parsed.amount_cents, 10) || 0;

        if (!payee || amountCents <= 0) {
          lastError = new Error('IA não conseguiu extrair favorecido ou valor válido.');
          continue;
        }

        return {
          payee,
          amountCents,
          date: parsed.date || '',
          isExpense: parsed.is_expense !== false,
          detectedBank: (parsed.detected_bank || '').trim(),
          model,
          rawJson: cleanJson
        };
      } catch (err) {
        lastError = err;
        continue;
      }
    }

    throw lastError || new Error('Não foi possível obter resposta dos modelos do Gemini.');
  }
}

export const geminiReceiptService = new GeminiReceiptService();
