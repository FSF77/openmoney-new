import 'dart:convert';
import 'dart:io';

class GeminiReceiptResult {
  final String date;
  final String payee;
  final int amountCents;
  final bool isExpense;
  final String detectedBank;
  final String rawJson;

  const GeminiReceiptResult({
    required this.date,
    required this.payee,
    required this.amountCents,
    required this.isExpense,
    required this.detectedBank,
    required this.rawJson,
  });
}

class GeminiReceiptService {
  /// Envia imagem ou PDF para o Google Gemini Flash e recebe JSON estruturado
  static Future<GeminiReceiptResult?> analyzeReceipt({
    required String filePath,
    required String apiKey,
    String extractedText = '',
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) return null;

    final file = File(filePath);
    final ext = filePath.split('.').last.toLowerCase();

    String mimeType;
    if (ext == 'pdf') {
      mimeType = 'application/pdf';
    } else if (ext == 'png') {
      mimeType = 'image/png';
    } else if (ext == 'jpg' || ext == 'jpeg') {
      mimeType = 'image/jpeg';
    } else if (ext == 'heic') {
      mimeType = 'image/heic';
    } else {
      mimeType = 'image/jpeg';
    }

    String base64Data = '';
    if (file.existsSync()) {
      try {
        final bytes = await file.readAsBytes();
        base64Data = base64Encode(bytes);
      } catch (_) {}
    }

    var prompt = '''
Você é um especialista contábil em leitura de comprovantes fiscais e recibos bancários brasileiros (cupons fiscais NFC-e, extratos, comprovantes de cartão de crédito/débito e Pix).
Analise as informações do comprovante e extraia um JSON com as chaves:
1. "date": A data da transação/emissão no formato "AAAA-MM-DD" (ex: "2026-10-24" ou "2024-02-12").
2. "payee": O nome do estabelecimento comercial, loja, restaurante ou pessoa favorecida (ex: "LEROY MERLIN", "PERFUMARIA ORQUIDEA", "RESTAURANTE BARDOURO", "COMERCIAL ESPERANCA").
   REGRAS OBRIGATÓRIAS PARA O NOME:
   - NUNCA use o nome da máquina de cartão (ex: "laranjinha", "cielo", "stone", "getnet", "safrapay", "bin", "rede").
   - NUNCA use endereços ou cidades (ex: "AV PRESIDENTE CASTELO BRANCO", "SAO PAULO-SP").
   - NUNCA use frases fiscais como "CNPJ do Emitente", "Consumidor", "Via Cliente", "Documento Auxiliar", "NFC-e".
3. "amount_cents": O valor total final pago da transação, em centavos inteiros (ex: R\$ 56,97 = 5697; R\$ 932,05 = 93205; R\$ 208,03 = 20803).
   ATENÇÃO: Ignore valores de tributos incidentes (lei 12.741), parcelas individuais, troco ou descontos. Pegue o Total a Pagar / Valor Total / Valor Pago.
4. "is_expense": true se for despesa (compra/pagamento), false se for receita (recebimento).
5. "detected_bank": O nome do banco ou emissor (ex: "Nubank", "Itaú", "Bradesco", "Santander", "Inter", "C6", "Caixa", "Banco do Brasil", "PagBank", "Mercado Pago", etc.) se identificado, ou vazio se não houver.
''';

    if (extractedText.trim().isNotEmpty) {
      prompt += '\n\nTexto extraído do documento para referência:\n$extractedText\n';
    }

    final candidateModels = [
      'gemini-3.5-flash-lite',
      'gemini-2.5-flash',
      'gemini-flash-latest',
    ];

    for (final model in candidateModels) {
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$cleanKey');

      final parts = <Map<String, dynamic>>[
        {'text': prompt}
      ];

      if (base64Data.isNotEmpty) {
        parts.add({
          'inline_data': {
            'mime_type': mimeType,
            'data': base64Data,
          }
        });
      }

      final payload = {
        'contents': [
          {'parts': parts}
        ],
        'generationConfig': {
          'temperature': 0.1,
          'response_mime_type': 'application/json',
        }
      };

      final client = HttpClient();
      try {
        final req = await client.postUrl(uri);
        req.headers.set('Content-Type', 'application/json; charset=utf-8');
        req.add(utf8.encode(jsonEncode(payload)));

        final res = await req.close();
        if (res.statusCode != 200) {
          continue;
        }

        final resBody = await res.transform(utf8.decoder).join();
        final parsed = jsonDecode(resBody);
        final candidates = parsed['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) continue;

        final text = candidates.first['content']?['parts']?[0]?['text'] as String?;
        if (text == null || text.trim().isEmpty) continue;

        final cleanJson = text.replaceAll('```json', '').replaceAll('```', '').trim();
        final data = jsonDecode(cleanJson);

        final payee = (data['payee'] as String?)?.trim() ?? '';
        final amountCents = (data['amount_cents'] as num?)?.toInt() ?? 0;

        if (payee.isNotEmpty && amountCents > 0) {
          return GeminiReceiptResult(
            date: data['date'] ?? '',
            payee: payee,
            amountCents: amountCents,
            isExpense: data['is_expense'] ?? true,
            detectedBank: data['detected_bank'] ?? '',
            rawJson: cleanJson,
          );
        }
      } catch (_) {
        continue;
      } finally {
        client.close();
      }
    }

    return null;
  }
}
