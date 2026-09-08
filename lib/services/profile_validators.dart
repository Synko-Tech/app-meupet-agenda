/// Validation helpers for the CPF and address fields of the profile
/// registration flow.
///
/// All validators keep the mask out of the canonical value: digits-only
/// strings are what gets persisted and submitted.
library;

/// Returns [value] with every non-digit character removed.
String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

/// Returns true when [value] contains a structurally valid CPF:
/// 11 digits, not an all-equal repeated sequence, and matching the two
/// standard verifier digits.
bool isValidCpf(String value) {
  final digits = digitsOnly(value);
  if (digits.length != 11) return false;
  if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return false;

  final first = _verifierDigit(digits.substring(0, 9));
  if (int.parse(digits[9]) != first) return false;

  final second = _verifierDigit(digits.substring(0, 10));
  if (int.parse(digits[10]) != second) return false;

  return true;
}

/// Validates a required CPF field: null/blank is "Campo obrigatorio",
/// anything that is not a valid CPF is "CPF invalido".
String? validateRequiredCpf(String? value) {
  if (value == null || value.trim().isEmpty) return 'Campo obrigatorio';
  if (!isValidCpf(value)) return 'CPF invalido';
  return null;
}

/// Validates a required CEP field: null/blank is "Campo obrigatorio",
/// anything without exactly 8 digits is "CEP invalido".
String? validateRequiredCep(String? value) {
  if (value == null || value.trim().isEmpty) return 'Campo obrigatorio';
  if (digitsOnly(value).length != 8) return 'CEP invalido';
  return null;
}

/// Returns true when [value] contains a structurally valid CNPJ:
/// 14 digits, not an all-equal repeated sequence, and matching the two
/// standard verifier digits.
bool isValidCnpj(String value) {
  final digits = digitsOnly(value);
  if (digits.length != 14) return false;
  if (RegExp(r'^(\d)\1{13}$').hasMatch(digits)) return false;

  const firstWeights = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  const secondWeights = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  if (_cnpjVerifierDigit(digits.substring(0, 12), firstWeights) !=
      int.parse(digits[12])) {
    return false;
  }
  if (_cnpjVerifierDigit(digits.substring(0, 13), secondWeights) !=
      int.parse(digits[13])) {
    return false;
  }

  return true;
}

/// Validates a required CNPJ field: null/blank is "Campo obrigatorio",
/// anything that is not a valid CNPJ is "CNPJ invalido".
String? validateRequiredCnpj(String? value) {
  if (value == null || value.trim().isEmpty) return 'Campo obrigatorio';
  if (!isValidCnpj(value)) return 'CNPJ invalido';
  return null;
}

/// Formats digits into the `00.000.000/0000-00` mask. Partial input is
/// masked progressively and extra digits beyond 14 are ignored.
String formatCnpj(String value) =>
    _formatMasked(value, 14, const {1: '.', 4: '.', 7: '/', 11: '-'});

/// Validates a required UF field: null/blank is "Campo obrigatorio",
/// anything that is not exactly two letters is "UF invalida". Case
/// insensitive.
String? validateRequiredUf(String? value) {
  if (value == null || value.trim().isEmpty) return 'Campo obrigatorio';
  final uf = value.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(uf)) return 'UF invalida';
  return null;
}

/// Validates a password for account creation: at least eight characters,
/// one uppercase letter, one number, and one special character.
String? validatePassword(String? value) {
  if (value == null || value.trim().isEmpty) return 'Campo obrigatorio';
  if (value.length < 8) {
    return 'A senha deve ter no minimo 8 caracteres';
  }
  if (!RegExp(r'[A-Z]').hasMatch(value)) {
    return 'A senha deve conter ao menos uma letra maiuscula';
  }
  if (!RegExp(r'\d').hasMatch(value)) {
    return 'A senha deve conter ao menos um numero';
  }
  if (!RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
    return 'A senha deve conter ao menos um caractere especial';
  }
  return null;
}

/// Formats digits into the `000.000.000-00` mask. Partial input is masked
/// progressively and extra digits beyond 11 are ignored.
String formatCpf(String value) =>
    _formatMasked(value, 11, const {2: '.', 5: '.', 8: '-'});

/// Formats digits into the `00000-000` mask. Partial input is masked
/// progressively and extra digits beyond 8 are ignored.
String formatCep(String value) => _formatMasked(value, 8, const {4: '-'});

/// Computes the verifier digit for [digits] using the standard Brazilian
/// algorithm (weighted sum from 10..2, `11 - remainder`, 0 when >= 10).
int _verifierDigit(String digits) {
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    sum += int.parse(digits[i]) * (digits.length + 1 - i);
  }
  final digit = 11 - (sum % 11);
  return digit >= 10 ? 0 : digit;
}

/// Computes one CNPJ verifier digit over [digits] with the given
/// [weights] (weighted sum, `11 - remainder`, 0 when remainder < 2).
int _cnpjVerifierDigit(String digits, List<int> weights) {
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    sum += int.parse(digits[i]) * weights[i];
  }
  final remainder = sum % 11;
  return remainder < 2 ? 0 : 11 - remainder;
}

/// Builds a masked string from up to [maxDigits] digits, writing the
/// separator mapped to each index after it (only when more digits follow).
String _formatMasked(String value, int maxDigits, Map<int, String> separators) {
  final digits = digitsOnly(value);
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length && i < maxDigits; i++) {
    buffer.write(digits[i]);
    final separator = separators[i];
    if (separator != null && i < digits.length - 1) {
      buffer.write(separator);
    }
  }
  return buffer.toString();
}
