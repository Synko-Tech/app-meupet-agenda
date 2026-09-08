# Relatório — Atividade IA e TDD

**Projeto:** MeuPet Agenda  
**Data da execução:** 08/09/2026  
**Tecnologia:** Flutter/Dart com Firebase Authentication

## 1. Interpretação da atividade

O documento anexado foi tratado como a especificação da atividade. Os requisitos extraídos foram:

1. analisar o projeto e localizar a função responsável pela autenticação do usuário;
2. gerar testes automatizados;
3. validar senha com no mínimo 8 caracteres;
4. exigir pelo menos uma letra maiúscula;
5. exigir pelo menos um número;
6. exigir pelo menos um caractere especial;
7. executar os testes;
8. salvar este relatório em formato Markdown na pasta principal do projeto.

O pedido do usuário foi aplicado ao projeto localizado em `C:\Users\braga\Documents\TCC\meupet_agenda_app`.

## 2. Fluxo de autenticação encontrado

O login de usuário segue este fluxo:

```text
LoginScreen
  -> AuthController.signIn()
  -> AuthRepository.signIn()
  -> FirebaseAuth.signInWithEmailAndPassword()
```

Referências:

- `lib/controllers/auth_controller.dart:47` — entrada do login no controller;
- `lib/repositories/auth_repository.dart:25` — método de login;
- `lib/repositories/auth_repository.dart:26` — chamada ao Firebase Authentication.

O cadastro de usuário, que é o ponto correto para validar força de senha, segue este fluxo:

```text
RegisterScreen / RegisterBusinessScreen
  -> AuthController.registerClient() / registerBusiness()
  -> AuthRepository.register() / registerBusiness()
  -> FirebaseAuth.createUserWithEmailAndPassword()
```

Referências:

- `lib/controllers/auth_controller.dart:51` e `lib/controllers/auth_controller.dart:71`;
- `lib/repositories/auth_repository.dart:41` e `lib/repositories/auth_repository.dart:114`.

O login continua aceitando a senha existente para autenticar. As regras de complexidade foram aplicadas ao cadastro, antes da chamada de criação da conta.

## 3. Diagnóstico inicial

Antes da alteração, as duas telas de cadastro possuíam uma validação privada que aceitava senhas com apenas 6 caracteres. Não havia verificação de letra maiúscula, número ou caractere especial.

## 4. Implementação realizada

Foi criado o validador compartilhado `validatePassword` em `lib/services/profile_validators.dart:91`, com as seguintes regras:

| Regra | Resultado esperado |
|---|---|
| Campo vazio | `Campo obrigatorio` |
| Menos de 8 caracteres | `A senha deve ter no minimo 8 caracteres` |
| Sem letra maiúscula | `A senha deve conter ao menos uma letra maiuscula` |
| Sem número | `A senha deve conter ao menos um numero` |
| Sem caractere especial | `A senha deve conter ao menos um caractere especial` |
| Senha válida | sem mensagem de erro |

O validador foi conectado às duas telas:

- `lib/screens/auth/register_screen.dart:226`;
- `lib/screens/auth/register_business_screen.dart:156`.

## 5. Testes automatizados adicionados

Foram adicionados quatro cenários de formulário em `test/screens/auth/register_screen_test.dart`:

| Cenário | Senha usada | Comportamento verificado |
|---|---|---|
| Tamanho mínimo | `Ab1!xyz` | cadastro rejeitado por ter 7 caracteres |
| Letra maiúscula | `senha@123` | cadastro rejeitado |
| Número | `Senha@abc` | cadastro rejeitado |
| Caractere especial | `Senha123` | cadastro rejeitado |

Cada teste confirma também que `AuthController.registerClient` não é chamado quando a senha é inválida. O fluxo válido foi atualizado para usar `Senha@123`.

Os testes já existentes do cadastro empresarial também foram ajustados para usar uma senha compatível, e essa tela utiliza o mesmo validador compartilhado.

## 6. Execução em TDD

### RED

Os quatro testes foram escritos antes da correção da implementação e executados com:

```text
flutter test test/screens/auth/register_screen_test.dart
```

Resultado: **4 falhas**, pois a implementação anterior não rejeitava as senhas sem maiúscula, sem número ou sem caractere especial e usava a mensagem de mínimo de 6 caracteres.

### GREEN

Após a implementação do validador compartilhado, o mesmo teste foi executado novamente:

```text
flutter test test/screens/auth/register_screen_test.dart
```

Resultado: **17 testes passaram**.

## 7. Verificação final

Comandos executados após a alteração:

```text
flutter analyze
```

Resultado: **No issues found**.

```text
flutter test
```

Resultado: **562 testes passaram** e o processo terminou com código de saída 0.

Também foi executado o teste específico da tela empresarial:

```text
flutter test test/screens/auth/register_business_screen_test.dart
```

Resultado: **10 testes passaram**.

Durante a suíte completa apareceu um aviso de hit-test já existente em `admin_calendar_screen_test.dart`; ele não causou falha e não está relacionado à validação de senha.

## 8. Conclusão

Os quatro requisitos de segurança de senha da atividade foram implementados e cobertos por testes automatizados. A validação ocorre antes da chamada de autenticação/cadastro, impede o envio de senhas inválidas ao controller e é reutilizada nos cadastros de cliente e empresa.

