import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/controllers/appointment_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/models/package_model.dart';
import 'package:meupet_agenda_app/models/service_model.dart';
import 'package:meupet_agenda_app/repositories/appointment_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

class MockBusinessContextController extends Mock
    implements BusinessContextController {}

class _FakeCustomerPackage extends Fake implements CustomerPackageModel {}

const _service = ServiceModel(
  id: 's1',
  name: 'Consulta',
  description: 'Consulta veterinaria',
  durationMinutes: 60,
  price: 100,
);

/// Returns a weekday (Mon-Fri) or Sunday date strictly in the future,
/// regardless of the day the test runs.
DateTime _futureDate(int weekday) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var days = (weekday - today.weekday) % 7;
  if (days == 0) {
    days = 7;
  }
  final candidate = today.add(Duration(days: days));
  return candidate.isAfter(now)
      ? candidate
      : candidate.add(const Duration(days: 7));
}

void main() {
  late MockAppointmentRepository repository;
  late MockBusinessContextController businessContext;
  late AppointmentController controller;

  setUpAll(() {
    registerFallbackValue(_service);
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(_FakeCustomerPackage());
  });

  setUp(() {
    repository = MockAppointmentRepository();
    businessContext = MockBusinessContextController();
    when(() => businessContext.activeBusinessId).thenReturn('b1');
    controller = AppointmentController(
      repository: repository,
      businessContext: businessContext,
    );
  });

  test(
    'rejects a past-time appointment before touching the repository',
    () async {
      controller.selectDate(DateTime.now().subtract(const Duration(days: 1)));
      controller.selectTime('09:00');

      await expectLater(
        controller.createAppointment(
          service: _service,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('futuro'),
          ),
        ),
      );

      verifyNever(
        () => repository.createAppointment(
          businessId: any(named: 'businessId'),
          service: any(named: 'service'),
          startAt: any(named: 'startAt'),
          customerPackage: any(named: 'customerPackage'),
        ),
      );
    },
  );

  test(
    'rejects a booking time outside business hours (weekday 18:00)',
    () async {
      controller.selectDate(_futureDate(DateTime.monday));
      controller.selectTime('18:00');

      await expectLater(
        controller.createAppointment(
          service: _service,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('nao esta disponivel'),
          ),
        ),
      );

      verifyNever(
        () => repository.createAppointment(
          businessId: any(named: 'businessId'),
          service: any(named: 'service'),
          startAt: any(named: 'startAt'),
          customerPackage: any(named: 'customerPackage'),
        ),
      );
    },
  );

  test('rejects a booking on Sunday regardless of time', () async {
    controller.selectDate(_futureDate(DateTime.sunday));
    controller.selectTime('09:00');

    await expectLater(
      controller.createAppointment(
        service: _service,
      ),
      throwsStateError,
    );

    verifyNever(
      () => repository.createAppointment(
        businessId: any(named: 'businessId'),
        service: any(named: 'service'),
        startAt: any(named: 'startAt'),
        customerPackage: any(named: 'customerPackage'),
      ),
    );
  });

  test(
    'accepts a valid booking and forwards the wall-clock to the repository',
    () async {
      final monday = _futureDate(DateTime.monday);
      controller.selectDate(monday);
      controller.selectTime('09:00');

      when(
        () => repository.createAppointment(
          businessId: any(named: 'businessId'),
          service: any(named: 'service'),
          startAt: any(named: 'startAt'),
          customerPackage: any(named: 'customerPackage'),
        ),
      ).thenAnswer((_) async => 'appt-1');

      await controller.createAppointment(
        service: _service,
      );

      expect(controller.errorMessage, isNull);
      // Wall-clock 09:00 em America/Sao_Paulo (UTC-3) == instante 12:00 UTC.
      final expectedStartAt = DateTime.utc(
        monday.year,
        monday.month,
        monday.day,
        12,
        0,
      );
      verify(
        () => repository.createAppointment(
          businessId: 'b1',
          service: _service,
          startAt: expectedStartAt,
          customerPackage: null,
        ),
      ).called(1);
    },
  );
}
