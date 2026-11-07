import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/cloud_sync_service.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

Future<void> showCloudAccountModal(
  BuildContext context,
  MoneyStore store,
) async {
  await showDialog(
    context: context,
    builder: (ctx) => _CloudAccountDialog(store: store),
  );
}

class _CloudAccountDialog extends StatefulWidget {
  final MoneyStore store;

  const _CloudAccountDialog({required this.store});

  @override
  State<_CloudAccountDialog> createState() => _CloudAccountDialogState();
}

class _CloudAccountDialogState extends State<_CloudAccountDialog> {
  final CloudSyncService _cloud = CloudSyncService.instance;

  bool _isRegisterMode = false;
  bool _isForgotMode = false;
  int _forgotStep = 1;
  bool _isBusy = false;
  bool _showPasswordChange = false;
  bool _addingAnotherAccount = false;
  bool _registerWithBlankBase = true;
  String? _statusMsg;
  bool _isError = false;
  List<CloudBackupInfo> _cloudBackups = const [];
  bool _loadingBackups = false;

  late final TextEditingController _serverCtrl;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _resetCodeCtrl = TextEditingController();
  final _newForgotPassCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();
  final _curPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initialServer = _cloud.apiBaseUrl.isNotEmpty
        ? _cloud.apiBaseUrl
        : CloudSyncService.defaultApiBaseUrl;
    _serverCtrl = TextEditingController(text: initialServer);
    if (_cloud.isAuthenticated) {
      _loadCloudBackups();
    }
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _resetCodeCtrl.dispose();
    _newForgotPassCtrl.dispose();
    _inviteCtrl.dispose();
    _curPassCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleRequestResetCode() async {
    final cleanEmail = _emailCtrl.text.trim();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      setState(() {
        _isError = true;
        _statusMsg = 'Informe um e-mail válido para receber o código.';
      });
      return;
    }
    setState(() {
      _isBusy = true;
      _statusMsg = null;
      _isError = false;
    });
    try {
      final res = await _cloud.requestPasswordResetCode(
        email: cleanEmail,
        customApiUrl: _serverCtrl.text.trim().isEmpty ? null : _serverCtrl.text.trim(),
      );
      if (mounted) {
        if (res.ok) {
          setState(() {
            _forgotStep = 2;
            _statusMsg = res.message ?? 'Código enviado para seu e-mail!';
            _isError = false;
          });
        } else {
          setState(() {
            _isError = true;
            _statusMsg = res.error;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _handleResetPasswordAndLogin() async {
    final cleanEmail = _emailCtrl.text.trim();
    final cleanCode = _resetCodeCtrl.text.trim();
    final newPass = _newForgotPassCtrl.text;

    if (cleanCode.isEmpty) {
      setState(() {
        _isError = true;
        _statusMsg = 'Informe o código de 6 dígitos recebido por e-mail.';
      });
      return;
    }
    if (newPass.length < 8) {
      setState(() {
        _isError = true;
        _statusMsg = 'A nova senha deve ter no mínimo 8 caracteres.';
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMsg = null;
      _isError = false;
    });

    try {
      final res = await _cloud.resetPasswordWithCode(
        email: cleanEmail,
        code: cleanCode,
        newPassword: newPass,
        customApiUrl: _serverCtrl.text.trim().isEmpty ? null : _serverCtrl.text.trim(),
      );
      if (mounted) {
        if (res.ok) {
          widget.store.saveCloudSessionToConfig();
          await widget.store.syncFromCloud();
          await _loadCloudBackups();
          setState(() {
            _isForgotMode = false;
            _forgotStep = 1;
            _addingAnotherAccount = false;
            _isError = false;
            _statusMsg = res.message ?? '✓ Senha redefinida e sincronizado!';
          });
        } else {
          setState(() {
            _isError = true;
            _statusMsg = res.error;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _loadCloudBackups() async {
    setState(() => _loadingBackups = true);
    final list = await _cloud.listCloudBackups();
    if (mounted) {
      setState(() {
        _cloudBackups = list;
        _loadingBackups = false;
      });
    }
  }

  Future<void> _handleAuth() async {
    setState(() {
      _isBusy = true;
      _statusMsg = null;
      _isError = false;
    });

    final serverUrl = _serverCtrl.text.trim();
    if (_isRegisterMode) {
      final res = await _cloud.register(
        name: _nameCtrl.text,
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        inviteCode: _inviteCtrl.text,
        customApiUrl: serverUrl,
      );
      if (!mounted) return;
      if (res.ok) {
        widget.store.saveCloudSessionToConfig();
        if (_registerWithBlankBase) {
          await widget.store.resetToBlankDatabaseAndSync(pushToCloud: true);
        } else {
          await widget.store.pushLocalToCloud(force: true);
        }
        await _loadCloudBackups();
        setState(() {
          _addingAnotherAccount = false;
          _isError = false;
          _statusMsg = _registerWithBlankBase
              ? '✓ Nova conta criada com base em branco pronta para uso!'
              : '✓ Conta criada e base openmoney.json sincronizada na nuvem!';
        });
      } else {
        setState(() {
          _isError = true;
          _statusMsg = res.error;
        });
      }
    } else {
      final res = await _cloud.login(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        customApiUrl: serverUrl,
      );
      if (!mounted) return;
      if (res.ok) {
        widget.store.saveCloudSessionToConfig();
        await widget.store.syncFromCloud();
        await _loadCloudBackups();
        setState(() {
          _addingAnotherAccount = false;
          _isError = false;
          _statusMsg = '✓ Conectado em ${_cloud.userEmail} e sincronizado!';
        });
      } else {
        setState(() {
          _isError = true;
          _statusMsg = res.error;
        });
      }
    }

    if (mounted) {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _handleSwitchAccount(SavedCloudAccount acc) async {
    if (acc.userId == _cloud.userId &&
        _cloud.isAuthenticated &&
        _cloud.state == CloudSyncState.synced) {
      return;
    }

    widget.store.cancelPendingSave();

    final prevAccount = _cloud.isAuthenticated
        ? SavedCloudAccount(
            userId: _cloud.userId,
            email: _cloud.userEmail,
            name: _cloud.userName,
            authToken: _cloud.authToken,
            apiBaseUrl: _cloud.apiBaseUrl,
            revision: _cloud.revision,
            lastSyncedAt: _cloud.lastSyncedAt?.toIso8601String(),
          )
        : null;

    setState(() {
      _isBusy = true;
      _statusMsg = 'Alternando para ${acc.email} e carregando base...';
      _isError = false;
    });

    _cloud.switchToSavedAccount(acc);
    if (!mounted) return;
    final synced = await widget.store.syncFromCloud();
    final errMsg = _cloud.lastError;

    if (!synced) {
      // Se falhar ao carregar a nova conta, restaura a conta anterior para manter consistência com a base em tela
      if (prevAccount != null && prevAccount.userId != acc.userId) {
        _cloud.switchToSavedAccount(prevAccount);
        widget.store.saveCloudSessionToConfig();
      }
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _isError = true;
        _statusMsg = errMsg ??
            'Não foi possível carregar a base de ${acc.email}. Tente novamente ou reconecte com sua senha.';
      });
      return;
    }

    widget.store.saveCloudSessionToConfig();
    await _loadCloudBackups();
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _addingAnotherAccount = false;
      _isError = false;
      _statusMsg = '✓ Conta alternada para ${acc.email} (r${_cloud.revision})!';
    });
  }

  Future<void> _confirmCreateNewBlankDatabase(OpenMoneyColors colors) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.borderGlass),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Atenção: Criar Nova Base em Branco',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '⚠️ CUIDADO: Ao criar uma nova base em branco nesta conta (${_cloud.userEmail.isNotEmpty ? _cloud.userEmail : "atual"}), os lançamentos, contas e cartões atuais serão substituídos por uma estrutura limpa (Schema v7).',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textPrimary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '💡 Dica: Se você deseja manter sua base atual intacta e criar uma segunda base separada, use o botão "+ Criar Nova Conta / Base" com outro e-mail ou exporte um backup .json antes de prosseguir.',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () async {
                  await widget.store.exportDatabaseFileWithPicker();
                },
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Exportar Backup .json Antes de Continuar'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.note_add_outlined, size: 16),
            label: const Text('Sim, Criar Base em Branco'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isBusy = true;
      _isError = false;
      _statusMsg = 'Criando nova base em branco e sincronizando...';
    });

    await widget.store.resetToBlankDatabaseAndSync(pushToCloud: true);
    await _loadCloudBackups();
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _isError = false;
      _statusMsg =
          '✓ Nova base em branco criada e sincronizada com sucesso!';
    });
  }

  Future<void> _confirmDeleteExistingDatabase(OpenMoneyColors colors) async {
    final confirmCtrl = TextEditingController();
    bool deleteFullAccount = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isTypedValid =
              confirmCtrl.text.trim().toUpperCase() == 'EXCLUIR';
          return AlertDialog(
            backgroundColor: colors.bgSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colors.accentRed.withValues(alpha: 0.6),
                width: 1.4,
              ),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.dangerous_rounded,
                  color: colors.accentRed,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Atenção Crítica: Excluir Base Existente',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: colors.accentRed,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.accentRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colors.accentRed.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '🚨 AVISO IRREVERSÍVEL: Esta ação apagará permanentemente os dados financeiros e os backups diários na nuvem da conta ${_cloud.userEmail}.\n\nRecomendamos fortemente exportar uma cópia do seu arquivo openmoney.json antes de prosseguir.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                        height: 1.38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await widget.store.exportDatabaseFileWithPicker();
                    },
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Fazer Backup (.json) Agora por Segurança'),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: deleteFullAccount,
                    activeColor: colors.accentRed,
                    onChanged: (val) =>
                        setDialogState(() => deleteFullAccount = val ?? false),
                    title: Text(
                      'Excluir também o meu login/conta de usuário da nuvem',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      deleteFullAccount
                          ? 'Sua conta e base serão removidas por completo do servidor.'
                          : 'Apenas a base e os backups serão apagados; seu login continuará ativo com uma base zerada.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Para confirmar, digite EXCLUIR no campo abaixo:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: confirmCtrl,
                    onChanged: (_) => setDialogState(() {}),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Digite EXCLUIR',
                      isDense: true,
                      filled: true,
                      fillColor: colors.bgPrimary.withValues(alpha: 0.65),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(
                  'Cancelar',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accentRed,
                  foregroundColor: Colors.white,
                ),
                onPressed: isTypedValid
                    ? () => Navigator.of(ctx).pop({
                          'confirm': confirmCtrl.text.trim(),
                          'deleteFullAccount': deleteFullAccount,
                        })
                    : null,
                icon: const Icon(Icons.delete_forever_rounded, size: 17),
                label: Text(
                  deleteFullAccount
                      ? 'Excluir Conta e Base'
                      : 'Excluir Base da Nuvem',
                ),
              ),
            ],
          );
        },
      ),
    );

    confirmCtrl.dispose();
    if (result == null || !mounted) return;

    setState(() {
      _isBusy = true;
      _isError = false;
      _statusMsg = 'Excluindo base na nuvem...';
    });

    final fullAcc = result['deleteFullAccount'] == true;
    final res = await _cloud.deleteCloudDatabase(
      confirmText: result['confirm'] as String,
      deleteFullAccount: fullAcc,
    );

    if (!mounted) return;
    if (res.ok) {
      await widget.store.resetToBlankDatabaseAndSync(pushToCloud: false);
      widget.store.saveCloudSessionToConfig();
      if (!fullAcc) {
        await _loadCloudBackups();
      }
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _isError = false;
        _statusMsg = fullAcc
            ? '✓ Conta e base excluídas permanentemente.'
            : '✓ Base existente e backups excluídos! Conta reiniciada com base limpa.';
      });
      if (fullAcc && kIsWeb) {
        Navigator.of(context).pop();
      }
    } else {
      setState(() {
        _isBusy = false;
        _isError = true;
        _statusMsg = res.error ?? 'Falha ao excluir base.';
      });
    }
  }

  Future<void> _handlePullFromCloud() async {
    setState(() {
      _isBusy = true;
      _statusMsg = null;
    });
    final ok = await widget.store.syncFromCloud();
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _isError = !ok;
      _statusMsg = ok
          ? '✓ Base atualizada a partir da nuvem (Revisão r${_cloud.revision}).'
          : (_cloud.lastError ?? 'Falha ao buscar dados da nuvem.');
    });
  }

  Future<void> _handlePushToCloud() async {
    setState(() {
      _isBusy = true;
      _statusMsg = null;
    });
    final ok = await widget.store.pushLocalToCloud(force: true);
    await _loadCloudBackups();
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _isError = !ok;
      _statusMsg = ok
          ? '✓ Base enviada e criptografada na nuvem (Revisão r${_cloud.revision}).'
          : (_cloud.lastError ?? 'Falha ao enviar base para a nuvem.');
    });
  }

  Future<void> _handleChangePassword() async {
    setState(() {
      _isBusy = true;
      _statusMsg = null;
    });
    final res = await _cloud.changePassword(
      currentPassword: _curPassCtrl.text,
      newPassword: _newPassCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _isError = !res.ok;
      _statusMsg = res.ok ? '✓ Senha alterada com sucesso!' : res.error;
      if (res.ok) {
        _showPasswordChange = false;
        _curPassCtrl.clear();
        _newPassCtrl.clear();
      }
    });
  }

  Future<void> _handleRestoreBackup(CloudBackupInfo b) async {
    setState(() {
      _isBusy = true;
      _statusMsg = null;
    });
    final snap = await _cloud.restoreCloudBackup(b.id);
    if (snap != null && snap.payload.isNotEmpty) {
      await widget.store.syncFromCloud();
      if (mounted) {
        setState(() {
          _isBusy = false;
          _isError = false;
          _statusMsg =
              '✓ Backup do dia ${b.backupDate} restaurado com sucesso!';
        });
      }
    } else if (mounted) {
      setState(() {
        _isBusy = false;
        _isError = true;
        _statusMsg = 'Não foi possível restaurar o backup selecionado.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = OpenMoneyColors(widget.store.isDarkMode);

    return AnimatedBuilder(
      animation: _cloud,
      builder: (context, _) {
        return Dialog(
          backgroundColor: colors.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: colors.borderGlass),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 740),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cabeçalho com Logo Oficial da Aplicação
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.asset(
                          'logo/openmoney_app_icon.png',
                          width: 40,
                          height: 40,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OpenMoney Cloud & Sincronização',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: colors.textPrimary,
                              ),
                            ),
                            Text(
                              _cloud.isAuthenticated
                                  ? 'Conectado como ${_cloud.userEmail} • ${_cloud.statusLabel}'
                                  : 'Sincronize e alterne entre múltiplas contas e bases openmoney.json',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.help_outline_rounded,
                          color: colors.accentBlue,
                          size: 20,
                        ),
                        tooltip: 'Guia de Ajuda da Sincronização',
                        onPressed: () => showCloudSyncHelpModal(context, colors),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: colors.textSecondary),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: colors.borderGlass, height: 1),
                  const SizedBox(height: 16),

                  Flexible(
                    child: SingleChildScrollView(
                      child: _isForgotMode
                          ? _buildDisconnectedBody(colors)
                          : (_cloud.isAuthenticated && !_addingAnotherAccount)
                              ? _buildConnectedBody(colors)
                              : _buildDisconnectedBody(colors),
                    ),
                  ),

                  if (_statusMsg != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (_isError
                                ? colors.accentRed
                                : colors.accentGreen)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (_isError
                                  ? colors.accentRed
                                  : colors.accentGreen)
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _statusMsg!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _isError
                                  ? colors.accentRed
                                  : colors.accentGreen,
                            ),
                          ),
                          if (_statusMsg!.contains('Sessão expirada') ||
                              _statusMsg!.contains('não autenticada')) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () {
                                    final currentEmail = _cloud.userEmail;
                                    _cloud.logout();
                                    setState(() {
                                      _emailCtrl.text = currentEmail;
                                      _passwordCtrl.clear();
                                      _isRegisterMode = false;
                                      _isForgotMode = false;
                                      _addingAnotherAccount = false;
                                      _statusMsg =
                                          'Digite sua nova senha para reconectar em $currentEmail';
                                      _isError = false;
                                    });
                                  },
                                  icon: const Icon(Icons.login, size: 14),
                                  label: const Text(
                                    'Reconectar com Senha',
                                    style: TextStyle(fontSize: 11.5),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () {
                                    final currentEmail = _cloud.userEmail;
                                    setState(() {
                                      _emailCtrl.text = currentEmail;
                                      _isForgotMode = true;
                                      _forgotStep = 1;
                                      _statusMsg = null;
                                      _isError = false;
                                      _resetCodeCtrl.clear();
                                      _newForgotPassCtrl.clear();
                                    });
                                  },
                                  icon: const Icon(Icons.mail_outline, size: 14),
                                  label: const Text(
                                    'Recuperar Senha por E-mail',
                                    style: TextStyle(fontSize: 11.5),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectedBody(OpenMoneyColors colors) {
    final savedAccounts = _cloud.savedAccounts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card de Resumo da Conta Ativa
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.bgPrimary.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.borderGlass),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colors.accentBlue.withValues(alpha: 0.2),
                child: Text(
                  (_cloud.userName.isNotEmpty
                          ? _cloud.userName[0]
                          : (_cloud.userEmail.isNotEmpty
                              ? _cloud.userEmail[0]
                              : 'U'))
                      .toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: colors.accentBlue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _cloud.userName.isNotEmpty
                                ? _cloud.userName
                                : _cloud.userEmail,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accentGreen.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'ATIVA',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: colors.accentGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${_cloud.userEmail} • Revisão na nuvem: r${_cloud.revision}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  _cloud.logout();
                  widget.store.saveCloudSessionToConfig();
                  if (kIsWeb && _cloud.savedAccounts.isEmpty) {
                    Navigator.of(context).pop();
                  }
                },
                icon: Icon(
                  Icons.logout,
                  size: 16,
                  color: colors.accentRed,
                ),
                label: Text(
                  'Sair',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.accentRed,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Seção: Alternar entre Contas / Bases Salvas
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.bgPrimary.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.borderGlass),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.switch_account_rounded,
                        size: 16,
                        color: colors.accentBlue,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Alternar entre Contas e Bases (${savedAccounts.length})',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _isBusy
                            ? null
                            : () {
                                setState(() {
                                  _emailCtrl.clear();
                                  _passwordCtrl.clear();
                                  _isRegisterMode = false;
                                  _addingAnotherAccount = true;
                                  _statusMsg = null;
                                });
                              },
                        icon: const Icon(Icons.login, size: 14),
                        label: const Text(
                          'Outra Conta',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _isBusy
                            ? null
                            : () {
                                setState(() {
                                  _nameCtrl.clear();
                                  _emailCtrl.clear();
                                  _passwordCtrl.clear();
                                  _registerWithBlankBase = true;
                                  _isRegisterMode = true;
                                  _addingAnotherAccount = true;
                                  _statusMsg = null;
                                });
                              },
                        icon: const Icon(Icons.person_add_alt_1, size: 14),
                        label: const Text(
                          '+ Nova Conta/Base',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (savedAccounts.length > 1) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 130),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: savedAccounts.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: colors.borderGlass, height: 1),
                    itemBuilder: (ctx, idx) {
                      final acc = savedAccounts[idx];
                      final isCurrent = acc.userId == _cloud.userId ||
                          acc.email.toLowerCase() ==
                              _cloud.userEmail.toLowerCase();
                      return ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 6),
                        leading: Icon(
                          isCurrent
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 17,
                          color: isCurrent
                              ? colors.accentGreen
                              : colors.textSecondary,
                        ),
                        title: Text(
                          acc.name.isNotEmpty
                              ? '${acc.name} (${acc.email})'
                              : acc.email,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          'Revisão r${acc.revision}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isCurrent)
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: _isBusy
                                    ? null
                                    : () => _handleSwitchAccount(acc),
                                child: const Text(
                                  'Alternar',
                                  style: TextStyle(fontSize: 11.5),
                                ),
                              )
                            else
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  'Em uso',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: colors.accentGreen,
                                  ),
                                ),
                              ),
                            if (!isCurrent)
                              IconButton(
                                icon: Icon(
                                  Icons.close,
                                  size: 15,
                                  color: colors.textSecondary,
                                ),
                                tooltip: 'Remover atalho desta conta',
                                onPressed: _isBusy
                                    ? null
                                    : () => _cloud.removeSavedAccount(
                                          acc.userId,
                                        ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  'Use "Outra Conta" ou "+ Nova Conta/Base" acima para conectar múltiplos e-mails e alternar entre suas bases com 1 clique.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Botões de Sincronização e Import/Export .json
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isBusy ? null : _handlePullFromCloud,
                icon: const Icon(Icons.cloud_download_outlined, size: 17),
                label: const Text('Baixar da Nuvem'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accentBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isBusy ? null : _handlePushToCloud,
                icon: const Icon(Icons.cloud_upload_outlined, size: 17),
                label: const Text('Enviar para Nuvem'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isBusy
                    ? null
                    : () async {
                        final path = await widget.store
                            .exportDatabaseFileWithPicker();
                        if (path != null && mounted) {
                          setState(() {
                            _isError = false;
                            _statusMsg =
                                '✓ Arquivo openmoney.json exportado com sucesso!';
                          });
                        }
                      },
                icon: const Icon(Icons.download_outlined, size: 17),
                label: const Text('Exportar .json'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isBusy
                    ? null
                    : () async {
                        setState(() {
                          _isBusy = true;
                          _statusMsg =
                              'Importando e sincronizando base com a nuvem...';
                          _isError = false;
                        });
                        final ok = await widget.store
                            .importDatabaseFileWithPicker();
                        await _loadCloudBackups();
                        if (mounted) {
                          final syncOk =
                              ok && _cloud.state == CloudSyncState.synced;
                          setState(() {
                            _isBusy = false;
                            _isError = !syncOk;
                            _statusMsg = syncOk
                                ? '✓ Base openmoney.json importada e sincronizada na nuvem (r${_cloud.revision})!'
                                : (ok
                                    ? (_cloud.lastError ??
                                        'Base carregada localmente, mas falhou ao enviar para nuvem.')
                                    : 'Importação cancelada ou arquivo inválido.');
                          });
                        }
                      },
                icon: const Icon(Icons.upload_file_outlined, size: 17),
                label: const Text('Importar .json'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Seção: Gerenciar Base (Criar Nova Base em Branco / Excluir Base Existente com Avisos de Cuidado)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.accentRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colors.accentRed.withValues(alpha: 0.28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.orange.shade400,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Gerenciamento da Base Atual (Operações com Aviso de Segurança)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange.shade400,
                        side: BorderSide(
                          color: Colors.orange.withValues(alpha: 0.5),
                        ),
                      ),
                      onPressed: _isBusy
                          ? null
                          : () => _confirmCreateNewBlankDatabase(colors),
                      icon: const Icon(Icons.note_add_outlined, size: 16),
                      label: const Text(
                        'Criar Nova Base Limpa',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.accentRed,
                        side: BorderSide(
                          color: colors.accentRed.withValues(alpha: 0.55),
                        ),
                      ),
                      onPressed: _isBusy
                          ? null
                          : () => _confirmDeleteExistingDatabase(colors),
                      icon: const Icon(Icons.delete_forever_outlined, size: 16),
                      label: const Text(
                        'Excluir Base Existente...',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Seção de Backups Diários na Nuvem
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Backups Diários na Nuvem (Isolados por Usuário)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.refresh,
                size: 16,
                color: colors.textSecondary,
              ),
              tooltip: 'Atualizar lista de backups',
              onPressed: _loadingBackups ? null : _loadCloudBackups,
            ),
          ],
        ),
        Container(
          constraints: const BoxConstraints(maxHeight: 150),
          decoration: BoxDecoration(
            color: colors.bgPrimary.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.borderGlass),
          ),
          child: _loadingBackups
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _cloudBackups.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        'O primeiro backup diário na nuvem é criado automaticamente ao salvar sua base.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _cloudBackups.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: colors.borderGlass, height: 1),
                      itemBuilder: (ctx, i) {
                        final b = _cloudBackups[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.history_rounded,
                            size: 18,
                            color: colors.accentBlue,
                          ),
                          title: Text(
                            'Snapshot ${b.backupDate} (r${b.revision})',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            b.formattedSize,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                          trailing: TextButton(
                            onPressed: _isBusy
                                ? null
                                : () => _handleRestoreBackup(b),
                            child: const Text('Restaurar'),
                          ),
                        );
                      },
                    ),
        ),

        const SizedBox(height: 10),

        // Alteração de Senha
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _showPasswordChange = !_showPasswordChange),
            icon: Icon(
              Icons.password_outlined,
              size: 16,
              color: colors.textSecondary,
            ),
            label: Text(
              _showPasswordChange
                  ? 'Cancelar alteração de senha'
                  : 'Alterar minha senha de acesso',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
        ),
        if (_showPasswordChange) ...[
          const SizedBox(height: 8),
          _buildInput(
            colors: colors,
            controller: _curPassCtrl,
            label: 'Senha Atual',
            obscure: true,
          ),
          const SizedBox(height: 8),
          _buildInput(
            colors: colors,
            controller: _newPassCtrl,
            label: 'Nova Senha (mín. 8 caracteres)',
            obscure: true,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _isBusy ? null : _handleChangePassword,
                child: const Text('Confirmar Nova Senha'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _emailCtrl.text = _cloud.userEmail;
                    _isForgotMode = true;
                    _forgotStep = 1;
                    _statusMsg = null;
                    _isError = false;
                    _resetCodeCtrl.clear();
                    _newForgotPassCtrl.clear();
                  });
                },
                child: Text(
                  'Esqueci minha senha atual',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.accentBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDisconnectedBody(OpenMoneyColors colors) {
    final savedAccounts = _cloud.savedAccounts;
    if (_isForgotMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _isForgotMode = false;
                  _forgotStep = 1;
                  _statusMsg = null;
                  _isError = false;
                });
              },
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Voltar ao Login', style: TextStyle(fontSize: 12.5)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _forgotStep == 1
                ? 'Recuperar Senha por E-mail (Etapa 1 de 2)'
                : 'Definir Nova Senha (Etapa 2 de 2)',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _forgotStep == 1
                ? 'Digite seu e-mail cadastrado. Um código de 6 dígitos será enviado via Resend.'
                : 'Digite o código de 6 dígitos recebido por e-mail e sua nova senha.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          if (!kIsWeb) ...[
            _buildInput(
              colors: colors,
              controller: _serverCtrl,
              label: 'URL do Servidor Cloud',
            ),
            const SizedBox(height: 10),
          ],
          if (_forgotStep == 1) ...[
            _buildInput(
              colors: colors,
              controller: _emailCtrl,
              label: 'E-mail Cadastrado',
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accentBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isBusy ? null : _handleRequestResetCode,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  _isBusy ? 'Enviando código...' : 'Enviar Código de Recuperação',
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.bgPrimary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.borderGlass),
              ),
              child: Row(
                children: [
                  Icon(Icons.email_outlined, size: 16, color: colors.accentBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _emailCtrl.text.trim(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _forgotStep = 1;
                        _resetCodeCtrl.clear();
                        _newForgotPassCtrl.clear();
                        _statusMsg = null;
                        _isError = false;
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Alterar',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.accentBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildInput(
              colors: colors,
              controller: _resetCodeCtrl,
              label: 'Código de Verificação (6 dígitos)',
            ),
            const SizedBox(height: 10),
            _buildInput(
              colors: colors,
              controller: _newForgotPassCtrl,
              label: 'Nova Senha (mín. 8 caracteres)',
              obscure: true,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accentBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isBusy ? null : _handleResetPasswordAndLogin,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(
                  _isBusy ? 'Redefinindo senha...' : 'Redefinir Senha e Conectar',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _isBusy ? null : _handleRequestResetCode,
                child: Text(
                  'Não recebeu o código? Reenviar',
                  style: TextStyle(fontSize: 12, color: colors.accentBlue),
                ),
              ),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_addingAnotherAccount && _cloud.isAuthenticated) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _addingAnotherAccount = false),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: Text(
                'Voltar para a conta ativa (${_cloud.userEmail})',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (savedAccounts.isNotEmpty && !_cloud.isAuthenticated) ...[
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: colors.bgPrimary.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.borderGlass),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contas Salvas neste Dispositivo (Acesso Rápido)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                ...savedAccounts.map(
                  (acc) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.account_circle_outlined,
                      color: colors.accentBlue,
                      size: 20,
                    ),
                    title: Text(
                      acc.name.isNotEmpty
                          ? '${acc.name} (${acc.email})'
                          : acc.email,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    trailing: OutlinedButton(
                      onPressed:
                          _isBusy ? null : () => _handleSwitchAccount(acc),
                      child: const Text(
                        'Conectar',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!kIsWeb) ...[
          _buildInput(
            colors: colors,
            controller: _serverCtrl,
            label: 'URL do Servidor Cloud',
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            ChoiceChip(
              label: const Text('Já tenho conta'),
              selected: !_isRegisterMode,
              onSelected: (_) => setState(() => _isRegisterMode = false),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Criar nova conta / base'),
              selected: _isRegisterMode,
              onSelected: (_) => setState(() => _isRegisterMode = true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isRegisterMode) ...[
          _buildInput(
            colors: colors,
            controller: _nameCtrl,
            label: 'Nome',
          ),
          const SizedBox(height: 10),
        ],
        _buildInput(
          colors: colors,
          controller: _emailCtrl,
          label: 'E-mail',
        ),
        const SizedBox(height: 10),
        _buildInput(
          colors: colors,
          controller: _passwordCtrl,
          label: 'Senha',
          obscure: true,
        ),
        if (!_isRegisterMode) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                setState(() {
                  _isForgotMode = true;
                  _forgotStep = 1;
                  _statusMsg = null;
                  _isError = false;
                  _resetCodeCtrl.clear();
                  _newForgotPassCtrl.clear();
                });
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Esqueci minha senha',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colors.accentBlue,
                ),
              ),
            ),
          ),
        ],
        if (_isRegisterMode) ...[
          const SizedBox(height: 10),
          _buildInput(
            colors: colors,
            controller: _inviteCtrl,
            label: 'Código de Convite (se configurado)',
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.bgPrimary.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.borderGlass),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dados iniciais para esta nova conta:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text(
                        'Criar Nova Base em Branco (Limpa)',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      selected: _registerWithBlankBase,
                      onSelected: (_) =>
                          setState(() => _registerWithBlankBase = true),
                    ),
                    ChoiceChip(
                      label: const Text(
                        'Copiar Dados Atualmente na Tela',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      selected: !_registerWithBlankBase,
                      onSelected: (_) =>
                          setState(() => _registerWithBlankBase = false),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 42,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accentBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: _isBusy ? null : _handleAuth,
            icon: Icon(_isRegisterMode ? Icons.person_add : Icons.login),
            label: Text(
              _isBusy
                  ? 'Conectando...'
                  : (_isRegisterMode
                      ? (_registerWithBlankBase
                          ? 'Criar Nova Conta e Base em Branco'
                          : 'Criar Conta e Enviar Base Atual')
                      : 'Conectar e Sincronizar'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInput({
    required OpenMoneyColors colors,
    required TextEditingController controller,
    required String label,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(fontSize: 13, color: colors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: colors.textSecondary),
        isDense: true,
        filled: true,
        fillColor: colors.bgPrimary.withValues(alpha: 0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.borderGlass),
        ),
      ),
    );
  }
}

/// Abre a modal com o Guia de Ajuda e Boas Práticas do OpenMoney Cloud
Future<void> showCloudSyncHelpModal(
  BuildContext context,
  OpenMoneyColors colors,
) async {
  await showDialog(
    context: context,
    builder: (ctx) => _CloudSyncHelpDialog(colors: colors),
  );
}

class _CloudSyncHelpDialog extends StatefulWidget {
  final OpenMoneyColors colors;

  const _CloudSyncHelpDialog({required this.colors});

  @override
  State<_CloudSyncHelpDialog> createState() => _CloudSyncHelpDialogState();
}

class _CloudSyncHelpDialogState extends State<_CloudSyncHelpDialog> {
  int _selectedTopic = 0;

  static const List<({String title, IconData icon, String summary, List<String> paragraphs})> _topics = [
    (
      title: '1. Primeiro Acesso & Importação',
      icon: Icons.rocket_launch_outlined,
      summary: 'Como criar sua conta na nuvem ou trazer sua base openmoney.json existente.',
      paragraphs: [
        '• Se você já possui uma base openmoney.json existente:\nAo criar sua conta na versão Web (https://openmoney.app.br), clique no botão "Importar meu openmoney.json existente (Opcional)". Sua base completa será compactada via Gzip, criptografada via AES-256-GCM e enviada imediatamente para o servidor.',
        '• Se você está no aplicativo Desktop:\nAbra a janela "Cloud & Sincronização", marque a opção "Criar nova conta / base" e selecione "Copiar Dados Atualmente na Tela". O aplicativo enviará a base que já está aberta na tela para a sua nova conta.',
        '• Se você é um novo usuário começando do zero:\nSelecione "Criar Nova Base em Branco (Limpa)". O sistema criará uma base limpa no Schema v: 7, pronta para você cadastrar suas contas e lançamentos.',
      ],
    ),
    (
      title: '2. Sincronização no Dia a Dia',
      icon: Icons.sync_rounded,
      summary: 'Salvamento automático contínuo com debounce de 350ms.',
      paragraphs: [
        '• Salvamento Automático:\nToda vez que você adiciona ou edita um lançamento, conta ou fatura, o OpenMoney aguarda 350 milissegundos após você parar de digitar e salva as alterações na nuvem de forma invisível.',
        '• Download Automático:\nAo abrir o aplicativo ou alternar entre telas, o sistema busca revisões mais recentes (rX) feitas em outros dispositivos e atualiza a tela na hora.',
        '• Indicadores de Estado:\n- 🟢 Sincronizado (r15): Todos os dados estão salvos na nuvem.\n- 🔵 Sincronizando...: Transmitindo ou recebendo alterações.\n- ⚪ Modo Local: Operando offline neste navegador.',
      ],
    ),
    (
      title: '3. Múltiplos Dispositivos',
      icon: Icons.devices_rounded,
      summary: 'Use no Mac, Windows, iPhone, Android e Web simultaneamente.',
      paragraphs: [
        '• Conectar em Outro Dispositivo:\nNo segundo aparelho (ex: celular ou notebook do trabalho), acesse https://openmoney.app.br ou abra o aplicativo nativo, digite o MESMO e-mail e a MESMA senha e clique em "Acessar Minha Base".',
        '• Sincronia Instantânea:\nO que você lançar pelo celular na rua aparecerá automaticamente no seu computador quando você abri-lo em casa.',
      ],
    ),
    (
      title: '4. Múltiplas Contas (Multi-Account)',
      icon: Icons.switch_account_outlined,
      summary: 'Gerencie bases Pessoal, Familiar e PJ no mesmo computador.',
      paragraphs: [
        '• Alternância Rápida em 1 Clique:\nNa tela "Cloud & Sincronização", a seção "Alternar entre Contas e Bases" lista todas as contas salvas neste dispositivo. Basta clicar em "Alternar".',
        '• Proteção de Dados:\nAo alternar de conta, qualquer gravação pendente é imediatamente cancelada para impedir qualquer risco de contaminação de dados entre bases diferentes.',
        '• Criar Nova Base Separada:\nClique em "+ Nova Conta/Base" para cadastrar outro e-mail com uma base totalmente isolada.',
      ],
    ),
    (
      title: '5. Backups Diários na Nuvem',
      icon: Icons.shield_outlined,
      summary: 'Histórico dos últimos 15 dias armazenado de forma segura.',
      paragraphs: [
        '• Snapshots Automáticos:\nA cada dia em que você salvar alterações, o servidor Cloudflare D1 armazena uma fotografia diária criptografada da sua base.',
        '• Como Restaurar:\nNo painel de Nuvem, role até "Backups Diários Automáticos na Nuvem" e clique em "Restaurar" ao lado da data desejada para recuperar a base daquele dia.',
      ],
    ),
    (
      title: '6. Recuperação de Senha por E-mail',
      icon: Icons.mark_email_read_outlined,
      summary: 'Código numérico de 6 dígitos via Resend válido por 15 minutos.',
      paragraphs: [
        '• Como Recuperar:\nNa tela de login, clique em "Esqueci minha senha", informe seu e-mail cadastrado e clique em "Enviar Código de Recuperação".',
        '• Código de 6 Dígitos:\nVocê receberá um e-mail do OpenMoney com um código numérico válido por 15 minutos. Digite o código no aplicativo, informe sua nova senha (mínimo de 8 caracteres) e o sistema já entrará logado.',
        '• Se aparecer "Sessão expirada":\nIsso acontece se você redefiniu a senha na Web e o Desktop ainda tinha a sessão antiga. Basta clicar no botão "Reconectar com Senha" e digitar a nova senha.',
      ],
    ),
    (
      title: '7. Modo Offline e Navegador',
      icon: Icons.wifi_off_rounded,
      summary: 'Uso sem internet ou sem criar conta na nuvem.',
      paragraphs: [
        '• Modo Offline:\nSe você perder a conexão, o aplicativo continua funcionando normalmente e sincroniza tudo assim que a internet voltar.',
        '• Modo Visitante:\nNa versão Web, clicar em "Usar Offline neste Navegador" grava os dados no localStorage do seu navegador sem enviar nada para servidores externos.',
      ],
    ),
    (
      title: '8. Criptografia & Privacidade',
      icon: Icons.lock_outline_rounded,
      summary: 'AES-256-GCM + PBKDF2 com isolamento estrito por usuário.',
      paragraphs: [
        '• Chaves Exclusivas por Usuário:\nO arquivo openmoney.json é criptografado com AES-256-GCM usando chave derivada via HKDF-SHA256 para o seu user_id. O banco de dados só armazena texto cifrado.',
        '• Senhas Seguras:\nSenhas são protegidas com salt aleatório de 128 bits e 100.000 iterações PBKDF2-HMAC-SHA256.',
        '• Retenção e Exportação:\nVocê é o único dono dos seus dados e pode exportar seu arquivo .json físico a qualquer momento pelas configurações.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final isCompact = MediaQuery.of(context).size.width < 700;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 620),
        child: Container(
          decoration: BoxDecoration(
            color: colors.bgSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.borderGlass, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho da Modal de Ajuda
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.help_outline_rounded,
                      color: colors.accentBlue,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Guia de Uso: OpenMoney Cloud & Sincronização',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: colors.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(color: colors.borderGlass, height: 1),

              // Corpo da Ajuda
              Expanded(
                child: isCompact ? _buildCompactView(colors) : _buildWideView(colors),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWideView(OpenMoneyColors colors) {
    final activeTopic = _topics[_selectedTopic];

    return Row(
      children: [
        // Coluna Esquerda: Lista de Tópicos
        Container(
          width: 260,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: colors.borderGlass)),
            color: colors.bgPrimary.withValues(alpha: 0.35),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _topics.length,
            separatorBuilder: (_, __) => Divider(
              color: colors.borderGlass.withValues(alpha: 0.4),
              height: 1,
            ),
            itemBuilder: (ctx, idx) {
              final item = _topics[idx];
              final isSelected = idx == _selectedTopic;

              return ListTile(
                dense: true,
                selected: isSelected,
                selectedTileColor: colors.accentBlue.withValues(alpha: 0.15),
                leading: Icon(
                  item.icon,
                  size: 18,
                  color: isSelected ? colors.accentBlue : colors.textSecondary,
                ),
                title: Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? colors.accentBlue : colors.textPrimary,
                  ),
                ),
                onTap: () => setState(() => _selectedTopic = idx),
              );
            },
          ),
        ),

        // Coluna Direita: Conteúdo Detalhado
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(activeTopic.icon, size: 24, color: colors.accentBlue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        activeTopic.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  activeTopic.summary,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                ...activeTopic.paragraphs.map(
                  (p) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.bgPrimary.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.borderGlass),
                    ),
                    child: Text(
                      p,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactView(OpenMoneyColors colors) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _topics.length,
      itemBuilder: (ctx, idx) {
        final item = _topics[idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: colors.bgPrimary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.borderGlass),
          ),
          child: ExpansionTile(
            leading: Icon(item.icon, size: 20, color: colors.accentBlue),
            title: Text(
              item.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            subtitle: Text(
              item.summary,
              style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
            ),
            childrenPadding: const EdgeInsets.all(12),
            children: item.paragraphs
                .map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      p,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}
