import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/profile_input_formatters.dart';
import '../../controllers/auth_controller.dart';
import '../../models/postal_address.dart';
import '../../services/cep_service.dart';
import '../../services/profile_validators.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

/// Tela de complementacao de cadastro para usuarios legados
/// (`profileComplete == false`): coleta nome, telefone, CPF e endereco e
/// chama o callable `completeOwnProfile`.
///
/// Permanece aberta em erro; quando o callable grava
/// `profileComplete: true`, a stream do [AuthController] notifica o gate,
/// que troca esta tela pelo shell sem navegacao manual.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cpfController = TextEditingController();
  final _cepController = TextEditingController();
  final _streetController = TextEditingController();
  final _numberController = TextEditingController();
  final _complementController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _cityController = TextEditingController();
  final _ufController = TextEditingController();

  bool _initialized = false;
  bool _cepLoading = false;
  int _cepRequestToken = 0;

  CepService get _cepService => context.read<CepService>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    // Nome e telefone ja conhecidos do perfil global sao preenchidos e
    // editaveis: o callable exige nome e o telefone e opcional.
    final profile = context.read<AuthController>().profile;
    if (profile != null) {
      _nameController.text = profile.name;
      _phoneController.text = profile.phone ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _cpfController.dispose();
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
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Complete seu cadastro')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Antes de comecar, precisamos do seu CPF e endereco para '
                'identificar voce e garantir a seguranca dos agendamentos '
                'e pagamentos.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('complete_profile_logout_button'),
                onPressed: () => context.read<AuthController>().signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sair'),
              ),
              const SizedBox(height: 20),
              AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(
                        key: const Key('complete_profile_name_field'),
                        label: 'Nome',
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        key: const Key('complete_profile_phone_field'),
                        label: 'Telefone',
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.telephoneNumber],
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        key: const Key('complete_profile_cpf_field'),
                        label: 'CPF',
                        controller: _cpfController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [CpfInputFormatter()],
                        validator: validateRequiredCpf,
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        key: const Key('complete_profile_cep_field'),
                        label: 'CEP',
                        controller: _cepController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [CepInputFormatter()],
                        autofillHints: const [AutofillHints.postalCode],
                        validator: validateRequiredCep,
                        onChanged: _onCepChanged,
                        suffixIcon: _cepLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        key: const Key('complete_profile_street_field'),
                        label: 'Logradouro',
                        controller: _streetController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.streetAddressLine1],
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AppTextField(
                              key: const Key('complete_profile_number_field'),
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
                              key: const Key(
                                'complete_profile_complement_field',
                              ),
                              label: 'Complemento',
                              controller: _complementController,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        key: const Key('complete_profile_neighborhood_field'),
                        label: 'Bairro',
                        controller: _neighborhoodController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: AppTextField(
                              key: const Key('complete_profile_city_field'),
                              label: 'Cidade',
                              controller: _cityController,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.addressCity],
                              validator: _required,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              key: const Key('complete_profile_uf_field'),
                              label: 'UF',
                              controller: _ufController,
                              textCapitalization: TextCapitalization.characters,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.addressState],
                              validator: validateRequiredUf,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      AppButton(
                        key: const Key('complete_profile_submit_button'),
                        label: 'Salvar',
                        icon: Icons.check_circle_outline,
                        isLoading: auth.isBusy,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onCepChanged(String value) {
    if (digitsOnly(value).length != 8) {
      return;
    }
    unawaited(_lookupCep(digitsOnly(value)));
  }

  Future<void> _lookupCep(String cep) async {
    final token = ++_cepRequestToken;
    setState(() => _cepLoading = true);
    try {
      final lookup = await _cepService.lookup(cep);
      if (!mounted || token != _cepRequestToken) {
        return;
      }
      setState(() {
        _cepLoading = false;
        _streetController.text = lookup.street;
        _neighborhoodController.text = lookup.neighborhood;
        _cityController.text = lookup.city;
        _ufController.text = lookup.state;
      });
    } on CepException catch (error) {
      if (!mounted || token != _cepRequestToken) {
        return;
      }
      setState(() => _cepLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cepMessage(error))));
    } catch (_) {
      // Erro inesperado (nao-CepException): nunca deixar o loading preso.
      if (!mounted || token != _cepRequestToken) {
        return;
      }
      setState(() => _cepLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel consultar o CEP. Tente novamente.'),
        ),
      );
    }
  }

  String _cepMessage(CepException error) {
    return switch (error.kind) {
      CepExceptionKind.invalid => 'CEP invalido.',
      CepExceptionKind.notFound => 'CEP nao encontrado.',
      CepExceptionKind.unavailable =>
        'Servico de CEP indisponivel. Tente novamente.',
    };
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

    try {
      await context.read<AuthController>().completeOwnProfile(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        cpf: digitsOnly(_cpfController.text),
        address: PostalAddress(
          postalCode: digitsOnly(_cepController.text),
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
      // Nenhuma navegacao aqui: o gate fecha esta tela quando a stream do
      // perfil notifica profileComplete: true.
    } catch (_) {
      if (!mounted) {
        return;
      }
      final message =
          context.read<AuthController>().errorMessage ??
          'Nao foi possivel completar o cadastro.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
