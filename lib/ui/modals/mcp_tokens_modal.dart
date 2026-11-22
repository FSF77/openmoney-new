import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/cloud_sync_service.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

Future<void> showMcpTokensModal(BuildContext context, MoneyStore store) async {
  await showDialog(
    context: context,
    builder: (ctx) => _McpTokensDialog(store: store),
  );
}

class _McpTokensDialog extends StatefulWidget {
  final MoneyStore store;
  const _McpTokensDialog({required this.store});

  @override
  State<_McpTokensDialog> createState() => _McpTokensDialogState();
}

class _McpTokensDialogState extends State<_McpTokensDialog> {
  List<Map<String, dynamic>> _tokens = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTokens();
  }

  Future<void> _loadTokens() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (!CloudSyncService.instance.isAuthenticated) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Para utilizar o servidor MCP, é necessário estar conectado à sua conta na Nuvem Cloud (Cloudflare).';
      });
      return;
    }

    try {
      final list = await CloudSyncService.instance.fetchApiTokens();
      if (mounted) {
        setState(() {
          _tokens = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Erro ao carregar tokens: $e';
        });
      }
    }
  }

  Future<void> _openCreateTokenDialog(OpenMoneyColors colors) async {
    final nameCtrl = TextEditingController(text: 'Claude Desktop');
    String permissions = 'read_write';

    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.bgSecondary,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.borderGlass),
          ),
          title: Row(
            children: [
              const Icon(Icons.key_rounded, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Novo Token MCP',
                style: TextStyle(fontSize: 16, color: colors.textPrimary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Identifique onde este token será utilizado (ex: Claude Desktop, Cursor, Agente Local):',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nome do Token',
                  labelStyle: TextStyle(fontSize: 12, color: colors.textMuted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: TextStyle(fontSize: 13, color: colors.textPrimary),
              ),
              const SizedBox(height: 14),
              Text(
                'Permissões:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.textPrimary),
              ),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'read_write',
                    label: Text('Leitura e Escrita', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.edit_note_outlined, size: 14),
                  ),
                  ButtonSegment(
                    value: 'read_only',
                    label: Text('Apenas Leitura', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.visibility_outlined, size: 14),
                  ),
                ],
                selected: {permissions},
                onSelectionChanged: (val) {
                  setDialogState(() => permissions = val.first);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final nav = Navigator.of(ctx);
                final res = await CloudSyncService.instance.createApiToken(
                  name: nameCtrl.text.trim(),
                  permissions: permissions,
                );
                if (res.ok && res.tokenData != null) {
                  nav.pop(res.tokenData);
                } else {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(res.error ?? 'Falha ao gerar token.')),
                    );
                  }
                }
              },
              child: const Text('Gerar Token'),
            ),
          ],
        ),
      ),
    );

    if (created != null && mounted) {
      _showTokenCreatedDialog(colors, created);
      _loadTokens();
    }
  }

  void _showTokenCreatedDialog(OpenMoneyColors colors, Map<String, dynamic> tokenData) {
    final fullToken = tokenData['token']?.toString() ?? '';
    final mcpUrl = 'https://openmoney.app.br/api/mcp/sse';

    final claudeConfigSnippet = jsonEncode({
      'mcpServers': {
        'openmoney': {
          'url': mcpUrl,
          'headers': {
            'Authorization': 'Bearer $fullToken',
          },
        },
      },
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSecondary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.borderGlass),
        ),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
            const SizedBox(width: 8),
            Text(
              'Token MCP Gerado com Sucesso!',
              style: TextStyle(fontSize: 16, color: colors.textPrimary, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Copie seu token agora! Por motivos de segurança, ele nunca mais será exibido.',
                        style: TextStyle(fontSize: 11.5, color: Colors.amber, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Token de Acesso (Bearer Token):', style: TextStyle(fontSize: 11.5, color: colors.textSecondary)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.bgPrimary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.borderGlass),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        fullToken,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: 'Copiar Token',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fullToken));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Token copiado para a área de transferência!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('Configuração para o Claude Desktop (claude_desktop_config.json):',
                  style: TextStyle(fontSize: 11.5, color: colors.textSecondary)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.bgPrimary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.borderGlass),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(
                      claudeConfigSnippet,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('Copiar Bloco JSON para o Claude Desktop', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: claudeConfigSnippet));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Configuração JSON copiada!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Concluído'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteToken(String tokenId) async {
    final ok = await CloudSyncService.instance.deleteApiToken(tokenId);
    if (ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Token revogado com sucesso.')),
        );
        _loadTokens();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isMobile = MediaQuery.sizeOf(context).width < 680;

    return Dialog(
      backgroundColor: colors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass, width: 1),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: 580,
          minWidth: isMobile ? 300 : 500,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 14 : 20,
                vertical: isMobile ? 12 : 16,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF162032) : const Color(0xFFF1F5F9),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: colors.borderGlass, width: 1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                    ),
                    child: const Icon(Icons.hub_outlined, color: Colors.blueAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Servidor MCP & Acesso Externo',
                          style: TextStyle(
                            fontSize: isMobile ? 14 : 16,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Model Context Protocol para Claude Desktop, Cursor e agentes',
                          style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Recarregar',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _loadTokens,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Banner explicativo do endpoint
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.bgPrimary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.borderGlass),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Endpoint Oficial MCP (SSE):',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 2),
                          SelectableText(
                            'https://openmoney.app.br/api/mcp/sse',
                            style: TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: Colors.blueAccent),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: 'Copiar URL do MCP',
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: 'https://openmoney.app.br/api/mcp/sse'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('URL do MCP copiada!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Lista de tokens
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, color: colors.expense),
                            ),
                          ),
                        )
                      : _tokens.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.vpn_key_outlined, size: 40, color: colors.textMuted.withValues(alpha: 0.5)),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Nenhum Token MCP gerado ainda.',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Gere um token abaixo para conectar o Claude Desktop ou Cursor à sua base.',
                                    style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: _tokens.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: colors.borderGlass),
                              itemBuilder: (ctx, idx) {
                                final tok = _tokens[idx];
                                final name = tok['name']?.toString() ?? 'Token';
                                final prefix = tok['token_prefix']?.toString() ?? 'opm_live_...';
                                final permissions = tok['permissions']?.toString() ?? 'read_write';
                                final isReadOnly = permissions == 'read_only';
                                final lastUsed = tok['last_used_at']?.toString();
                                final created = tok['created_at']?.toString() ?? '';

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: (isReadOnly ? Colors.teal : Colors.blueAccent).withValues(alpha: 0.12),
                                        ),
                                        child: Icon(
                                          isReadOnly ? Icons.visibility_outlined : Icons.edit_note_outlined,
                                          size: 16,
                                          color: isReadOnly ? Colors.teal : Colors.blueAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  name,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: colors.textPrimary,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: (isReadOnly ? Colors.teal : Colors.blueAccent).withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    isReadOnly ? 'Leitura' : 'Leitura e Escrita',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: isReadOnly ? Colors.teal : Colors.blueAccent,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'Prefixo: $prefix  •  Criado: ${created.length >= 10 ? created.substring(0, 10) : created}',
                                              style: TextStyle(fontSize: 11, color: colors.textMuted),
                                            ),
                                            if (lastUsed != null && lastUsed.isNotEmpty)
                                              Text(
                                                'Último uso: ${lastUsed.length >= 16 ? lastUsed.substring(0, 16).replaceFirst("T", " ") : lastUsed}',
                                                style: TextStyle(fontSize: 10.5, color: colors.textSecondary),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                        tooltip: 'Revogar Token',
                                        onPressed: () => _deleteToken(tok['id']?.toString() ?? ''),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF162032) : const Color(0xFFF1F5F9),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: colors.borderGlass, width: 1)),
              ),
              child: Row(
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Gerar Novo Token MCP'),
                    onPressed: () => _openCreateTokenDialog(colors),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
