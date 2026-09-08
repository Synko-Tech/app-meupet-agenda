import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_brand_colors.dart';
import '../../app/formatters.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/business_context_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../models/app_user.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_page.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';
import 'appointment_history_screen.dart';
import 'financial_summary_screen.dart';
import 'private_profile_screen.dart';
import 'widgets/merchant_connection_card.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final profile = auth.profile;

    if (profile == null) {
      return ListView(
        padding: const EdgeInsets.all(18),
        children: const [
          EmptyState(
            icon: Icons.person_off_outlined,
            title: 'Conta nao encontrada',
            message: 'Entre novamente para carregar seus dados.',
          ),
        ],
      );
    }

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Perfil',
            subtitle: 'Dados da conta, historicos e seguranca',
          ),
          _ProfileCard(profile: profile),
          const SizedBox(height: 12),
          _PaymentsReceivingCard(profile: profile),
          const SizedBox(height: 12),
          _ProfileActions(profile: profile),
        ],
      ),
    );
  }
}

/// Card de recebimentos (Mercado Pago) da loja ativa. Visible apenas para
/// staff da loja; owner gerencia a conexao.
class _PaymentsReceivingCard extends StatelessWidget {
  const _PaymentsReceivingCard({required this.profile});

  final AppUser profile;

  @override
  Widget build(BuildContext context) {
    final businessContext = context.watch<BusinessContextController>();
    final role = businessContext.activeRole;
    if (role == null || !role.isStaff) {
      return const SizedBox.shrink();
    }
    return MerchantConnectionCard(profile: profile, role: role);
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final AppUser profile;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name.isEmpty ? 'Usuario' : profile.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(profile.email),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusBadge(label: profile.role.label),
                        StatusBadge(
                          label: profile.isActive ? 'Ativo' : 'Inativo',
                          variant: profile.isActive
                              ? StatusBadgeVariant.success
                              : StatusBadgeVariant.warning,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ProfileInfoRow(
            icon: Icons.phone_outlined,
            label: 'Telefone',
            value: profile.phone?.isNotEmpty == true
                ? profile.phone!
                : 'Nao informado',
          ),
          const SizedBox(height: 10),
          _ProfileInfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Cadastro',
            value: profile.createdAt == null
                ? 'Nao informado'
                : formatDate(profile.createdAt!),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.brand.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileActions extends StatelessWidget {
  const _ProfileActions({required this.profile});

  final AppUser profile;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final themeController = context.watch<ThemeController>();
    return Column(
      children: [
        AppButton(
          key: const Key('account_private_profile_button'),
          label: 'Dados pessoais',
          icon: Icons.badge_outlined,
          isSecondary: true,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrivateProfileScreen(userId: profile.id),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.dark_mode_outlined, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Modo escuro')),
            Switch(
              value: themeController.isDark,
              onChanged: (_) => themeController.toggle(),
            ),
          ],
        ),
        if (profile.isSuperAdmin) ...[
          const SizedBox(height: 16),
          const _SuperAdminPrivateLookup(),
        ],
        const SizedBox(height: 10),
        if (profile.isAdmin) ...[
          const SizedBox(height: 10),
          AppButton(
            label: 'Historico de agendamentos',
            icon: Icons.history_outlined,
            isSecondary: true,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AppointmentHistoryScreen(profile: profile),
              ),
            ),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'Resumo financeiro',
            icon: Icons.analytics_outlined,
            isSecondary: true,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FinancialSummaryScreen()),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Editar perfil',
                icon: Icons.edit_outlined,
                isSecondary: true,
                isLoading: auth.isBusy,
                onPressed: () => _showEditSheet(context, profile),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppButton(
                label: 'Alterar senha',
                icon: Icons.lock_reset_outlined,
                isSecondary: true,
                isLoading: auth.isBusy,
                onPressed: () => _sendPasswordReset(context, profile.email),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AppButton(
          key: const Key('account_logout_button'),
          label: 'Sair da conta',
          icon: Icons.logout,
          isLoading: auth.isBusy,
          onPressed: () => context.read<AuthController>().signOut(),
        ),
      ],
    );
  }

  void _showEditSheet(BuildContext context, AppUser profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditProfileSheet(profile: profile),
    );
  }

  Future<void> _sendPasswordReset(BuildContext context, String email) async {
    final auth = context.read<AuthController>();
    try {
      await auth.sendPasswordReset(email);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail de alteracao de senha enviado.')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.errorMessage ?? 'Falha ao enviar e-mail.')),
      );
    }
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.profile});

  final AppUser profile;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _phoneController = TextEditingController(text: widget.profile.phone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final auth = context.watch<AuthController>();
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, bottom + 18),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Editar perfil',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Nome',
              controller: _nameController,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Informe o nome'
                  : null,
            ),
            const SizedBox(height: 10),
            AppTextField(
              label: 'Telefone',
              controller: _phoneController,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'Salvar alteracoes',
              icon: Icons.save_outlined,
              isLoading: auth.isBusy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final auth = context.read<AuthController>();
    try {
      await auth.updateProfile(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Perfil atualizado.')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.errorMessage ?? 'Falha ao salvar perfil.')),
      );
    }
  }
}

/// Entrada administrativa minima para super admin: consulta o detalhe
/// privado (CPF mascarado + endereco) de um UID conhecido digitado aqui.
/// As regras do Firestore autorizam apenas super_admin a ler documentos
/// de terceiros; admin comum e colaborador nao veem este bloco.
class _SuperAdminPrivateLookup extends StatefulWidget {
  const _SuperAdminPrivateLookup();

  @override
  State<_SuperAdminPrivateLookup> createState() =>
      _SuperAdminPrivateLookupState();
}

class _SuperAdminPrivateLookupState extends State<_SuperAdminPrivateLookup> {
  final _uidController = TextEditingController();

  @override
  void dispose() {
    _uidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Consulta administrativa',
          style: TextStyle(
            color: context.brand.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        AppTextField(
          key: const Key('private_lookup_uid_field'),
          label: 'UID do usuario',
          controller: _uidController,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _open(),
        ),
        const SizedBox(height: 8),
        AppButton(
          key: const Key('private_lookup_open_button'),
          label: 'Ver dados privados',
          icon: Icons.visibility_outlined,
          isSecondary: true,
          onPressed: _open,
        ),
      ],
    );
  }

  void _open() {
    final uid = _uidController.text.trim();
    if (uid.isEmpty) {
      return;
    }
    final ownUid = context.read<AuthController>().firebaseUser?.uid;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateProfileScreen(userId: uid, ownUid: ownUid),
      ),
    );
  }
}
