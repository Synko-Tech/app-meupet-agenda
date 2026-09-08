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
import '../../widgets/brand_mark.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cpfController = TextEditingController();
  final _cepController = TextEditingController();
  final _streetController = TextEditingController();
  final _numberController = TextEditingController();
  final _complementController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _cityController = TextEditingController();
  final _ufController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _cepLoading = false;
  int _cepRequestToken = 0;

  CepService get _cepService => context.read<CepService>();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _cpfController.dispose();
    _cepController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _ufController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: BrandMark(size: 48)),
                  const SizedBox(height: 20),
                  Text(
                    'Criar conta',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text('Crie sua conta para agendar servicos e pacotes.'),
                  const SizedBox(height: 18),
                  AppTextField(
                    key: const Key('register_name_field'),
                    label: 'Nome',
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    key: const Key('register_email_field'),
                    label: 'E-mail',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    validator: _email,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    key: const Key('register_phone_field'),
                    label: 'Telefone',
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    key: const Key('register_cpf_field'),
                    label: 'CPF',
                    controller: _cpfController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [CpfInputFormatter()],
                    validator: validateRequiredCpf,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    key: const Key('register_cep_field'),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    key: const Key('register_street_field'),
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
                          key: const Key('register_number_field'),
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
                          key: const Key('register_complement_field'),
                          label: 'Complemento',
                          controller: _complementController,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    key: const Key('register_neighborhood_field'),
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
                          key: const Key('register_city_field'),
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
                          key: const Key('register_uf_field'),
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
                  const SizedBox(height: 12),
                  AppTextField(
                    key: const Key('register_password_field'),
                    label: 'Senha',
                    controller: _passwordController,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    validator: validatePassword,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    key: const Key('register_confirm_field'),
                    label: 'Confirmar senha',
                    controller: _confirmController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    validator: _confirm,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  AppButton(
                    key: const Key('register_submit_button'),
                    label: 'Cadastrar',
                    icon: Icons.check_circle_outline,
                    isLoading: auth.isBusy,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
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

  String? _email(String? value) {
    final required = _required(value);
    if (required != null) {
      return required;
    }
    final email = value!.trim();
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!valid) {
      return 'Informe um e-mail valido';
    }
    return null;
  }

  String? _confirm(String? value) {
    if (value == null || value.isEmpty) {
      return 'Confirme a senha';
    }
    if (value != _passwordController.text) {
      return 'As senhas nao conferem';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      await context.read<AuthController>().registerClient(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
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
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (!mounted) {
        return;
      }
      final message =
          context.read<AuthController>().errorMessage ??
          'Nao foi possivel cadastrar.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
