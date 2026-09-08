import 'package:flutter/services.dart';

import '../services/profile_validators.dart';

/// Masks CPF input as the user types (`000.000.000-00`), strips non-digits
/// from pasted content and limits the field to 11 digits. The canonical
/// value (digits only) is recovered with [digitsOnly].
class CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatCpf(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Masks CEP input as the user types (`00000-000`), strips non-digits from
/// pasted content and limits the field to 8 digits. The canonical value
/// (digits only) is recovered with [digitsOnly].
class CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatCep(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Masks CNPJ input as the user types (`00.000.000/0000-00`), strips
/// non-digits from pasted content and limits the field to 14 digits. The
/// canonical value (digits only) is recovered with [digitsOnly].
class CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatCnpj(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
