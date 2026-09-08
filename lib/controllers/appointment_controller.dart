import 'package:flutter/foundation.dart';

import '../models/appointment_model.dart';
import '../models/package_model.dart';
import '../models/service_model.dart';
import '../repositories/appointment_repository.dart';
import '../services/business_hours.dart';
import '../services/function_error.dart';
import 'business_context_controller.dart';

class AppointmentController extends ChangeNotifier {
  AppointmentController({
    required AppointmentRepository repository,
    required BusinessContextController businessContext,
  }) : _repository = repository,
       _businessContext = businessContext;

  final AppointmentRepository _repository;
  final BusinessContextController _businessContext;

  DateTime selectedDate = DateTime.now();
  String selectedTime = '09:00';
  bool isBusy = false;
  String? errorMessage;

  static const List<String> availableTimes = [
    '08:00',
    '08:30',
    '09:00',
    '09:30',
    '10:00',
    '10:30',
    '11:00',
    '11:30',
    '12:00',
    '12:30',
    '13:00',
    '13:30',
    '14:00',
    '14:30',
    '15:00',
    '15:30',
    '16:00',
    '16:30',
    '17:00',
    '17:30',
    '18:00',
    '18:30',
    '19:00',
    '19:30',
  ];

  String get _businessId {
    final businessId = _businessContext.activeBusinessId;
    if (businessId == null) {
      throw StateError('Nenhuma loja ativa.');
    }
    return businessId;
  }

  void selectDate(DateTime date) {
    selectedDate = date;
    notifyListeners();
  }

  void selectTime(String time) {
    selectedTime = time;
    notifyListeners();
  }

  Future<void> createAppointment({
    required ServiceModel service,
    CustomerPackageModel? customerPackage,
  }) async {
    await _run(() async {
      final startAt = _dateWithSelectedTime();
      if (startAt.isBefore(DateTime.now())) {
        throw StateError('Escolha um horario futuro para o agendamento.');
      }
      if (!BusinessHours.isInsideBookingHours(
        time: selectedTime,
        serviceName: service.name,
        date: selectedDate,
      )) {
        throw StateError('Este horario nao esta disponivel para este servico.');
      }

      await _repository.createAppointment(
        businessId: _businessId,
        service: service,
        startAt: startAt,
        customerPackage: customerPackage,
      );
    });
  }

  Future<void> cancelAppointment(AppointmentModel appointment) {
    return _run(() => _repository.cancelAppointment(_businessId, appointment));
  }

  DateTime _dateWithSelectedTime() {
    final parts = selectedTime.split(':');
    final hour = int.tryParse(parts.first) ?? 9;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    // Wall-clock em America/Sao_Paulo (o fuso do negocio). O backend calcula
    // business hours, dayKey e slot locks convertendo o instante recebido para
    // Sao Paulo (functions/src/appointments/slot-keys.ts). Se construirmos um
    // DateTime local aqui, um dispositivo em outro fuso (ex.: Manaus, UTC-4)
    // enviaria "09:00" que o servidor interpretaria como 10:00 em SP. Sao
    // Paulo e UTC-3 fixo (sem DST desde 2019), entao somamos 3h aos
    // componentes e construimos em UTC: o instante resultante exibe 09:00
    // quando convertido para America/Sao_Paulo.
    return DateTime.utc(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      hour + 3,
      minute,
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = friendlyErrorMessage(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}
