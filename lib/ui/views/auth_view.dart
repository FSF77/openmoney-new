import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/native_file_picker.dart';
import '../../services/platform_io.dart';
import '../../services/update_service.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

class AuthView extends StatefulWidget {
  final MoneyStore store;

  const AuthView({super.key, required this.store});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  bool _isRegisterMode = false;
  bool _isForgotMode = false;
  int _forgotStep = 1;
  bool _obscurePassword = true;
  bool _obscureNewPassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;
  Map<String, dynamic>? _importedInitialJson;
  String? _importedFileName;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _resetCodeCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();
  late final TextEditingController _serverUrlCtrl;

  @override
  void initState() {
    super.initState();
    _serverUrlCtrl = TextEditingController(
      text: CloudSyncService.instance.apiBaseUrl,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _resetCodeCtrl.dispose();
    _newPasswordCtrl.dispose();
    _inviteCtrl.dispose();
    _serverUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestResetCode() async {
    if (_isLoading) return;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _errorMessage = 'Informe um e-mail válido para receber o código.';
        _infoMessage = null;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      final res = await CloudSyncService.instance.requestPasswordResetCode(
        email: email,
        customApiUrl: _serverUrlCtrl.text.trim().isEmpty ? null : _serverUrlCtrl.text.trim(),
      );
      if (mounted) {
        if (res.ok) {
          setState(() {
            _forgotStep = 2;
            _infoMessage = res.message ?? 'Código de 6 dígitos enviado para seu e-mail!';
            _errorMessage = null;
          });
        } else {
          setState(() {
            _errorMessage = res.error;
            _infoMessage = null;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPasswordAndLogin() async {
    if (_isLoading) return;
    final email = _emailCtrl.text.trim();
    final code = _resetCodeCtrl.text.trim();
    final newPass = _newPasswordCtrl.text;

    if (code.isEmpty) {
      setState(() {
        _errorMessage = 'Informe o código de 6 dígitos enviado para seu e-mail.';
        _infoMessage = null;
      });
      return;
    }
    if (newPass.length < 8) {
      setState(() {
        _errorMessage = 'A nova senha deve ter no mínimo 8 caracteres.';
        _infoMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final res = await CloudSyncService.instance.resetPasswordWithCode(
        email: email,
        code: code,
        newPassword: newPass,
        customApiUrl: _serverUrlCtrl.text.trim().isEmpty ? null : _serverUrlCtrl.text.trim(),
      );
      if (mounted) {
        if (res.ok) {
          await widget.store.syncFromCloud();
          widget.store.saveCloudSessionToConfig();
          return;
        } else {
          setState(() {
            _errorMessage = res.error;
            _infoMessage = null;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickInitialJsonFile() async {
    final path = await NativeFilePicker.pickFile(
      title: 'Selecionar arquivo openmoney.json existente',
      allowedExtensions: const ['json'],
    );
    if (path == null || path.isEmpty) return;
    try {
      final raw = await File(path).readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map &&
          (decoded.containsKey('accounts') || decoded.containsKey('txs'))) {
        if (!mounted) return;
        setState(() {
          _importedInitialJson = Map<String, dynamic>.from(decoded);
          _importedFileName = path.split('/').last;
          _errorMessage = null;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'O arquivo selecionado não parece ser uma base openmoney.json válida.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Não foi possível ler o arquivo .json selecionado.';
      });
    }
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final store = widget.store;
    final importedJson = _importedInitialJson;
    final customUrl = _serverUrlCtrl.text.trim();
    CloudSyncService.instance.setWebAuthFlowInProgress(true);

    try {
      if (_isRegisterMode) {
        // Cria a conta de forma instantânea e, em seguida, envia a base via stream binário Gzip
        final res = await CloudSyncService.instance.register(
          name: _nameCtrl.text,
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
          inviteCode: _inviteCtrl.text,
          customApiUrl: customUrl.isEmpty ? null : customUrl,
        );
        if (res.ok) {
          if (importedJson != null) {
            store.loadFromJsonMap(
              importedJson,
              virtualPath: 'cloud://${CloudSyncService.instance.userEmail}',
            );
            await store.pushLocalToCloud(force: true);
          } else {
            await store.syncFromCloud();
          }
          store.saveCloudSessionToConfig();
          CloudSyncService.instance.setWebAuthFlowInProgress(false);
          return;
        } else {
          if (mounted) {
            setState(() {
              _errorMessage = res.error;
            });
          }
        }
      } else {
        final res = await CloudSyncService.instance.login(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
          customApiUrl: customUrl.isEmpty ? null : customUrl,
        );
        if (res.ok) {
          await store.syncFromCloud();
          store.saveCloudSessionToConfig();
          CloudSyncService.instance.setWebAuthFlowInProgress(false);
          return;
        } else {
          if (mounted) {
            setState(() {
              _errorMessage = res.error;
            });
          }
        }
      }
    } finally {
      CloudSyncService.instance.setWebAuthFlowInProgress(false);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = OpenMoneyColors(widget.store.isDarkMode);

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.4),
            radius: 1.25,
            colors: [
              colors.accentBlue.withValues(alpha: 0.16),
              colors.bgPrimary,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: colors.bgSecondary.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.borderGlass, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Cabeçalho com Logo Oficial e Título
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'logo/openmoney_app_icon.png',
                            width: 52,
                            height: 52,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OpenMoney Cloud',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: colors.textPrimary,
                                letterSpacing: -0.4,
                              ),
                            ),
                            Text(
                              'v${OpenMoneyVersion.version} (Build ${OpenMoneyVersion.build})',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    if (CloudSyncService.instance.savedAccounts.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: colors.bgPrimary.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.borderGlass),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.switch_account_rounded,
                                  size: 15,
                                  color: colors.accentBlue,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Contas Salvas neste Dispositivo (Acesso Rápido)',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ...CloudSyncService.instance.savedAccounts.map(
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
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                trailing: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: _isLoading
                                      ? null
                                      : () async {
                                          setState(() {
                                            _isLoading = true;
                                            _errorMessage = null;
                                          });
                                          CloudSyncService.instance
                                              .setWebAuthFlowInProgress(true);
                                          try {
                                            CloudSyncService.instance
                                                .switchToSavedAccount(acc);
                                            final synced = await widget.store
                                                .syncFromCloud();
                                            if (synced) {
                                              widget.store
                                                  .saveCloudSessionToConfig();
                                              return;
                                            }
                                            if (mounted) {
                                              setState(() {
                                                _emailCtrl.text = acc.email;
                                                _errorMessage =
                                                    'Sessão expirada para ${acc.email}. Digite sua senha para reconectar.';
                                              });
                                            }
                                          } finally {
                                            CloudSyncService.instance
                                                .setWebAuthFlowInProgress(
                                                  false,
                                                );
                                            if (mounted) {
                                              setState(
                                                () => _isLoading = false,
                                              );
                                            }
                                          }
                                        },
                                  child: const Text(
                                    'Entrar',
                                    style: TextStyle(fontSize: 11.5),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_isForgotMode) ...[
                      _buildForgotPasswordContent(colors),
                    ] else ...[
                      // Seletor Entrar / Criar Conta
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colors.bgPrimary.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.borderGlass),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildModeTab(
                                colors: colors,
                                label: 'Entrar',
                                selected: !_isRegisterMode,
                                onTap: () => setState(() {
                                  _isRegisterMode = false;
                                  _errorMessage = null;
                                  _infoMessage = null;
                                }),
                              ),
                            ),
                            Expanded(
                              child: _buildModeTab(
                                colors: colors,
                                label: 'Criar Conta',
                                selected: _isRegisterMode,
                                onTap: () => setState(() {
                                  _isRegisterMode = true;
                                  _errorMessage = null;
                                  _infoMessage = null;
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (_isRegisterMode) ...[
                        _buildTextField(
                          colors: colors,
                          controller: _nameCtrl,
                          label: 'Seu Nome',
                          hint: 'Ex: Fabiano',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 12),
                      ],

                      _buildTextField(
                        colors: colors,
                        controller: _emailCtrl,
                        label: 'E-mail',
                        hint: 'seu@email.com',
                        icon: Icons.alternate_email,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),

                      _buildTextField(
                        colors: colors,
                        controller: _passwordCtrl,
                        label: 'Senha',
                        hint: _isRegisterMode
                            ? 'Mínimo de 8 caracteres'
                            : 'Digite sua senha',
                        icon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        onSubmitted: (_) => _submit(),
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                            size: 18,
                            color: colors.textSecondary,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),

                      if (!_isRegisterMode) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                _isForgotMode = true;
                                _forgotStep = 1;
                                _errorMessage = null;
                                _infoMessage = null;
                                _resetCodeCtrl.clear();
                                _newPasswordCtrl.clear();
                              });
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Esqueci minha senha',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.accentBlue,
                              ),
                            ),
                          ),
                        ),
                      ],

                      if (_isRegisterMode) ...[
                        const SizedBox(height: 12),
                        _buildTextField(
                          colors: colors,
                          controller: _inviteCtrl,
                          label: 'Código de Convite (se exigido)',
                          hint: 'Opcional se o cadastro estiver aberto',
                          icon: Icons.vpn_key_outlined,
                        ),
                        const SizedBox(height: 14),
                        // Opção para importar openmoney.json existente já na criação da conta
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _pickInitialJsonFile,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colors.accentBlue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: colors.accentBlue.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _importedInitialJson != null
                                      ? Icons.check_circle
                                      : Icons.upload_file_outlined,
                                  size: 18,
                                  color: _importedInitialJson != null
                                      ? colors.accentGreen
                                      : colors.accentBlue,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _importedFileName != null
                                        ? 'Base selecionada: $_importedFileName'
                                        : 'Importar meu openmoney.json existente (Opcional)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (_importedInitialJson != null)
                                  IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: colors.textSecondary,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => setState(() {
                                      _importedInitialJson = null;
                                      _importedFileName = null;
                                    }),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.accentBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          onPressed: _isLoading ? null : _submit,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _isRegisterMode
                                      ? Icons.person_add_alt_1
                                      : Icons.login,
                                  size: 18,
                                ),
                          label: Text(
                            _isLoading
                                ? 'Autenticando...'
                                : (_isRegisterMode
                                    ? 'Criar Conta Segura'
                                    : 'Acessar Minha Base'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],

                    if (_infoMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.accentGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colors.accentGreen.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: colors.accentGreen,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _infoMessage!,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.accentGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.accentRed.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colors.accentRed.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: colors.accentRed,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.accentRed,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Modo local / offline neste navegador
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          CloudSyncService.instance
                              .enableWebOfflineGuestMode();
                          final rawGuest =
                              webLocalStorageGet('openmoney_web_guest_db');
                          if (rawGuest != null && rawGuest.isNotEmpty) {
                            try {
                              final decoded = jsonDecode(rawGuest);
                              if (decoded is Map<String, dynamic> &&
                                  decoded['payload'] is Map<String, dynamic>) {
                                widget.store.loadFromJsonString(
                                  jsonEncode(decoded['payload']),
                                  virtualPath: 'local://navegador',
                                );
                              }
                            } catch (_) {}
                          }
                          widget.store.save();
                        },
                        icon: Icon(
                          Icons.computer_outlined,
                          size: 14,
                          color: colors.textSecondary,
                        ),
                        label: Text(
                          'Usar Offline neste Navegador',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Divider(color: colors.borderGlass),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 14,
                          color: colors.accentGreen,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Criptografia AES-256-GCM + PBKDF2',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForgotPasswordContent(OpenMoneyColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                setState(() {
                  _isForgotMode = false;
                  _forgotStep = 1;
                  _errorMessage = null;
                  _infoMessage = null;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 16, color: colors.accentBlue),
                    const SizedBox(width: 4),
                    Text(
                      'Voltar ao Login',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.accentBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _forgotStep == 1
              ? 'Recuperar Senha por E-mail'
              : 'Definir Nova Senha',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _forgotStep == 1
              ? 'Digite o e-mail cadastrado para receber um código numérico de 6 dígitos via Resend.'
              : 'Digite o código de 6 dígitos enviado para seu e-mail e cadastre uma nova senha.',
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        if (_forgotStep == 1) ...[
          _buildTextField(
            colors: colors,
            controller: _emailCtrl,
            label: 'E-mail Cadastrado',
            hint: 'seu@email.com',
            icon: Icons.alternate_email,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _requestResetCode(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              onPressed: _isLoading ? null : _requestResetCode,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _isLoading
                    ? 'Enviando código...'
                    : 'Enviar Código de Recuperação',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
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
                      _newPasswordCtrl.clear();
                      _errorMessage = null;
                      _infoMessage = null;
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
          const SizedBox(height: 12),
          _buildTextField(
            colors: colors,
            controller: _resetCodeCtrl,
            label: 'Código de Verificação (6 dígitos)',
            hint: 'Ex: 123456',
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            colors: colors,
            controller: _newPasswordCtrl,
            label: 'Nova Senha',
            hint: 'Mínimo de 8 caracteres',
            icon: Icons.lock_outline,
            obscureText: _obscureNewPassword,
            onSubmitted: (_) => _resetPasswordAndLogin(),
            suffix: IconButton(
              icon: Icon(
                _obscureNewPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
                color: colors.textSecondary,
              ),
              onPressed: () => setState(
                () => _obscureNewPassword = !_obscureNewPassword,
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              onPressed: _isLoading ? null : _resetPasswordAndLogin,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                _isLoading
                    ? 'Redefinindo senha...'
                    : 'Redefinir Senha e Entrar',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _isLoading ? null : _requestResetCode,
              child: Text(
                'Não recebeu o código? Reenviar',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.accentBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModeTab({
    required OpenMoneyColors colors,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? colors.accentBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required OpenMoneyColors colors,
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          onSubmitted: onSubmitted,
          style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: colors.textSecondary.withValues(alpha: 0.55),
            ),
            prefixIcon: Icon(icon, size: 18, color: colors.textSecondary),
            suffixIcon: suffix,
            filled: true,
            fillColor: colors.bgPrimary.withValues(alpha: 0.65),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.borderGlass),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.borderGlass),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.accentBlue, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
