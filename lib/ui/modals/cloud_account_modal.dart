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
  bool _isBusy = false;
  bool _showPasswordChange = false;
  String? _statusMsg;
  bool _isError = false;
  List<CloudBackupInfo> _cloudBackups = const [];
  bool _loadingBackups = false;

  late final TextEditingController _serverCtrl;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();
  final _curPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _serverCtrl = TextEditingController(text: _cloud.apiBaseUrl);
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
    _inviteCtrl.dispose();
    _curPassCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
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
        await widget.store.pushLocalToCloud(force: true);
        await _loadCloudBackups();
        setState(() {
          _isError = false;
          _statusMsg =
              '✓ Conta criada e base openmoney.json sincronizada na nuvem!';
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
          _isError = false;
          _statusMsg = '✓ Conectado e sincronizado com sucesso!';
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
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cabeçalho
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.accentBlue.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _cloud.isAuthenticated
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_sync_outlined,
                          color: _cloud.isAuthenticated
                              ? colors.accentGreen
                              : colors.accentBlue,
                          size: 22,
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
                                  : 'Sincronize sua base openmoney.json entre Web, Desktop e Mobile',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
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
                      child: _cloud.isAuthenticated
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
                      child: Text(
                        _statusMsg!,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color:
                              _isError ? colors.accentRed : colors.accentGreen,
                        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card de Resumo da Conta
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
                    Text(
                      _cloud.userName.isNotEmpty
                          ? _cloud.userName
                          : _cloud.userEmail,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
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
                  if (kIsWeb) {
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

        const SizedBox(height: 18),

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
          constraints: const BoxConstraints(maxHeight: 160),
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

        const SizedBox(height: 12),

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
          ElevatedButton(
            onPressed: _isBusy ? null : _handleChangePassword,
            child: const Text('Confirmar Nova Senha'),
          ),
        ],
      ],
    );
  }

  Widget _buildDisconnectedBody(OpenMoneyColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!kIsWeb) ...[
          _buildInput(
            colors: colors,
            controller: _serverCtrl,
            label:
                'URL do seu OpenMoney na Cloudflare (ex: https://openmoney.suaempresa.com.br)',
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
              label: const Text('Criar nova conta'),
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
        if (_isRegisterMode) ...[
          const SizedBox(height: 10),
          _buildInput(
            colors: colors,
            controller: _inviteCtrl,
            label: 'Código de Convite (se configurado)',
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
                      ? 'Criar Conta e Enviar Base Atual'
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
