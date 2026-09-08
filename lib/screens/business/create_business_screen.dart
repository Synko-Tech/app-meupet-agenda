import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/business_context_controller.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

/// Onboarding do owner: cria a primeira loja. O backend grava
/// `businesses/{id}` e o membership `owner` na mesma transacao; ao concluir,
/// o app seleciona a loja recem-criada como ativa.
class CreateBusinessScreen extends StatefulWidget {
  const CreateBusinessScreen({super.key});

  @override
  State<CreateBusinessScreen> createState() => _CreateBusinessScreenState();
}

class _CreateBusinessScreenState extends State<CreateBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final businessContext = context.watch<BusinessContextController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Criar loja')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 42,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Crie sua loja',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Voce sera o dono (owner) e podera configurar o recebimento '
                  'de pagamentos depois, no perfil.',
                ),
                const SizedBox(height: 18),
                AppTextField(
                  label: 'Nome da loja',
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Descricao (opcional)',
                  controller: _descriptionController,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 20),
                AppButton(
                  label: 'Criar loja',
                  icon: Icons.check_circle_outline,
                  isLoading: businessContext.isBusy,
                  onPressed: _submit,
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final controller = context.read<BusinessContextController>();
    try {
      await controller.createBusiness(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
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
          controller.errorMessage ?? 'Nao foi possivel criar a loja.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
