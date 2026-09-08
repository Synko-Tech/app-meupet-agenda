import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/app/profile_input_formatters.dart';
import 'package:meupet_agenda_app/widgets/app_text_field.dart';

void main() {
  Future<void> pump(WidgetTester tester, AppTextField field) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Form(child: Center(child: field)),
        ),
      ),
    );
  }

  group('AppTextField', () {
    testWidgets('renders label and accepts input', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(tester, AppTextField(label: 'E-mail', controller: controller));
      await tester.enterText(find.byType(TextFormField), 'a@b.com');
      expect(controller.text, 'a@b.com');
    });

    testWidgets('password field toggles visibility', (tester) async {
      final controller = TextEditingController(text: 'segredo');
      addTearDown(controller.dispose);
      await pump(
        tester,
        AppTextField(label: 'Senha', controller: controller, obscureText: true),
      );
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      await tester.tap(find.byTooltip('Mostrar senha'));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });

    testWidgets('runs validator and surfaces error text', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Form(
              key: formKey,
              child: AppTextField(
                label: 'Nome',
                controller: controller,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Informe o nome' : null,
              ),
            ),
          ),
        ),
      );
      formKey.currentState!.validate();
      await tester.pump();
      expect(find.text('Informe o nome'), findsOneWidget);
    });

    testWidgets('meets labeled tap target guideline', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        AppTextField(
          label: 'Telefone',
          controller: controller,
          obscureText: true,
        ),
      );
      final handle = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('applies input formatters to typed text', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        AppTextField(
          label: 'CPF',
          controller: controller,
          inputFormatters: [CpfInputFormatter()],
        ),
      );
      await tester.enterText(find.byType(TextFormField), '52998224725');
      expect(controller.text, '529.982.247-25');
    });

    testWidgets('passes textCapitalization to the text field', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        AppTextField(
          label: 'Nome',
          controller: controller,
          textCapitalization: TextCapitalization.characters,
        ),
      );
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.textCapitalization, TextCapitalization.characters);
    });

    testWidgets('revalidates on user interaction with autovalidateMode', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'x');
      addTearDown(controller.dispose);
      await pump(
        tester,
        AppTextField(
          label: 'CPF',
          controller: controller,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Campo obrigatorio' : null,
        ),
      );
      await tester.enterText(find.byType(TextFormField), '');
      await tester.pump();
      expect(find.text('Campo obrigatorio'), findsOneWidget);
    });

    testWidgets('uses the provided focus node', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      await pump(
        tester,
        AppTextField(
          label: 'Nome',
          controller: controller,
          focusNode: focusNode,
        ),
      );
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode, same(focusNode));
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
    });
  });
}
