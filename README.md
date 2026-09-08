# MeuPet Agenda

[![CI](https://github.com/Synko-Tech/app-meupet-agenda/actions/workflows/ci.yml/badge.svg)](https://github.com/Synko-Tech/app-meupet-agenda/actions/workflows/ci.yml)

Aplicativo Flutter com Firebase para gestao de agendamentos, pacotes de
servicos, pagamentos simples e painel administrativo para pequenos
estabelecimentos.

## Integracao continua — atividade GitHub Actions

A pipeline esta em `.github/workflows/ci.yml` e executa em pushes de qualquer
branch, pull requests e acionamento manual pela aba **Actions**. Usa Ubuntu
24.04, Java 17 e Flutter 3.47.1, com as dependencias fixadas em `pubspec.lock`.

1. Instala dependencias: `flutter pub get --enforce-lockfile`.
2. Analisa o codigo: `flutter analyze --no-pub`.
3. Executa testes unitarios e de widgets com cobertura:
   `flutter test --no-pub --coverage --reporter expanded`.
4. Faz o build Android: `flutter build apk --debug --no-pub`.
5. Disponibiliza o APK e `coverage/lcov.info` como artefatos por sete dias.

Uma falha de instalacao, analise, teste ou build faz a pipeline falhar. O APK
fica em **Actions > CI > execucao > Artifacts > meupet-agenda-debug**.
E um build de depuracao que usa os emuladores locais de Firebase; nao e uma
publicacao na Play Store. Os testes desta pipeline nao precisam de credenciais
de producao nem de emulador Android.

Os testes unitarios adicionados para a atividade estao em
`test/services/password_validator_test.dart`: cobrem entradas vazias, tamanho
minimo, maiuscula, numero, caractere especial e senhas validas. Eles chamam o
validador real, sem simular sua implementacao. Tambem existem testes unitarios
de modelos, controllers e outros servicos nas respectivas pastas de `test/`.

Para repetir a pipeline localmente, execute os quatro comandos acima na raiz
do projeto. O build exige Android SDK e Java 17. As suites de Firebase e E2E
descritas abaixo sao verificacoes adicionais e nao fazem parte deste workflow.

**Entrega no AVA:** informe a URL abaixo depois de verificar uma execucao
verde da pipeline no GitHub. Este repositorio e privado por escolha do
proprietario; o professor precisa receber acesso para avaliar. O enunciado
original pede repositorio publico, portanto a visibilidade privada difere
desse requisito. O badge mostra o resultado real para quem tem acesso.

Repositorio da entrega: [Synko-Tech/app-meupet-agenda](https://github.com/Synko-Tech/app-meupet-agenda).

## Stack

- Flutter
- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Firebase Cloud Messaging
- Provider para gerenciamento de estado

## Estrutura

- `lib/models`: modelos compatíveis com Firestore
- `lib/repositories`: acesso a Firebase Auth e Firestore
- `lib/services`: Storage, notificacoes e camada futura de pagamento
- `lib/controllers`: providers com estado e acoes de negocio
- `lib/screens`: telas de login, agenda, pacotes, pagamentos e painel
- `lib/widgets`: componentes reutilizaveis

## Colecoes Firestore

- `users`
- `services`
- `packages`
- `customerPackages`
- `appointments`
- `payments`
- `notifications`
- `packageUsage`

As regras iniciais ficam em `firestore.rules` e `storage.rules`.

## Permissoes

- `client`: agenda servicos, consulta pacotes e pagamentos proprios.
- `collaborator`: visualiza areas operacionais.
- `admin`: gerencia catalogo de servicos e pacotes.
- `super_admin`: gerencia calendario administrativo.

Pagamentos sao somente leitura no app: o status vem exclusivamente do webhook
do Mercado Pago (veja abaixo). O calendario administrativo fica
restrito a `super_admin`.

## Mercado Pago (Checkout Pro)

O fluxo de compra de pacotes usa o Mercado Pago Checkout Pro: o app chama o
callable `createMercadoPagoCheckout`, recebe o `initPoint` e abre o navegador
externo. Apenas o webhook `mercadoPagoWebhook` altera o status do pagamento
(PENDENTE, EM_ANALISE, PAGO, CANCELADO, REEMBOLSADO) — o app nao tem mais
atualizacao manual de status.

Variaveis de ambiente em `functions/.env`:

- `MERCADOPAGO_ACCESS_TOKEN`: access token da conta Mercado Pago (obrigatorio).
- `MERCADOPAGO_WEBHOOK_URL`: URL publica HTTPS do webhook, ex.:
  `https://southamerica-east1-<projeto>.cloudfunctions.net/mercadoPagoWebhook`
  (no emulador: `http://127.0.0.1:5001/<projeto>/southamerica-east1/mercadoPagoWebhook`).
- `MERCADOPAGO_WEBHOOK_SECRET`: segredo configurado no painel de notificacoes
  do Mercado Pago. **Obrigatorio em producao** — sem ele o webhook recusa
  requisicoes (fail closed); no emulador ele pode ficar ausente.

## Comandos uteis

```bash
flutter pub get
dart analyze
flutter test
flutter build apk --debug
python3 -m pip install --user google-cloud-firestore
GOOGLE_APPLICATION_CREDENTIALS=/caminho/para/key.json python3 scripts/audit_firestore.py --project meupet-agenda-app
GOOGLE_APPLICATION_CREDENTIALS=/caminho/para/key.json python3 scripts/backfill_slot_locks.py --project meupet-agenda-app --dry-run
```

## Ambiente (emuladores x producao)

O app decide o backend pelo **modo de build**, sem precisar de flags:

- **Debug** (`flutter run`, `flutter build apk --debug`): usa a suite local de
  emuladores por padrao — um install debug nunca toca em dados de producao.
  O app exibe o selo `LOCAL` no canto para deixar isso visivel.
- **Release** (`flutter build apk --release`): usa o Firebase de producao.

Para forcar um ambiente em qualquer build, use o override explicito:

```bash
flutter run --dart-define=USE_FIREBASE_EMULATORS=true
flutter run --dart-define=USE_FIREBASE_EMULATORS=false
```

O host do emulador visto do dispositivo Android e `10.0.2.2` (loopback da
maquina host); use `localhost` em desktop com
`--dart-define=FIREBASE_EMULATOR_HOST=localhost`. A configuracao compartilhada
vive em `lib/app/firebase_emulators.dart` e e usada por `main.dart` e pelos
testes E2E.

### Desenvolvimento local (emulador persistente)

Para desenvolver/testar no app, suba a suite de emuladores num terminal
dedicado (deixe aberto) com o MESMO project id do app:

```bash
scripts/start-dev.sh          # sobe os emuladores + seed de dados de teste
scripts/start-dev.sh --no-seed
scripts/stop-dev.sh           # encerra a suite
```

> **Importante:** o emulador de Functions roteia por project id. Iniciar com
> outro projeto (ex.: `demo-meupet-agenda`) faz os callables do app retornarem
> 404 e a tela mostrar "Servico indisponivel no momento. Tente novamente mais
> tarde." — sempre use `--project meupet-agenda-app`.

Usuarios do emulador local (seed em `functions/seed-emulator.js`):

- Cliente: `alice@exemplo.com` / `senha-forte-123`
- Administrador: `admin@exemplo.com` / `senha-forte-admin`

Essas credenciais sao exclusivas de desenvolvimento e nunca devem espelhar
contas de producao.
GOOGLE_APPLICATION_CREDENTIALS=/caminho/para/key.json python3 scripts/reconcile_packages_payments.py --project meupet-agenda-app
GOOGLE_APPLICATION_CREDENTIALS=/caminho/para/key.json python3 scripts/backfill_payment_created_at.py --project meupet-agenda-app --dry-run
```

## Testes

Todas as suítes de emulador exigem um project id `demo-*` (nunca o projeto de
producao) e falham na inicializacao caso o id nao comece com `demo-`:

```bash
# Regras (Firestore + Storage) e Cloud Functions contra os emuladores.
# `auth` e incluido: os testes de completeOwnProfile usam o Admin SDK para
# semear/ler usuarios do Auth Emulator.
npx firebase emulators:exec --project demo-meupet-agenda \
  --only auth,firestore,storage,functions \
  "npm --prefix firebase-tests test && npm --prefix functions test"

# Cobertura Flutter (unit + widget).
flutter test --coverage
```

### Teste de integracao no dispositivo (E2E)

Semeia o emulador (Auth + Firestore via Admin SDK, que ignora regras) e roda o
fluxo critico (login, senha invalida, agendamento, compra de pacote e logout)
num emulador Android:

```bash
firebase emulators:exec --project meupet-agenda-app \
  --only auth,firestore,storage,functions \
  "node functions/seed-emulator.js && \
   flutter test integration_test/critical_flows_test.dart \
     -d emulator-5554 \
     --dart-define=USE_FIREBASE_EMULATORS=true \
     --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2"
```

Diferente das suites `demo-*`, o E2E roda com o project id do proprio app
(`meupet-agenda-app`): o namespace do Auth Emulator e por projeto, e o app
Android e inicializado com o google-services.json de producao — os usuarios
semeados so sao encontrados quando emulador e seed usam o mesmo id. O seed
sai seguro: ele recusa qualquer host de emulador fora de `127.0.0.1`/`localhost`,
entao nunca toca em producao. (As suites de regras/functions ficam em
`demo-*` por serem autocontidas, sem dados semeados.)

`10.0.2.2` e o loopback do emulador Android para a maquina host; use
`localhost` em desktop.

### Politicas protegidas por teste

- Agendamento no passado ou que termine apos o expediente: rejeitado no
  backend.
- Pacote vencido nunca e consumido (backend e `canUse` no app).
- Agendamento `CONCLUIDO` nao pode ser cancelado com restituicao.
- Escritas financeiras (agendamentos, `customerPackages`, `payments`,
  `packageUsage`) sao exclusivas das Cloud Functions; regras negam SDK de
  cliente, inclusive para staff.
- Usuario inativo perde acesso ao Storage e aos privilegios de role.

## Migracao de dados

- `firestore.indexes.json`: indices compostos — `payments` (id_cliente + createdAt) para o filtro por periodo; consultas por campo unico nao precisam de indice.
- `scripts/backfill_slot_locks.py`: cria docs `appointmentSlots` para agendamentos futuros AGENDADO/CONFIRMADO criados antes das travas de horario; aborta se dois agendamentos caem no mesmo slot; rode `--dry-run` primeiro.
- `scripts/reconcile_packages_payments.py`: lista pacotes ATIVO sem pagamento PAGO confirmado (somente leitura, nao altera dados).
- `scripts/backfill_payment_created_at.py`: preenche `createdAt` em pagamentos legados (fonte: `paidAt` -> `data_pagamento` -> createTime do documento) para o filtro por periodo funcionar; nunca sobrescreve `createdAt` existente; rode `--dry-run` primeiro e use `--apply` para gravar.

## Observacoes

O projeto esta configurado para Android no Firebase `meupet-agenda-app`.
Pagamentos e notificacoes possuem camadas preparadas para integracao futura com
gateway e Cloud Functions.

## Firebase

O Firestore foi criado em `southamerica-east1` e as regras de
`firestore.rules` foram publicadas. Para o cadastro funcionar, habilite no
Console Firebase:

1. Authentication
2. Sign-in method
3. Email/Password

Depois execute o bootstrap do administrador inicial, informando as credenciais
via parametros:

```powershell
.\scripts\seed_super_admin.ps1 -Email "seu-email" -Password "sua-senha-forte" -ApiKey "sua-web-api-key"
```

A Web API Key do projeto fica no Console Firebase (Configuracoes do projeto >
Geral). Nao commite credenciais nem chaves no repositorio.

Troque a senha apos o primeiro acesso.

## Agenda

Agendamentos novos gravam `dayKey` e `timeKey` alem dos timestamps. Esses
campos separam corretamente cada dia e evitam que um horario ocupado na segunda
bloqueie outro dia.
