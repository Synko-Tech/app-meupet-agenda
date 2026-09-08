import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/brand_mark.dart';
import 'forgot_password_screen.dart';
import 'register_business_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                const Center(child: BrandWordmark(size: 64)),
                const SizedBox(height: 28),
                Text(
                  'Entrar',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                const Text('Agendamentos e pacotes em um so lugar'),
                const SizedBox(height: 18),
                AppTextField(
                  key: const Key('login_email_field'),
                  label: 'E-mail',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: _email,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  key: const Key('login_password_field'),
                  label: 'Senha',
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: _required,
                  onSubmitted: (_) => _submit(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ForgotPasswordScreen(),
                      ),
                    ),
                    child: const Text('Esqueci minha senha'),
                  ),
                ),
                AppButton(
                  key: const Key('login_submit_button'),
                  label: 'Acessar',
                  icon: Icons.login,
                  isLoading: auth.isBusy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 18),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Perfis',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Cliente agenda servicos e consulta saldo. '
                        'Colaborador acompanha atendimentos. '
                        'Administrador gerencia o estabelecimento.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: 'Criar conta cliente',
                  icon: Icons.person_add_alt_1,
                  isSecondary: true,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RegisterScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                AppButton(
                  label: 'Criar conta empresa',
                  icon: Icons.storefront_outlined,
                  isSecondary: true,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RegisterBusinessScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      await context.read<AuthController>().signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      debugPrint(
        'LOGIN_ERRO runtime=${error.runtimeType} '
        'code=${error is FirebaseAuthException ? error.code : 'n/a'} '
        'msg=${error is FirebaseAuthException ? error.message : error}',
      );
      final message =
          context.read<AuthController>().errorMessage ??
          'Nao foi possivel acessar.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
