import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../controllers/business_context_controller.dart';
import '../screens/account/complete_profile_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/business/business_selector_screen.dart';
import '../screens/business/create_business_screen.dart';
import '../screens/home/home_shell.dart';

/// Gate raiz de autenticacao: mostra splash, telas de perfil ausente/desativado,
/// login, complementacao de cadastro (CPF/endereco) ou o shell de acordo com
/// o estado do [AuthController].
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (auth.isLoading) {
      return const _SplashScreen();
    }

    if (auth.firebaseUser != null && auth.profile == null) {
      return const _MissingProfileScreen();
    }

    if (auth.profile != null && !auth.profile!.isActive) {
      return const _BlockedProfileScreen();
    }

    if (!auth.isAuthenticatedAndActive) {
      return const LoginScreen();
    }

    if (!auth.profile!.profileComplete) {
      return const CompleteProfileScreen();
    }

    return const BusinessGate();
  }
}

/// Gate de contexto de loja: o usuario so acessa o shell apos escolher a
/// loja ativa. Sem membership, staff entra no onboarding de criacao da
/// primeira loja; clientes vao direto ao shell (a loja os adiciona depois).
class BusinessGate extends StatelessWidget {
  const BusinessGate({super.key});

  @override
  Widget build(BuildContext context) {
    final business = context.watch<BusinessContextController>();
    final auth = context.watch<AuthController>();

    if (business.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (business.memberships.isEmpty) {
      if (auth.profile?.isStaff ?? false) {
        return const CreateBusinessScreen();
      }
      return const HomeShell();
    }

    if (!business.hasActiveBusiness) {
      return const BusinessSelectorScreen();
    }

    return const HomeShell();
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _MissingProfileScreen extends StatelessWidget {
  const _MissingProfileScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off_outlined, size: 42),
              const SizedBox(height: 12),
              Text(
                'Perfil nao encontrado',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'A autenticacao existe, mas o documento do usuario ainda nao '
                'esta disponivel no Firestore.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.read<AuthController>().signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sair'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedProfileScreen extends StatelessWidget {
  const _BlockedProfileScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block_outlined, size: 42),
              const SizedBox(height: 12),
              Text(
                'Conta desativada',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Conta desativada. Entre em contato com o estabelecimento.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.read<AuthController>().signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sair'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
