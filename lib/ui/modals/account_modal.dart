import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/bank_logo_registry.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

Future<void> showAccountModal(
  BuildContext context,
  MoneyStore store, {
  Account? editingAccount,
}) async {
  await showDialog(
    context: context,
    builder: (ctx) => _AccountDialog(
      store: store,
      editingAccount: editingAccount,
    ),
  );
}

class _AccountDialog extends StatefulWidget {
  final MoneyStore store;
  final Account? editingAccount;

  const _AccountDialog({
    required this.store,
    this.editingAccount,
  });

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _openingCtrl;
  late final TextEditingController _businessCtrl;
  late final TextEditingController _bankCodeCtrl;
  late final TextEditingController _agencyCtrl;
  late final TextEditingController _accountNumberCtrl;
  late final TextEditingController _minBalanceCtrl;
  late final TextEditingController _commentsCtrl;
  late String _type;
  late int _closeDay;
  late int _dueDay;
  late String _payAccId;
  late bool _inactive;
  late bool _favorite;
  String? _logo;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final acc = widget.editingAccount;
    _logo = acc?.logo;
    _nameCtrl = TextEditingController(text: acc?.name ?? '');
    _openingCtrl = TextEditingController(
      text: acc != null ? formatInputCents(acc.opening) : '0,00',
    );
    _businessCtrl = TextEditingController(text: acc?.business ?? '');
    _bankCodeCtrl = TextEditingController(text: acc?.bankCode ?? '');
    _agencyCtrl = TextEditingController(text: acc?.agency ?? '');
    _accountNumberCtrl = TextEditingController(text: acc?.accountNumber ?? '');
    _minBalanceCtrl = TextEditingController(
      text: acc?.minBalance != null ? formatInputCents(acc!.minBalance!) : '',
    );
    _commentsCtrl = TextEditingController(text: acc?.comments ?? '');
    _type = acc?.type ?? 'Corrente';
    _closeDay = acc?.card?.closeDay ?? 1;
    _dueDay = acc?.card?.dueDay ?? 10;

    final nonCardAccounts = widget.store.db.accounts
        .where((a) => a.id != acc?.id && a.type != kCardType)
        .toList();
    final fallbackPay = nonCardAccounts.isNotEmpty
        ? nonCardAccounts.first.id
        : (widget.store.db.accounts
                .where((a) => a.id != acc?.id)
                .firstOrNull
                ?.id ??
            '');
    _payAccId = acc?.card?.pay ?? fallbackPay;
    _inactive = acc?.isInactive ?? false;
    _favorite = acc?.isFavorite ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _openingCtrl.dispose();
    _businessCtrl.dispose();
    _bankCodeCtrl.dispose();
    _agencyCtrl.dispose();
    _accountNumberCtrl.dispose();
    _minBalanceCtrl.dispose();
    _commentsCtrl.dispose();
    super.dispose();
  }

  void _handleSave() {
    final rawOpening = _openingCtrl.text.trim();
    final isNeg = rawOpening.startsWith('-');
    final parsedAbs = parseCents(rawOpening) ?? 0;
    final openingCents = isNeg ? -parsedAbs.abs() : parsedAbs;

    final rawMinBal = _minBalanceCtrl.text.trim();
    final int? minBalanceCents = rawMinBal.isEmpty
        ? null
        : (rawMinBal.startsWith('-')
            ? -(parseCents(rawMinBal)?.abs() ?? 0)
            : parseCents(rawMinBal));

    final err = widget.store.saveAccount(
      editingId: widget.editingAccount?.id,
      name: _nameCtrl.text,
      type: _type,
      openingCents: openingCents,
      closeDay: _closeDay,
      dueDay: _dueDay,
      payAccId: _payAccId,
      inactive: _inactive,
      favorite: _favorite,
      business: _businessCtrl.text,
      bankCode: _bankCodeCtrl.text,
      agency: _agencyCtrl.text,
      accountNumber: _accountNumberCtrl.text,
      comments: _commentsCtrl.text,
      minBalance: minBalanceCents,
      logo: _logo,
    );

    if (err != null) {
      setState(() => _errorText = err);
      return;
    }
    Navigator.of(context).pop();
  }

  void _openLogoPicker(BuildContext context) {
    final colors =
        OpenMoneyColors(Theme.of(context).brightness == Brightness.dark);
    showDialog(
      context: context,
      builder: (ctx) {
        String search = '';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = BankLogoRegistry.items.where((i) {
              if (search.trim().isEmpty) return true;
              return i.name.toLowerCase().contains(search.toLowerCase());
            }).toList();

            return AlertDialog(
              backgroundColor: colors.bgPrimary,
              title: const Text('Escolher Logo do Banco'),
              content: SizedBox(
                width: 420,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Buscar banco...',
                        prefixIcon: Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) => setModalState(() => search = val),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.95,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, idx) {
                          final item = filtered[idx];
                          final isSelected = _logo == item.filename;
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setState(() => _logo = item.filename);
                              Navigator.of(ctx).pop();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colors.accent.withValues(alpha: 0.18)
                                    : colors.surfaceGlass,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? colors.accent
                                      : colors.borderGlass,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.asset(
                                      item.assetPath,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.name,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? colors.accent
                                          : colors.textPrimary,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleDeleteAttempt() {
    final acc = widget.editingAccount;
    if (acc == null) return;

    final txCount = widget.store.transactionCount(acc.id);
    if (txCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.amber),
              SizedBox(width: 10),
              Expanded(child: Text('Proteção de Integridade Contábil')),
            ],
          ),
          content: Text(
            'A conta "${acc.name}" possui $txCount lançamento(s) vinculado(s) e não pode ser excluída fisicamente para preservar o histórico e os balanços patrimoniais.\n\nVocê pode desativá-la para arquivá-la da barra lateral mantendo 100% dos relatórios intactos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.archive_outlined, size: 18),
              label: const Text('Desativar Conta com 1 Clique'),
              onPressed: () {
                if (!acc.isInactive) {
                  widget.store.toggleAccountInactive(acc.id);
                }
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      );
      return;
    }

    if (widget.store.db.accounts.length <= 1) {
      setState(() =>
          _errorText = 'O sistema exige pelo menos 1 conta cadastrada.');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Conta Definitivamente'),
        content: Text(
          'Confirma a exclusão definitiva da conta "${acc.name}" (0 lançamentos)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              widget.store.deleteAccount(acc.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Excluir Conta'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isCard = _type == kCardType;
    final payCandidates = widget.store.db.accounts
        .where((a) => a.id != widget.editingAccount?.id)
        .toList();

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.borderGlass),
      ),
      title: Text(
        widget.editingAccount == null ? 'Nova Conta' : 'Editar Conta',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: colors.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorText != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colors.expense.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.expense),
                  ),
                  child: Text(
                    _errorText!,
                    style: TextStyle(color: colors.expense, fontSize: 13),
                  ),
                ),
              ],
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nome da Conta',
                  hintText: 'Ex.: Itaú Uniclass, Nubank Ultravioleta...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // Bloco de Logo do Banco
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.surfaceGlass,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.borderGlass),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.borderGlass.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _logo != null
                          ? Padding(
                              padding: const EdgeInsets.all(2.5),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.asset(
                                  BankLogoRegistry.findByIdOrFilename(_logo)
                                          ?.assetPath ??
                                      'logo/$_logo',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(
                                    _type == kCardType
                                        ? Icons.credit_card
                                        : Icons.account_balance_wallet_outlined,
                                    color: colors.accent,
                                    size: 20,
                                  ),
                                ),
                              ),
                            )
                          : Icon(
                              _type == kCardType
                                  ? Icons.credit_card
                                  : Icons.account_balance_wallet_outlined,
                              color: colors.accent,
                              size: 20,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _logo != null
                                ? (BankLogoRegistry.findByIdOrFilename(_logo)
                                        ?.name ??
                                    _logo!)
                                : 'Ícone Padrão (${_type == kCardType ? "Cartão" : "Carteira"})',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _logo != null
                                ? 'Logo pré-definido selecionado'
                                : 'Nenhum logo associado',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.account_balance, size: 14),
                      label: Text(_logo != null ? 'Trocar...' : 'Escolher...'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 11.5),
                      ),
                      onPressed: () => _openLogoPicker(context),
                    ),
                    if (_logo != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Remover Logo (Usar Padrão)',
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => setState(() => _logo = null),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _businessCtrl,
                decoration: InputDecoration(
                  labelText: 'Negócio / Entidade (Agrupador)',
                  hintText: 'Ex.: PF, PJ, Consultoria...',
                  border: const OutlineInputBorder(),
                  prefixIcon:
                      const Icon(Icons.business_outlined, size: 20),
                  suffixIcon: _businessCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _businessCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              Builder(builder: (context) {
                final suggestions = {
                  'PF',
                  'PJ',
                  ...widget.store.allBusinesses
                }.toList();
                return Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: suggestions.map((tag) {
                    final isSelected =
                        _businessCtrl.text.trim().toLowerCase() ==
                            tag.toLowerCase();
                    return ActionChip(
                      label: Text(tag),
                      avatar: isSelected
                          ? const Icon(Icons.check, size: 14)
                          : null,
                      backgroundColor: isSelected
                          ? colors.accent.withValues(alpha: 0.18)
                          : null,
                      side: isSelected
                          ? BorderSide(color: colors.accent)
                          : null,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? colors.accent : null,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      onPressed: () {
                        setState(() {
                          if (isSelected) {
                            _businessCtrl.clear();
                          } else {
                            _businessCtrl.text = tag;
                          }
                        });
                      },
                    );
                  }).toList(),
                );
              }),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Conta',
                  border: OutlineInputBorder(),
                ),
                items: kAccountTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _type = v);
                },
              ),
              const SizedBox(height: 14),
              if (!isCard)
                TextField(
                  controller: _openingCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Saldo Inicial de Abertura (R\$)',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (isCard) ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _closeDay,
                        decoration: const InputDecoration(
                          labelText: 'Dia de Fechamento',
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(
                          31,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text('Dia ${i + 1}'),
                          ),
                        ),
                        onChanged: (v) {
                          if (v != null) setState(() => _closeDay = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _dueDay,
                        decoration: const InputDecoration(
                          labelText: 'Dia de Vencimento',
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(
                          31,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text('Dia ${i + 1}'),
                          ),
                        ),
                        onChanged: (v) {
                          if (v != null) setState(() => _dueDay = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (payCandidates.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue:
                        payCandidates.any((a) => a.id == _payAccId)
                            ? _payAccId
                            : payCandidates.first.id,
                    decoration: const InputDecoration(
                      labelText: 'Conta Padrão para Débito da Fatura',
                      border: OutlineInputBorder(),
                    ),
                    items: payCandidates
                        .map((a) =>
                            DropdownMenuItem(value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _payAccId = v);
                    },
                  ),
              ],
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 6),
              Text(
                'DADOS BANCÁRIOS & CONTROLE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _bankCodeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Cód. Banco',
                        hintText: 'Ex: 001, 260',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _agencyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Agência',
                        hintText: 'Ex: 0001',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: TextField(
                      controller: _accountNumberCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nº Conta',
                        hintText: 'Ex: 12345-6',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _minBalanceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Saldo Mínimo / Limite da Conta (R\$)',
                  hintText: '0,00',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _commentsCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Comentários / Observações',
                  hintText: 'Anotações sobre a conta, chave PIX, gerente...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Favoritar Conta'),
                subtitle: const Text('Fixa no topo da barra lateral'),
                value: _favorite,
                onChanged: (v) => setState(() => _favorite = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Conta Inativa (Arquivada)'),
                subtitle: const Text(
                    'Oculta de novos lançamentos preservando o histórico'),
                value: _inactive,
                onChanged: (v) => setState(() => _inactive = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.editingAccount != null)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: colors.expense),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Excluir'),
            onPressed: _handleDeleteAttempt,
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Salvar'),
          onPressed: _handleSave,
        ),
      ],
    );
  }
}
