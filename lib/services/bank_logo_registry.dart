import 'package:flutter/material.dart';
import '../models/openmoney_models.dart';
import '../ui/theme/liquid_glass.dart';

class BankLogoItem {
  final String id;
  final String name;
  final String filename;

  const BankLogoItem({
    required this.id,
    required this.name,
    required this.filename,
  });

  String get assetPath => 'logo/$filename';
}

class BankLogoRegistry {
  static const List<BankLogoItem> items = [
    // Principais Bancos & Fintechs
    BankLogoItem(id: 'nubank', name: 'Nubank', filename: 'nubank.png'),
    BankLogoItem(id: 'nubank-ultravioleta', name: 'Nubank Ultravioleta', filename: 'nubank-ultravioleta.png'),
    BankLogoItem(id: 'nubank-pj', name: 'Nubank PJ', filename: 'nubank.pj.png'),
    BankLogoItem(id: 'itau', name: 'Itaú', filename: 'itau.png'),
    BankLogoItem(id: 'itau-uniclass', name: 'Itaú Uniclass', filename: 'itau-uniclass.png'),
    BankLogoItem(id: 'itaupersonnalite', name: 'Itaú Personnalité', filename: 'itaupersonnalite.png'),
    BankLogoItem(id: 'itau-empresas', name: 'Itaú Empresas', filename: 'itau.empresas.png'),
    BankLogoItem(id: 'bb', name: 'Banco do Brasil', filename: 'bb.png'),
    BankLogoItem(id: 'bradesco', name: 'Bradesco', filename: 'bradesco.png'),
    BankLogoItem(id: 'bradesco-empresas', name: 'Bradesco Empresas', filename: 'bradesco-empresas.png'),
    BankLogoItem(id: 'santander', name: 'Santander', filename: 'santander.png'),
    BankLogoItem(id: 'santander-private', name: 'Santander Private', filename: 'santander-private.png'),
    BankLogoItem(id: 'c6bank', name: 'C6 Bank', filename: 'c6bank.png'),
    BankLogoItem(id: 'caixa', name: 'Caixa Econômica Federal', filename: 'caixa.png'),
    BankLogoItem(id: 'intermedium', name: 'Banco Inter', filename: 'intermedium.png'),
    BankLogoItem(id: 'interpj', name: 'Inter Empresas / PJ', filename: 'interpj.png'),
    BankLogoItem(id: 'btgpactual', name: 'BTG Pactual', filename: 'btgpactual.png'),
    BankLogoItem(id: 'btgplus', name: 'BTG+', filename: 'btgplus.png'),
    BankLogoItem(id: 'btg-empresas', name: 'BTG Empresas', filename: 'btg.empresas.png'),
    BankLogoItem(id: 'safra', name: 'Banco Safra', filename: 'safra.png'),
    BankLogoItem(id: 'neon', name: 'Banco Neon', filename: 'neon.png'),
    BankLogoItem(id: 'next', name: 'Banco Next', filename: 'next.png'),
    BankLogoItem(id: 'daycoval', name: 'Banco Daycoval', filename: 'daycoval.png'),
    BankLogoItem(id: 'brb', name: 'BRB - Banco de Brasília', filename: 'brb.png'),
    BankLogoItem(id: 'abcbrasil', name: 'Banco ABC Brasil', filename: 'abcbrasil.png'),
    BankLogoItem(id: 'votorantim', name: 'Banco Votorantim / BV', filename: 'votorantim.png'),
    BankLogoItem(id: 'citibank', name: 'Citibank', filename: 'citibank.png'),
    BankLogoItem(id: 'hsbc', name: 'HSBC', filename: 'hsbc.png'),
    BankLogoItem(id: 'sofisadireto', name: 'Sofisa Direto', filename: 'sofisadireto.png'),
    BankLogoItem(id: 'nomad', name: 'Nomad Global', filename: 'nomad.png'),
    BankLogoItem(id: 'revolut', name: 'Revolut', filename: 'revolut.png'),

    // Corretoras & Investimentos
    BankLogoItem(id: 'xp', name: 'XP Investimentos', filename: 'xp.png'),
    BankLogoItem(id: 'rico', name: 'Rico Investimentos', filename: 'rico.png'),
    BankLogoItem(id: 'clear-corretora', name: 'Clear Corretora', filename: 'clear-corretora.png'),
    BankLogoItem(id: 'genial', name: 'Genial Investimentos', filename: 'genial.png'),
    BankLogoItem(id: 'ion', name: 'Íon Itaú', filename: 'ion.png'),
    BankLogoItem(id: 'agora', name: 'Ágora Investimentos', filename: 'agora.png'),
    BankLogoItem(id: 'toroinvestimentos', name: 'Toro Investimentos', filename: 'toroinvestimentos.png'),
    BankLogoItem(id: 'nu-invest', name: 'Nu Invest', filename: 'nu-invest.png'),
    BankLogoItem(id: 'easynvest', name: 'Easynvest', filename: 'easynvest.png'),
    BankLogoItem(id: 'modalmais', name: 'Modalmais', filename: 'modalmais.png'),
    BankLogoItem(id: 'orama', name: 'Órama Investimentos', filename: 'orama.png'),
    BankLogoItem(id: 'tesourodireto', name: 'Tesouro Direto', filename: 'tesourodireto.png'),
    BankLogoItem(id: 'tesouronacional', name: 'Tesouro Nacional', filename: 'tesouronacional.png'),

    // Cripto & Web3
    BankLogoItem(id: 'binance', name: 'Binance', filename: 'binance.png'),
    BankLogoItem(id: 'coinbase', name: 'Coinbase', filename: 'coinbase.png'),

    // Carteiras Digitais & Pagamentos
    BankLogoItem(id: 'picpay', name: 'PicPay', filename: 'picpay.png'),
    BankLogoItem(id: 'mercadopago', name: 'Mercado Pago', filename: 'mercadopago.png'),
    BankLogoItem(id: 'mercadolivre', name: 'Mercado Livre', filename: 'mercadolivre.png'),
    BankLogoItem(id: 'pagbank', name: 'PagBank', filename: 'pagbank.png'),
    BankLogoItem(id: 'pagseguro', name: 'PagSeguro', filename: 'pagseguro.png'),
    BankLogoItem(id: 'recargapay', name: 'RecargaPay', filename: 'recargapay.png'),
    BankLogoItem(id: '99pay', name: '99Pay', filename: '99Pay.png'),
    BankLogoItem(id: 'paypal', name: 'PayPal', filename: 'paypal.png'),
    BankLogoItem(id: 'infinitepay', name: 'InfinitePay', filename: 'infinitepay.png'),
    BankLogoItem(id: 'stone', name: 'Stone', filename: 'stone.png'),
    BankLogoItem(id: 'ton', name: 'Ton Stone', filename: 'ton.png'),
    BankLogoItem(id: 'sumup', name: 'SumUp Bank', filename: 'sumup.png'),
    BankLogoItem(id: 'contabilizei-bank', name: 'Contabilizei.bank', filename: 'contabilizei.bank.png'),
    BankLogoItem(id: 'ifood-conta-digital', name: 'iFood Conta Digital', filename: 'ifood-conta-digital.png'),

    // Benefícios & Vales
    BankLogoItem(id: 'alelo', name: 'Alelo', filename: 'alelo.png'),
    BankLogoItem(id: 'caju', name: 'Caju Benefícios', filename: 'caju.png'),
    BankLogoItem(id: 'vr', name: 'VR Benefícios', filename: 'vr.png'),

    // Cartões de Loja & Parcerias
    BankLogoItem(id: 'amazon', name: 'Amazon', filename: 'amazon.png'),
    BankLogoItem(id: 'c-a', name: 'C&A Pay', filename: 'c-a.png'),
    BankLogoItem(id: 'credicard-on', name: 'Credicard On', filename: 'credicard-on.png'),
    BankLogoItem(id: 'pao-acucar', name: 'Pão de Açúcar Mais', filename: 'pao-acucar.png'),
    BankLogoItem(id: 'portoseguro', name: 'Porto Seguro Bank', filename: 'portoseguro.png'),
    BankLogoItem(id: 'renner', name: 'Lojas Renner / Realize', filename: 'renner.png'),
    BankLogoItem(id: 'riachuelo', name: 'Riachuelo / Midway', filename: 'riachuelo.png'),
    BankLogoItem(id: 'samsung', name: 'Samsung Pay / Card', filename: 'samsung.png'),

    // Bandeiras de Cartão
    BankLogoItem(id: 'visa', name: 'Visa', filename: 'visa.png'),
    BankLogoItem(id: 'mastercard', name: 'Mastercard', filename: 'mastercard.png'),
    BankLogoItem(id: 'master-black', name: 'Mastercard Black', filename: 'master-black.png'),
    BankLogoItem(id: 'elo', name: 'Elo', filename: 'elo.png'),
    BankLogoItem(id: 'amex', name: 'American Express', filename: 'amex.png'),
    BankLogoItem(id: 'diners', name: 'Diners Club', filename: 'diners.png'),
  ];

  static BankLogoItem? findByIdOrFilename(String? query) {
    if (query == null || query.trim().isEmpty) return null;
    final q = query.trim().toLowerCase();
    for (final item in items) {
      if (item.filename.toLowerCase() == q ||
          item.id.toLowerCase() == q ||
          item.name.toLowerCase() == q) {
        return item;
      }
    }
    return null;
  }
}

class AccountLogoWidget extends StatelessWidget {
  final Account account;
  final double size;
  final double cornerRadius;
  final bool selected;

  const AccountLogoWidget({
    super.key,
    required this.account,
    this.size = 28,
    this.cornerRadius = 8,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isCard = account.type == kCardType;

    final logoItem = BankLogoRegistry.findByIdOrFilename(account.logo);

    if (logoItem != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.15)
              : colors.borderGlass.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(cornerRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(size >= 40 ? 4.0 : 2.5),
          child: Image.asset(
            logoItem.assetPath,
            width: size >= 40 ? size - 8 : size - 5,
            height: size >= 40 ? size - 8 : size - 5,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                _buildFallbackIcon(colors, isCard),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected
            ? colors.accent.withValues(alpha: 0.15)
            : colors.borderGlass.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: _buildFallbackIcon(colors, isCard),
    );
  }

  Widget _buildFallbackIcon(OpenMoneyColors colors, bool isCard) {
    return Icon(
      isCard ? Icons.credit_card : Icons.account_balance_wallet_outlined,
      size: size * 0.58,
      color: selected ? colors.accent : colors.textSecondary,
    );
  }
}
