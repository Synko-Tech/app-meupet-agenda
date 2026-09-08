/// Gera uma chave de idempotencia unica por gesto do usuario.
///
/// O servidor deduplica chamadas repetidas com a mesma chave
/// (purchaseIdempotency, appointmentIdempotency, paymentStatusIdempotency,
/// cancelAppointmentIdempotency). Microssegundos desde a epoch mais um
/// contador de sessao garantem unicidade dentro da janela de retry do app.
String newIdempotencyKey() {
  final stamp = DateTime.now().microsecondsSinceEpoch.toString();
  _sequence = (_sequence + 1) & 0xffff;
  return '${stamp}_$_sequence';
}

int _sequence = 0;
