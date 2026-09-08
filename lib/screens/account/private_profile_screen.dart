import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_brand_colors.dart';
import '../../models/postal_address.dart';
import '../../models/private_profile.dart';
import '../../repositories/private_profile_repository.dart';
import '../../services/function_error.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/empty_state.dart';

/// Tela de dados pessoais privados (CPF mascarado + endereco) de um
/// usuario. [userId] e o dono na navegacao normal e um UID digitado pelo
/// super admin na consulta administrativa (regras do Firestore autorizam
/// dono e super_admin apenas).
class PrivateProfileScreen extends StatefulWidget {
  const PrivateProfileScreen({
    super.key,
    required this.userId,
    this.ownUid,
  });

  final String userId;

  /// UID do usuario autenticado. Quando difere de [userId] (consulta do
  /// super admin por outro usuario), a edicao de endereco e ocultada:
  /// `updateOwnAddress` so altera o perfil do proprio chamador.
  final String? ownUid;

  @override
  State<PrivateProfileScreen> createState() => _PrivateProfileScreenState();
}

class _PrivateProfileScreenState extends State<PrivateProfileScreen> {
  PrivateProfileRepository get _repository =>
      context.read<PrivateProfileRepository>();

  /// Edicao de endereco so para o proprio perfil: sem [widget.ownUid]
  /// (navegacao do dono) ou quando ele coincide com [widget.userId].
  bool get _canEditAddress =>
      widget.ownUid == null || widget.ownUid == widget.userId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dados pessoais')),
      body: StreamBuilder<PrivateProfile?>(
        stream: _repository.privateProfileStream(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.visibility_off_outlined,
              title: 'Dados privados indisponiveis',
              message: _errorMessage(snapshot.error!),
            );
          }
          final profile = snapshot.data;
          if (profile == null) {
            return const EmptyState(
              icon: Icons.badge_outlined,
              title: 'Dados privados nao encontrados',
              message: 'Complete seu cadastro para informar CPF e endereco.',
            );
          }
          return _PrivateProfileView(
            profile: profile,
            canEditAddress: _canEditAddress,
          );
        },
      ),
    );
  }

  /// Erros do Firestore viram mensagem amigavel: permission-denied (role
  /// sem acesso ao documento privado) e o caso mais comum de consulta de
  /// UID pelo super admin / acesso indevido.
  String _errorMessage(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Voce nao tem permissao para esta acao.';
      }
      if (error.code == 'not-found') {
        return 'Dados privados nao encontrados.';
      }
    }
    return friendlyErrorMessage(error);
  }
}

class _PrivateProfileView extends StatelessWidget {
  const _PrivateProfileView({
    required this.profile,
    required this.canEditAddress,
  });

  final PrivateProfile profile;
  final bool canEditAddress;

  @override
  Widget build(BuildContext context) {
    final address = profile.address;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _InfoRow(icon: Icons.badge_outlined, label: 'CPF'),
              Text(
                profile.cpfMasked,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Text(
                'Endereco',
                style: TextStyle(
                  color: context.brand.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.lock_outline,
                label: 'CEP',
                value: address.postalCode,
              ),
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.signpost_outlined,
                label: 'Logradouro',
                value: address.street,
              ),
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.tag_outlined,
                label: 'Numero',
                value: address.number,
              ),
              if (address.complement != null &&
                  address.complement!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                _InfoRow(
                  icon: Icons.add_box_outlined,
                  label: 'Complemento',
                  value: address.complement!,
                ),
              ],
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.location_city_outlined,
                label: 'Bairro',
                value: address.neighborhood,
              ),
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.map_outlined,
                label: 'Cidade',
                value: address.city,
              ),
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.flag_outlined,
                label: 'UF',
                value: address.state,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (canEditAddress)
          AppButton(
            key: const Key('private_profile_edit_address_button'),
            label: 'Editar endereco',
            icon: Icons.edit_location_alt_outlined,
            isSecondary: true,
            onPressed: () => _showEditSheet(context, address),
          ),
        const SizedBox(height: 18),
      ],
    );
  }

  void _showEditSheet(BuildContext context, PostalAddress address) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditAddressSheet(address: address),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, this.value});

  final IconData icon;
  final String label;
  final String? value;

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
              if (value != null)
                Text(
                  value!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Formulario de endereco em bottom sheet, sempre dentro de um
/// [SingleChildScrollView] para nao estourar com o teclado aberto
/// (viewInsets aplicado no padding inferior).
class _EditAddressSheet extends StatefulWidget {
  const _EditAddressSheet({required this.address});

  final PostalAddress address;

  @override
  State<_EditAddressSheet> createState() => _EditAddressSheetState();
}

class _EditAddressSheetState extends State<_EditAddressSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cepController;
  late final TextEditingController _streetController;
  late final TextEditingController _numberController;
  late final TextEditingController _complementController;
  late final TextEditingController _neighborhoodController;
  late final TextEditingController _cityController;
  late final TextEditingController _ufController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final address = widget.address;
    _cepController = TextEditingController(text: address.postalCode);
    _streetController = TextEditingController(text: address.street);
    _numberController = TextEditingController(text: address.number);
    _complementController = TextEditingController(
      text: address.complement ?? '',
    );
    _neighborhoodController = TextEditingController(text: address.neighborhood);
    _cityController = TextEditingController(text: address.city);
    _ufController = TextEditingController(text: address.state);
  }

  @override
  void dispose() {
    _cepController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _ufController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 18, 18, bottom + 18),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Editar endereco',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            AppTextField(
              key: const Key('edit_address_cep_field'),
              label: 'CEP',
              controller: _cepController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              validator: _required,
            ),
            const SizedBox(height: 10),
            AppTextField(
              key: const Key('edit_address_street_field'),
              label: 'Logradouro',
              controller: _streetController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: _required,
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    key: const Key('edit_address_number_field'),
                    label: 'Numero',
                    controller: _numberController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    key: const Key('edit_address_complement_field'),
                    label: 'Complemento',
                    controller: _complementController,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AppTextField(
              key: const Key('edit_address_neighborhood_field'),
              label: 'Bairro',
              controller: _neighborhoodController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: _required,
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: AppTextField(
                    key: const Key('edit_address_city_field'),
                    label: 'Cidade',
                    controller: _cityController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    key: const Key('edit_address_uf_field'),
                    label: 'UF',
                    controller: _ufController,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    validator: _required,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppButton(
              key: const Key('edit_address_save_button'),
              label: 'Salvar endereco',
              icon: Icons.save_outlined,
              isLoading: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo obrigatorio';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    final repository = context.read<PrivateProfileRepository>();
    try {
      await repository.updateOwnAddress(
        address: PostalAddress(
          postalCode: _cepController.text.trim(),
          street: _streetController.text.trim(),
          number: _numberController.text.trim(),
          complement: _complementController.text.trim().isEmpty
              ? null
              : _complementController.text.trim(),
          neighborhood: _neighborhoodController.text.trim(),
          city: _cityController.text.trim(),
          state: _ufController.text.trim().toUpperCase(),
        ),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Endereco atualizado.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
