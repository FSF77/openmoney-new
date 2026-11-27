import 'package:flutter/material.dart';
import '../models/openmoney_models.dart';
import '../store/money_store.dart';
import '../ui/theme/liquid_glass.dart';

class CategoryIconItem {
  final String id;
  final String label;
  final String group;
  final IconData icon;
  final List<String> keywords;

  const CategoryIconItem({
    required this.id,
    required this.label,
    required this.group,
    required this.icon,
    this.keywords = const [],
  });
}

class CategoryColorOption {
  final String key;
  final String label;
  final Color lightColor;
  final Color darkColor;

  const CategoryColorOption({
    required this.key,
    required this.label,
    required this.lightColor,
    required this.darkColor,
  });

  Color colorFor(bool isDark) => isDark ? darkColor : lightColor;
}

class ResolvedCategoryVisual {
  final IconData icon;
  final Color color;
  final String? iconId;
  final String? colorKey;
  final bool isInherited;
  final bool isCustomized;

  const ResolvedCategoryVisual({
    required this.icon,
    required this.color,
    this.iconId,
    this.colorKey,
    this.isInherited = false,
    this.isCustomized = false,
  });
}

class CategoryIconRegistry {
  static const List<String> groups = [
    'Todos',
    'Alimentação',
    'Casa',
    'Transporte',
    'Saúde',
    'Compras',
    'Lazer',
    'Tecnologia',
    'Educação',
    'Finanças',
    'Família & Pessoal',
    'Outros',
  ];

  static const List<CategoryColorOption> colors = [
    CategoryColorOption(
      key: 'orange',
      label: 'Laranja',
      lightColor: Color(0xFFEA580C),
      darkColor: Color(0xFFFB923C),
    ),
    CategoryColorOption(
      key: 'amber',
      label: 'Âmbar',
      lightColor: Color(0xFFD97706),
      darkColor: Color(0xFFFBBF24),
    ),
    CategoryColorOption(
      key: 'emerald',
      label: 'Esmeralda',
      lightColor: Color(0xFF059669),
      darkColor: Color(0xFF34D399),
    ),
    CategoryColorOption(
      key: 'teal',
      label: 'Turquesa',
      lightColor: Color(0xFF0D9488),
      darkColor: Color(0xFF2DD4BF),
    ),
    CategoryColorOption(
      key: 'cyan',
      label: 'Ciano',
      lightColor: Color(0xFF0891B2),
      darkColor: Color(0xFF22D3EE),
    ),
    CategoryColorOption(
      key: 'sky',
      label: 'Azul Céu',
      lightColor: Color(0xFF0284C7),
      darkColor: Color(0xFF38BDF8),
    ),
    CategoryColorOption(
      key: 'blue',
      label: 'Azul',
      lightColor: Color(0xFF2563EB),
      darkColor: Color(0xFF60A5FA),
    ),
    CategoryColorOption(
      key: 'indigo',
      label: 'Índigo',
      lightColor: Color(0xFF4F46E5),
      darkColor: Color(0xFF818CF8),
    ),
    CategoryColorOption(
      key: 'violet',
      label: 'Violeta',
      lightColor: Color(0xFF7C3AED),
      darkColor: Color(0xFFA78BFA),
    ),
    CategoryColorOption(
      key: 'purple',
      label: 'Roxo',
      lightColor: Color(0xFF9333EA),
      darkColor: Color(0xFFC084FC),
    ),
    CategoryColorOption(
      key: 'pink',
      label: 'Rosa',
      lightColor: Color(0xFFDB2777),
      darkColor: Color(0xFFF472B6),
    ),
    CategoryColorOption(
      key: 'rose',
      label: 'Framboesa',
      lightColor: Color(0xFFE11D48),
      darkColor: Color(0xFFFB7185),
    ),
    CategoryColorOption(
      key: 'red',
      label: 'Vermelho',
      lightColor: Color(0xFFDC2626),
      darkColor: Color(0xFFF87171),
    ),
    CategoryColorOption(
      key: 'lime',
      label: 'Lima',
      lightColor: Color(0xFF65A30D),
      darkColor: Color(0xFFA3E635),
    ),
    CategoryColorOption(
      key: 'slate',
      label: 'Grafite',
      lightColor: Color(0xFF475569),
      darkColor: Color(0xFF94A3B8),
    ),
  ];

  static const List<CategoryIconItem> items = [
    // Alimentação
    CategoryIconItem(
      id: 'restaurant',
      label: 'Restaurante',
      group: 'Alimentação',
      icon: Icons.restaurant_rounded,
      keywords: ['alimentacao', 'comida', 'jantar', 'almoco', 'refeicao'],
    ),
    CategoryIconItem(
      id: 'shopping_cart',
      label: 'Mercado',
      group: 'Alimentação',
      icon: Icons.shopping_cart_rounded,
      keywords: ['supermercado', 'feira', 'hortifruti', 'compras mes'],
    ),
    CategoryIconItem(
      id: 'local_bar',
      label: 'Bares & Drinks',
      group: 'Alimentação',
      icon: Icons.local_bar_rounded,
      keywords: ['bar', 'bebida', 'cerveja', 'happy hour', 'pub'],
    ),
    CategoryIconItem(
      id: 'local_cafe',
      label: 'Café & Padaria',
      group: 'Alimentação',
      icon: Icons.local_cafe_rounded,
      keywords: ['cafe', 'padaria', 'lanche', 'cafeteria', 'bolo'],
    ),
    CategoryIconItem(
      id: 'fastfood',
      label: 'Lanches',
      group: 'Alimentação',
      icon: Icons.fastfood_rounded,
      keywords: ['lanche', 'hamburguer', 'snack', 'fast food'],
    ),
    CategoryIconItem(
      id: 'local_pizza',
      label: 'Pizza',
      group: 'Alimentação',
      icon: Icons.local_pizza_rounded,
      keywords: ['pizzaria', 'massa'],
    ),
    CategoryIconItem(
      id: 'delivery_dining',
      label: 'Delivery',
      group: 'Alimentação',
      icon: Icons.delivery_dining_rounded,
      keywords: ['ifood', 'rappi', 'entrega', 'pedido'],
    ),
    CategoryIconItem(
      id: 'bakery_dining',
      label: 'Confeitaria',
      group: 'Alimentação',
      icon: Icons.bakery_dining_rounded,
      keywords: ['doce', 'pao', 'croissant', 'padaria'],
    ),

    // Casa
    CategoryIconItem(
      id: 'home',
      label: 'Casa',
      group: 'Casa',
      icon: Icons.home_rounded,
      keywords: ['moradia', 'lar', 'residencia', 'aluguel'],
    ),
    CategoryIconItem(
      id: 'apartment',
      label: 'Condomínio',
      group: 'Casa',
      icon: Icons.apartment_rounded,
      keywords: ['predio', 'apartamento', 'aluguel', 'sindico'],
    ),
    CategoryIconItem(
      id: 'bolt',
      label: 'Energia',
      group: 'Casa',
      icon: Icons.bolt_rounded,
      keywords: ['luz', 'eletricidade', 'energia eletrica', 'conta de luz'],
    ),
    CategoryIconItem(
      id: 'water_drop',
      label: 'Água',
      group: 'Casa',
      icon: Icons.water_drop_rounded,
      keywords: ['esgoto', 'saneamento', 'sabesp', 'conta de agua'],
    ),
    CategoryIconItem(
      id: 'local_fire_department',
      label: 'Gás',
      group: 'Casa',
      icon: Icons.local_fire_department_rounded,
      keywords: ['botijao', 'encanado', 'comgas'],
    ),
    CategoryIconItem(
      id: 'wifi',
      label: 'Internet',
      group: 'Casa',
      icon: Icons.wifi_rounded,
      keywords: ['fibra', 'banda larga', 'roteador', 'provedor'],
    ),
    CategoryIconItem(
      id: 'phone_android',
      label: 'Telefonia',
      group: 'Casa',
      icon: Icons.phone_android_rounded,
      keywords: ['celular', 'plano', 'vivo', 'claro', 'tim'],
    ),
    CategoryIconItem(
      id: 'tv',
      label: 'TV',
      group: 'Casa',
      icon: Icons.tv_rounded,
      keywords: ['televisao', 'cabo', 'smart tv'],
    ),
    CategoryIconItem(
      id: 'cleaning_services',
      label: 'Limpeza',
      group: 'Casa',
      icon: Icons.cleaning_services_rounded,
      keywords: ['diarista', 'faxina', 'lavanderia', 'produtos limpeza'],
    ),
    CategoryIconItem(
      id: 'handyman',
      label: 'Manutenção',
      group: 'Casa',
      icon: Icons.handyman_rounded,
      keywords: ['reforma', 'conserto', 'ferramenta', 'reparo'],
    ),

    // Transporte
    CategoryIconItem(
      id: 'directions_car',
      label: 'Carro',
      group: 'Transporte',
      icon: Icons.directions_car_rounded,
      keywords: ['transporte', 'automovel', 'veiculo', 'uber', '99'],
    ),
    CategoryIconItem(
      id: 'local_gas_station',
      label: 'Combustível',
      group: 'Transporte',
      icon: Icons.local_gas_station_rounded,
      keywords: ['gasolina', 'etanol', 'diesel', 'posto', 'abastecimento'],
    ),
    CategoryIconItem(
      id: 'local_parking',
      label: 'Estacionamento',
      group: 'Transporte',
      icon: Icons.local_parking_rounded,
      keywords: ['garagem', 'valet', 'zona azul'],
    ),
    CategoryIconItem(
      id: 'toll',
      label: 'Pedágio',
      group: 'Transporte',
      icon: Icons.toll_rounded,
      keywords: ['sem parar', 'veloe', 'tag', 'rodovia'],
    ),
    CategoryIconItem(
      id: 'directions_bus',
      label: 'Transporte Público',
      group: 'Transporte',
      icon: Icons.directions_bus_rounded,
      keywords: ['onibus', 'metro', 'trem', 'passagem', 'bilhete unico'],
    ),
    CategoryIconItem(
      id: 'local_taxi',
      label: 'App / Táxi',
      group: 'Transporte',
      icon: Icons.local_taxi_rounded,
      keywords: ['uber', '99', 'taxi', 'corrida'],
    ),
    CategoryIconItem(
      id: 'two_wheeler',
      label: 'Moto / Bike',
      group: 'Transporte',
      icon: Icons.two_wheeler_rounded,
      keywords: ['motocicleta', 'bicicleta', 'scooter'],
    ),
    CategoryIconItem(
      id: 'car_repair',
      label: 'Oficina',
      group: 'Transporte',
      icon: Icons.car_repair_rounded,
      keywords: ['mecanico', 'revisao', 'pneu', 'lavagem'],
    ),
    CategoryIconItem(
      id: 'flight',
      label: 'Viagem',
      group: 'Transporte',
      icon: Icons.flight_rounded,
      keywords: ['aviao', 'passagem aerea', 'voo', 'aeroporto', 'ferias'],
    ),
    CategoryIconItem(
      id: 'hotel',
      label: 'Hospedagem',
      group: 'Transporte',
      icon: Icons.hotel_rounded,
      keywords: ['hotel', 'pousada', 'airbnb', 'viagem'],
    ),

    // Saúde
    CategoryIconItem(
      id: 'medical_services',
      label: 'Saúde',
      group: 'Saúde',
      icon: Icons.medical_services_rounded,
      keywords: ['medico', 'consulta', 'clinica', 'hospital', 'plano'],
    ),
    CategoryIconItem(
      id: 'medication',
      label: 'Medicamentos',
      group: 'Saúde',
      icon: Icons.medication_rounded,
      keywords: ['farmacia', 'remedio', 'drogaria'],
    ),
    CategoryIconItem(
      id: 'favorite',
      label: 'Bem-estar',
      group: 'Saúde',
      icon: Icons.favorite_rounded,
      keywords: ['seguro de vida', 'cardiologia', 'coracao'],
    ),
    CategoryIconItem(
      id: 'psychology',
      label: 'Terapia',
      group: 'Saúde',
      icon: Icons.psychology_rounded,
      keywords: ['terapeuta', 'psicologo', 'saude mental'],
    ),
    CategoryIconItem(
      id: 'health_and_safety',
      label: 'Plano / Seguro',
      group: 'Saúde',
      icon: Icons.health_and_safety_rounded,
      keywords: ['plano de saude', 'convenio', 'odontologico'],
    ),
    CategoryIconItem(
      id: 'fitness_center',
      label: 'Academia',
      group: 'Saúde',
      icon: Icons.fitness_center_rounded,
      keywords: ['treino', 'musculacao', 'crossfit', 'personal', 'esporte'],
    ),

    // Compras
    CategoryIconItem(
      id: 'shopping_bag',
      label: 'Compras',
      group: 'Compras',
      icon: Icons.shopping_bag_rounded,
      keywords: ['loja', 'shopping', 'varejo', 'presente'],
    ),
    CategoryIconItem(
      id: 'checkroom',
      label: 'Vestuário',
      group: 'Compras',
      icon: Icons.checkroom_rounded,
      keywords: ['roupa', 'calcado', 'sapato', 'moda'],
    ),
    CategoryIconItem(
      id: 'devices',
      label: 'Eletrônicos',
      group: 'Compras',
      icon: Icons.devices_rounded,
      keywords: ['informatica', 'notebook', 'celular', 'gadget'],
    ),
    CategoryIconItem(
      id: 'chair',
      label: 'Móveis',
      group: 'Compras',
      icon: Icons.chair_rounded,
      keywords: ['decoracao', 'sofa', 'casa'],
    ),
    CategoryIconItem(
      id: 'kitchen',
      label: 'Eletrodomésticos',
      group: 'Compras',
      icon: Icons.kitchen_rounded,
      keywords: ['geladeira', 'fogao', 'eletro'],
    ),
    CategoryIconItem(
      id: 'redeem',
      label: 'Presentes',
      group: 'Compras',
      icon: Icons.redeem_rounded,
      keywords: ['aniversario', 'mimo', 'cashback', 'premio'],
    ),

    // Lazer
    CategoryIconItem(
      id: 'sports_esports',
      label: 'Games',
      group: 'Lazer',
      icon: Icons.sports_esports_rounded,
      keywords: ['videogame', 'jogo', 'nintendo', 'playstation', 'xbox', 'lazer'],
    ),
    CategoryIconItem(
      id: 'movie',
      label: 'Cinema & Teatro',
      group: 'Lazer',
      icon: Icons.movie_rounded,
      keywords: ['filme', 'ingresso', 'show', 'cultura'],
    ),
    CategoryIconItem(
      id: 'music_note',
      label: 'Música',
      group: 'Lazer',
      icon: Icons.music_note_rounded,
      keywords: ['spotify', 'show', 'instrumento', 'audio'],
    ),
    CategoryIconItem(
      id: 'celebration',
      label: 'Festas',
      group: 'Lazer',
      icon: Icons.celebration_rounded,
      keywords: ['evento', 'comemoracao', 'balada', 'aniversario'],
    ),
    CategoryIconItem(
      id: 'beach_access',
      label: 'Passeios',
      group: 'Lazer',
      icon: Icons.beach_access_rounded,
      keywords: ['praia', 'parque', 'diversao', 'lazer'],
    ),
    CategoryIconItem(
      id: 'sports_soccer',
      label: 'Esportes',
      group: 'Lazer',
      icon: Icons.sports_soccer_rounded,
      keywords: ['futebol', 'tenis', 'corrida', 'clube'],
    ),

    // Tecnologia & Assinaturas
    CategoryIconItem(
      id: 'subscriptions',
      label: 'Assinaturas',
      group: 'Tecnologia',
      icon: Icons.subscriptions_rounded,
      keywords: ['recorrente', 'mensalidade', 'streaming', 'servicos'],
    ),
    CategoryIconItem(
      id: 'smart_display',
      label: 'Streaming',
      group: 'Tecnologia',
      icon: Icons.smart_display_rounded,
      keywords: ['netflix', 'youtube', 'disney', 'prime', 'hbo'],
    ),
    CategoryIconItem(
      id: 'auto_awesome',
      label: 'IA & Apps',
      group: 'Tecnologia',
      icon: Icons.auto_awesome_rounded,
      keywords: ['inteligencia artificial', 'chatgpt', 'gemini', 'claude'],
    ),
    CategoryIconItem(
      id: 'cloud',
      label: 'Nuvem & Software',
      group: 'Tecnologia',
      icon: Icons.cloud_rounded,
      keywords: ['icloud', 'google one', 'dropbox', 'software', 'saas'],
    ),
    CategoryIconItem(
      id: 'language',
      label: 'Sites & Domínios',
      group: 'Tecnologia',
      icon: Icons.language_rounded,
      keywords: ['web', 'hospedagem', 'dominio', 'servidor'],
    ),
    CategoryIconItem(
      id: 'laptop_mac',
      label: 'Computador',
      group: 'Tecnologia',
      icon: Icons.laptop_mac_rounded,
      keywords: ['apple', 'mac', 'microsoft', 'pc'],
    ),

    // Educação
    CategoryIconItem(
      id: 'school',
      label: 'Educação',
      group: 'Educação',
      icon: Icons.school_rounded,
      keywords: ['escola', 'faculdade', 'universidade', 'mensalidade'],
    ),
    CategoryIconItem(
      id: 'menu_book',
      label: 'Livros & Cursos',
      group: 'Educação',
      icon: Icons.menu_book_rounded,
      keywords: ['curso', 'livro', 'apostila', 'treinamento', 'ingles'],
    ),

    // Finanças & Receitas
    CategoryIconItem(
      id: 'payments',
      label: 'Salário / Renda',
      group: 'Finanças',
      icon: Icons.payments_rounded,
      keywords: ['salario', 'renda', 'pagamento', 'pro-labore', 'dinheiro'],
    ),
    CategoryIconItem(
      id: 'account_balance',
      label: 'Banco & Impostos',
      group: 'Finanças',
      icon: Icons.account_balance_rounded,
      keywords: ['imposto', 'taxa', 'tarifa', 'tributo', 'governo', 'iptu', 'ipva'],
    ),
    CategoryIconItem(
      id: 'account_balance_wallet',
      label: 'Carteira',
      group: 'Finanças',
      icon: Icons.account_balance_wallet_rounded,
      keywords: ['outras rendas', 'beneficio', 'vale', 'reembolso'],
    ),
    CategoryIconItem(
      id: 'savings',
      label: 'Poupança / Aportes',
      group: 'Finanças',
      icon: Icons.savings_rounded,
      keywords: ['investimento', 'reserva', 'caixinha', 'cofrinho'],
    ),
    CategoryIconItem(
      id: 'trending_up',
      label: 'Investimentos',
      group: 'Finanças',
      icon: Icons.trending_up_rounded,
      keywords: ['acoes', 'renda fixa', 'fii', 'cripto', 'aporte'],
    ),
    CategoryIconItem(
      id: 'show_chart',
      label: 'Rendimentos',
      group: 'Finanças',
      icon: Icons.show_chart_rounded,
      keywords: ['dividendos', 'juros', 'lucro', 'jcp'],
    ),
    CategoryIconItem(
      id: 'storefront',
      label: 'Vendas & Negócios',
      group: 'Finanças',
      icon: Icons.storefront_rounded,
      keywords: ['venda', 'comercio', 'loja', 'freelance'],
    ),
    CategoryIconItem(
      id: 'work',
      label: 'Trabalho / Serviços',
      group: 'Finanças',
      icon: Icons.work_rounded,
      keywords: ['servico', 'freela', 'consultoria', 'honorarios', 'pj'],
    ),
    CategoryIconItem(
      id: 'receipt_long',
      label: 'Contas & Boletos',
      group: 'Finanças',
      icon: Icons.receipt_long_rounded,
      keywords: ['fatura', 'boleto', 'nota fiscal', 'recibo'],
    ),
    CategoryIconItem(
      id: 'credit_card',
      label: 'Cartão',
      group: 'Finanças',
      icon: Icons.credit_card_rounded,
      keywords: ['anuidade', 'parcela', 'credito'],
    ),
    CategoryIconItem(
      id: 'gavel',
      label: 'Multas & Documentos',
      group: 'Finanças',
      icon: Icons.gavel_rounded,
      keywords: ['multa', 'documentacao', 'cartorio', 'advogado'],
    ),
    CategoryIconItem(
      id: 'swap_horiz',
      label: 'Transferência',
      group: 'Finanças',
      icon: Icons.swap_horiz_rounded,
      keywords: ['pix', 'ted', 'doc', 'movimentacao'],
    ),

    // Família & Pessoal
    CategoryIconItem(
      id: 'family_restroom',
      label: 'Família',
      group: 'Família & Pessoal',
      icon: Icons.family_restroom_rounded,
      keywords: ['filhos', 'crianca', 'casa', 'mesada'],
    ),
    CategoryIconItem(
      id: 'child_care',
      label: 'Crianças & Bebê',
      group: 'Família & Pessoal',
      icon: Icons.child_care_rounded,
      keywords: ['bebe', 'fralda', 'creche', 'brinquedo'],
    ),
    CategoryIconItem(
      id: 'pets',
      label: 'Pets',
      group: 'Família & Pessoal',
      icon: Icons.pets_rounded,
      keywords: ['cachorro', 'gato', 'racao', 'veterinario', 'petshop'],
    ),
    CategoryIconItem(
      id: 'spa',
      label: 'Cuidados Pessoais',
      group: 'Família & Pessoal',
      icon: Icons.spa_rounded,
      keywords: ['beleza', 'estetica', 'perfumaria', 'autocuidado'],
    ),
    CategoryIconItem(
      id: 'content_cut',
      label: 'Salão & Barbearia',
      group: 'Família & Pessoal',
      icon: Icons.content_cut_rounded,
      keywords: ['cabelo', 'cabeleireiro', 'barbeiro', 'manicure'],
    ),
    CategoryIconItem(
      id: 'volunteer_activism',
      label: 'Doações',
      group: 'Família & Pessoal',
      icon: Icons.volunteer_activism_rounded,
      keywords: ['caridade', 'dizimo', 'oferta', 'ong', 'ajuda'],
    ),

    // Outros
    CategoryIconItem(
      id: 'shield',
      label: 'Seguros',
      group: 'Outros',
      icon: Icons.shield_rounded,
      keywords: ['seguro', 'protecao', 'auto', 'residencial'],
    ),
    CategoryIconItem(
      id: 'star',
      label: 'Favoritos / Especiais',
      group: 'Outros',
      icon: Icons.star_rounded,
      keywords: ['destaque', 'importante', 'meta'],
    ),
    CategoryIconItem(
      id: 'build',
      label: 'Serviços Gerais',
      group: 'Outros',
      icon: Icons.build_rounded,
      keywords: ['ferramenta', 'tecnico', 'suporte'],
    ),
    CategoryIconItem(
      id: 'label_outline',
      label: 'Outros',
      group: 'Outros',
      icon: Icons.label_outline_rounded,
      keywords: ['diversos', 'geral', 'sem categoria'],
    ),
  ];

  static final Map<String, CategoryIconItem> _iconById = {
    for (final item in items) item.id: item,
  };

  static final Map<String, CategoryColorOption> _colorByKey = {
    for (final c in colors) c.key: c,
  };

  static CategoryIconItem? findIconById(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    return _iconById[id.trim()];
  }

  static CategoryColorOption? findColorByKey(String? key) {
    if (key == null || key.trim().isEmpty) return null;
    return _colorByKey[key.trim()];
  }

  static List<CategoryIconItem> searchIcons(String query, {String? group}) {
    final normQuery = removeDiacritics(query).trim().toLowerCase();
    final filterGroup = (group != null && group.isNotEmpty && group != 'Todos')
        ? group
        : null;

    return items.where((item) {
      if (filterGroup != null && item.group != filterGroup) return false;
      if (normQuery.isEmpty) return true;
      final normLabel = removeDiacritics(item.label).toLowerCase();
      final normGroup = removeDiacritics(item.group).toLowerCase();
      if (normLabel.contains(normQuery) ||
          normGroup.contains(normQuery) ||
          item.id.toLowerCase().contains(normQuery)) {
        return true;
      }
      for (final kw in item.keywords) {
        if (removeDiacritics(kw).toLowerCase().contains(normQuery)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  static ({String iconId, String colorKey}) suggestForName(
    String name, {
    String type = 'Despesa',
  }) {
    final norm = removeDiacritics(name).trim().toLowerCase();
    if (norm.isEmpty) {
      return type == 'Receita'
          ? (iconId: 'trending_up', colorKey: 'emerald')
          : (iconId: 'label_outline', colorKey: 'slate');
    }

    if (norm.contains('transferencia')) {
      return (iconId: 'swap_horiz', colorKey: 'sky');
    }

    // Regras semânticas em português (correspondência exata ou por palavra-chave)
    if (norm.contains('mercado') || norm.contains('supermercado') || norm.contains('hortifruti')) {
      return (iconId: 'shopping_cart', colorKey: 'orange');
    }
    if (norm.contains('bar') || norm.contains('bebida') || norm.contains('cerveja')) {
      return (iconId: 'local_bar', colorKey: 'orange');
    }
    if (norm.contains('cafe') || norm.contains('padaria') || norm.contains('lanche')) {
      return (iconId: 'local_cafe', colorKey: 'orange');
    }
    if (norm.contains('delivery') || norm.contains('ifood')) {
      return (iconId: 'delivery_dining', colorKey: 'orange');
    }
    if (norm.contains('alimenta') || norm.contains('restaurante') || norm.contains('comida')) {
      return (iconId: 'restaurant', colorKey: 'orange');
    }

    if (norm.contains('streaming') || norm.contains('netflix') || norm.contains('youtube')) {
      return (iconId: 'smart_display', colorKey: 'violet');
    }
    if (norm.contains('assinatura') || norm.contains('servico')) {
      if (norm.contains('prestacao')) {
        return (iconId: 'work', colorKey: 'lime');
      }
      return (iconId: 'subscriptions', colorKey: 'violet');
    }
    if (norm == 'ia' || norm.contains('inteligencia artificial')) {
      return (iconId: 'auto_awesome', colorKey: 'violet');
    }
    if (norm.contains('site') || norm.contains('dominio')) {
      return (iconId: 'language', colorKey: 'violet');
    }
    if (norm.contains('software') || norm.contains('nuvem')) {
      return (iconId: 'cloud', colorKey: 'violet');
    }

    if (norm.contains('agua') || norm.contains('esgoto')) {
      return (iconId: 'water_drop', colorKey: 'sky');
    }
    if (norm.contains('eletric') || norm.contains('energia') || norm.contains('luz')) {
      return (iconId: 'bolt', colorKey: 'amber');
    }
    if (norm == 'gas' || norm.contains(' gas')) {
      return (iconId: 'local_fire_department', colorKey: 'orange');
    }
    if (norm.contains('internet') || norm.contains('wifi')) {
      return (iconId: 'wifi', colorKey: 'sky');
    }
    if (norm.contains('telefon') || norm.contains('celular')) {
      return (iconId: 'phone_android', colorKey: 'sky');
    }
    if (norm == 'tv' || norm.contains('televis')) {
      return (iconId: 'tv', colorKey: 'sky');
    }
    if (norm.contains('condominio') || norm.contains('aluguel')) {
      return (iconId: 'apartment', colorKey: 'sky');
    }
    if (norm.contains('casa') || norm.contains('moradia')) {
      return (iconId: 'home', colorKey: 'sky');
    }

    if (norm.contains('combustivel') || norm.contains('gasolina') || norm.contains('posto')) {
      return (iconId: 'local_gas_station', colorKey: 'blue');
    }
    if (norm.contains('estacionamento') || norm.contains('pedagio')) {
      return (iconId: 'local_parking', colorKey: 'blue');
    }
    if (norm.contains('metro') || norm.contains('onibus') || norm.contains('taxi') || norm.contains('uber')) {
      return (iconId: 'directions_bus', colorKey: 'blue');
    }
    if (norm.contains('transporte') || norm.contains('automove') || norm.contains('carro') || norm.contains('veiculo')) {
      return (iconId: 'directions_car', colorKey: 'blue');
    }

    if (norm.contains('viagem') || norm.contains('voo') || norm.contains('passagem')) {
      return (iconId: 'flight', colorKey: 'teal');
    }
    if (norm.contains('hotel') || norm.contains('hospedagem')) {
      return (iconId: 'hotel', colorKey: 'teal');
    }

    if (norm.contains('medicamento') || norm.contains('farmacia') || norm.contains('remedio')) {
      return (iconId: 'medication', colorKey: 'red');
    }
    if (norm.contains('terapeuta') || norm.contains('psicolog')) {
      return (iconId: 'psychology', colorKey: 'red');
    }
    if (norm.contains('saude') || norm.contains('medico') || norm.contains('hospital') || norm.contains('dentista')) {
      return (iconId: 'medical_services', colorKey: 'red');
    }

    if (norm.contains('academia') || norm.contains('fitness') || norm.contains('treino')) {
      return (iconId: 'fitness_center', colorKey: 'cyan');
    }
    if (norm.contains('cinema') || norm.contains('teatro') || norm.contains('filme')) {
      return (iconId: 'movie', colorKey: 'cyan');
    }
    if (norm.contains('game') || norm.contains('jogo') || norm.contains('lazer') || norm.contains('nintendo')) {
      return (iconId: 'sports_esports', colorKey: 'cyan');
    }
    if (norm.contains('musica')) {
      return (iconId: 'music_note', colorKey: 'cyan');
    }

    if (norm.contains('eletronico') || norm.contains('informatica')) {
      return (iconId: 'devices', colorKey: 'pink');
    }
    if (norm.contains('movei') || norm.contains('movel')) {
      return (iconId: 'chair', colorKey: 'pink');
    }
    if (norm.contains('eletrodomestico')) {
      return (iconId: 'kitchen', colorKey: 'pink');
    }
    if (norm.contains('roupa') || norm.contains('vestuario')) {
      return (iconId: 'checkroom', colorKey: 'pink');
    }
    if (norm.contains('compra')) {
      return (iconId: 'shopping_bag', colorKey: 'pink');
    }

    if (norm.contains('cuidado') || norm.contains('beleza') || norm.contains('salao')) {
      return (iconId: 'spa', colorKey: 'rose');
    }
    if (norm.contains('educa') || norm.contains('escola') || norm.contains('faculdade') || norm.contains('curso')) {
      return (iconId: 'school', colorKey: 'indigo');
    }
    if (norm.contains('livro')) {
      return (iconId: 'menu_book', colorKey: 'indigo');
    }
    if (norm.contains('familia') || norm.contains('filho')) {
      return (iconId: 'family_restroom', colorKey: 'amber');
    }
    if (norm.contains('pet') || norm.contains('cachorro') || norm.contains('gato') || norm.contains('veterin')) {
      return (iconId: 'pets', colorKey: 'amber');
    }
    if (norm.contains('festa')) {
      return (iconId: 'celebration', colorKey: 'purple');
    }
    if (norm.contains('presente')) {
      return (iconId: 'redeem', colorKey: 'purple');
    }
    if (norm.contains('doacao')) {
      return (iconId: 'volunteer_activism', colorKey: 'rose');
    }
    if (norm.contains('multa') || norm.contains('documenta')) {
      return (iconId: 'gavel', colorKey: 'slate');
    }
    if (norm.contains('imposto') || norm.contains('taxa') || norm.contains('iptu')) {
      return (iconId: 'account_balance', colorKey: 'slate');
    }
    if (norm.contains('seguro')) {
      return (iconId: 'shield', colorKey: 'blue');
    }

    // Receitas / Investimentos
    if (norm.contains('cashback')) {
      return (iconId: 'redeem', colorKey: 'emerald');
    }
    if (norm.contains('rendimento') || norm.contains('dividendo')) {
      return (iconId: 'show_chart', colorKey: 'emerald');
    }
    if (norm.contains('investimento')) {
      return type == 'Receita'
          ? (iconId: 'trending_up', colorKey: 'teal')
          : (iconId: 'savings', colorKey: 'teal');
    }
    if (norm.contains('outras rendas') || norm.contains('beneficio') || norm.contains('reembolso')) {
      return (iconId: 'account_balance_wallet', colorKey: 'lime');
    }
    if (norm.contains('renda') || norm.contains('salario') || norm.contains('pro-labore') || norm.contains('lucro')) {
      return (iconId: 'payments', colorKey: 'emerald');
    }
    if (norm.contains('venda')) {
      return (iconId: 'storefront', colorKey: 'amber');
    }

    return type == 'Receita'
        ? (iconId: 'trending_up', colorKey: 'emerald')
        : (iconId: 'label_outline', colorKey: 'slate');
  }

  static ResolvedCategoryVisual resolve({
    CategoryItem? category,
    CategoryItem? parentCategory,
    String? rawPath,
    String? fallbackType,
    bool isDark = false,
    bool isTransfer = false,
  }) {
    final effectivePath = rawPath ?? category?.path ?? '';
    final normPath = removeDiacritics(effectivePath).trim().toLowerCase();

    if (isTransfer ||
        effectivePath.startsWith('xfer:') ||
        normPath.contains('transferencia')) {
      final col = findColorByKey('sky')!.colorFor(isDark);
      return ResolvedCategoryVisual(
        icon: Icons.swap_horiz_rounded,
        color: col,
        iconId: 'swap_horiz',
        colorKey: 'sky',
      );
    }

    final effectiveType = category?.type ?? fallbackType ?? 'Despesa';

    // Subcategoria: herda do pai por padrão, podendo sobrescrever icon e/ou color
    final isSub = (category?.parent != null && category!.parent!.isNotEmpty) ||
        (category == null && effectivePath.contains(kCategorySep));

    if (isSub) {
      final parentName = category?.parent ??
          effectivePath.split(kCategorySep).first.trim();
      final parentVisual = resolve(
        category: parentCategory,
        rawPath: parentName,
        fallbackType: effectiveType,
        isDark: isDark,
      );

      final customIcon = findIconById(category?.icon);
      final customColor = findColorByKey(category?.color);

      return ResolvedCategoryVisual(
        icon: customIcon?.icon ?? parentVisual.icon,
        color: customColor?.colorFor(isDark) ?? parentVisual.color,
        iconId: customIcon?.id ?? parentVisual.iconId,
        colorKey: customColor?.key ?? parentVisual.colorKey,
        isInherited: customIcon == null && customColor == null,
        isCustomized: customIcon != null || customColor != null,
      );
    }

    // Categoria principal (ou caminho avulso sem pai)
    final nameForSuggest = category?.name ?? effectivePath;
    final suggestion = suggestForName(nameForSuggest, type: effectiveType);
    final explicitIcon = findIconById(category?.icon);
    final explicitColor = findColorByKey(category?.color);

    final resolvedIconItem =
        explicitIcon ?? findIconById(suggestion.iconId) ?? items.last;
    final resolvedColorOpt =
        explicitColor ?? findColorByKey(suggestion.colorKey) ?? colors.last;

    return ResolvedCategoryVisual(
      icon: resolvedIconItem.icon,
      color: resolvedColorOpt.colorFor(isDark),
      iconId: resolvedIconItem.id,
      colorKey: resolvedColorOpt.key,
      isInherited: false,
      isCustomized: explicitIcon != null || explicitColor != null,
    );
  }

  static ResolvedCategoryVisual resolveForStore(
    MoneyStore store,
    String catPath, {
    required bool isDark,
    String? fallbackType,
    bool isTransfer = false,
  }) {
    final cat = store.categoryByPath(catPath);
    CategoryItem? parentCat;
    if (cat?.parent != null && cat!.parent!.isNotEmpty) {
      parentCat = store.categoryByPath(cat.parent!);
    } else if (cat == null && catPath.contains(kCategorySep)) {
      final parentName = catPath.split(kCategorySep).first.trim();
      parentCat = store.categoryByPath(parentName);
    }
    return resolve(
      category: cat,
      parentCategory: parentCat,
      rawPath: catPath,
      fallbackType: fallbackType,
      isDark: isDark,
      isTransfer: isTransfer,
    );
  }
}

class CategoryIconBadge extends StatelessWidget {
  final MoneyStore? store;
  final CategoryItem? category;
  final CategoryItem? parentCategory;
  final String? categoryPath;
  final IconData? icon;
  final Color? color;
  final double size;
  final double? iconSize;
  final double? borderRadius;
  final bool isTransfer;
  final String? fallbackType;

  const CategoryIconBadge({
    super.key,
    this.store,
    this.category,
    this.parentCategory,
    this.categoryPath,
    this.icon,
    this.color,
    this.size = 20,
    this.iconSize,
    this.borderRadius,
    this.isTransfer = false,
    this.fallbackType,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    IconData effectiveIcon;
    Color effectiveColor;

    if (icon != null && color != null) {
      effectiveIcon = icon!;
      effectiveColor = color!;
    } else if (store != null && category == null && categoryPath != null) {
      final resolved = CategoryIconRegistry.resolveForStore(
        store!,
        categoryPath!,
        isDark: isDark,
        fallbackType: fallbackType,
        isTransfer: isTransfer,
      );
      effectiveIcon = icon ?? resolved.icon;
      effectiveColor = color ?? resolved.color;
    } else {
      CategoryItem? resolvedParent = parentCategory;
      if (resolvedParent == null &&
          store != null &&
          category?.parent != null &&
          category!.parent!.isNotEmpty) {
        resolvedParent = store!.categoryByPath(category!.parent!);
      }
      final resolved = CategoryIconRegistry.resolve(
        category: category,
        parentCategory: resolvedParent,
        rawPath: categoryPath,
        fallbackType: fallbackType,
        isDark: isDark,
        isTransfer: isTransfer,
      );
      effectiveIcon = icon ?? resolved.icon;
      effectiveColor = color ?? resolved.color;
    }

    final radius = borderRadius ?? (size * 0.28).clamp(4.0, 10.0);
    final effectiveIconSize = iconSize ?? (size * 0.62).clamp(11.0, 28.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: effectiveColor.withValues(alpha: isDark ? 0.28 : 0.20),
          width: 0.75,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        effectiveIcon,
        size: effectiveIconSize,
        color: effectiveColor == colors.textMuted ? colors.textSecondary : effectiveColor,
      ),
    );
  }
}
