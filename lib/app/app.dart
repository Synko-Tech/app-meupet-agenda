import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/admin_controller.dart';
import '../controllers/appointment_controller.dart';
import '../controllers/auth_controller.dart';
import '../controllers/business_context_controller.dart';
import '../controllers/merchant_connection_controller.dart';
import '../controllers/package_controller.dart';
import '../controllers/theme_controller.dart';
import '../repositories/appointment_repository.dart';
import '../repositories/auth_repository.dart';
import '../repositories/business_repository.dart';
import '../repositories/merchant_connection_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/package_repository.dart';
import '../repositories/payment_repository.dart';
import '../repositories/private_profile_repository.dart';
import '../repositories/service_repository.dart';
import '../repositories/user_repository.dart';
import '../services/cep_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../widgets/environment_banner.dart';
import 'app_theme.dart';
import 'auth_gate.dart';

class MeuPetAgendaApp extends StatelessWidget {
  const MeuPetAgendaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => UserRepository()),
        Provider(create: (_) => BusinessRepository()),
        Provider(create: (_) => MerchantConnectionRepository()),
        Provider(create: (_) => ServiceRepository()),
        Provider(create: (_) => PackageRepository()),
        Provider(create: (_) => AppointmentRepository()),
        Provider(create: (_) => PaymentRepository()),
        Provider(create: (_) => NotificationRepository()),
        Provider(create: (_) => StorageService()),
        Provider(create: (_) => NotificationService()),
        Provider(create: (_) => PrivateProfileRepository()),
        Provider(create: (_) => CepService()),
        Provider(
          create: (context) => AuthRepository(
            privateProfileRepository: context.read<PrivateProfileRepository>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => AuthController(
            authRepository: context.read<AuthRepository>(),
            userRepository: context.read<UserRepository>(),
            notificationService: context.read<NotificationService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => BusinessContextController(
            repository: context.read<BusinessRepository>(),
            authController: context.read<AuthController>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => MerchantConnectionController(
            repository: context.read<MerchantConnectionRepository>(),
            businessContext: context.read<BusinessContextController>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => AppointmentController(
            repository: context.read<AppointmentRepository>(),
            businessContext: context.read<BusinessContextController>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => PackageController(
            packageRepository: context.read<PackageRepository>(),
            businessContext: context.read<BusinessContextController>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => AdminController(
            serviceRepository: context.read<ServiceRepository>(),
            packageRepository: context.read<PackageRepository>(),
            userRepository: context.read<UserRepository>(),
            authController: context.read<AuthController>(),
            businessContext: context.read<BusinessContextController>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: const _AppView(),
    );
  }
}

class _AppView extends StatelessWidget {
  const _AppView();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeuPet Agenda',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: context.watch<ThemeController>().mode,
      builder: (context, child) => Stack(
        textDirection: TextDirection.ltr,
        children: [
          ?child,
          const Positioned(top: 0, left: 0, child: EnvironmentBanner()),
        ],
      ),
      home: const AuthGate(),
    );
  }
}
