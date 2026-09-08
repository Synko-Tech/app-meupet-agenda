import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'profile_validators.dart';

/// Result of a ViaCEP lookup for an 8-digit postal code.
///
/// Field names follow the domain (postalCode/street/...) instead of ViaCEP's
/// wire names (cep/logradouro/...), so callers never see the raw API shape.
class PostalAddressLookup {
  const PostalAddressLookup({
    required this.postalCode,
    required this.street,
    required this.neighborhood,
    required this.city,
    required this.state,
  });

  /// The 8 digits that were looked up (mask-free).
  final String postalCode;

  /// `logradouro` from ViaCEP.
  final String street;

  /// `bairro` from ViaCEP.
  final String neighborhood;

  /// `localidade` from ViaCEP.
  final String city;

  /// `uf` from ViaCEP.
  final String state;
}

/// Why a ViaCEP lookup failed.
enum CepExceptionKind {
  /// The CEP is not 8 digits or the service rejected the request (HTTP != 200).
  invalid,

  /// The CEP is well-formed but does not exist (`{erro: true}`).
  notFound,

  /// Timeout, network failure or an unparseable response.
  unavailable,
}

/// Thrown by [CepService.lookup]; check [kind] to decide how to react.
class CepException implements Exception {
  const CepException(this.kind);

  const CepException.invalid() : kind = CepExceptionKind.invalid;

  const CepException.notFound() : kind = CepExceptionKind.notFound;

  const CepException.unavailable() : kind = CepExceptionKind.unavailable;

  final CepExceptionKind kind;

  @override
  String toString() => 'CepException(${kind.name})';
}

/// Looks up Brazilian postal codes through the public ViaCEP API.
///
/// Only 8-digit CEPs are ever sent over the network: shorter/malformed input
/// fails locally with [CepExceptionKind.invalid] without touching the API.
class CepService {
  CepService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _baseUrl = 'https://viacep.com.br/ws/';

  /// Resolves [postalCode] to a structured address.
  ///
  /// Throws [CepException] with the appropriate [CepExceptionKind] on every
  /// failure path; it never surfaces raw network or parsing errors.
  Future<PostalAddressLookup> lookup(String postalCode) async {
    final cep = digitsOnly(postalCode);
    if (cep.length != 8) {
      throw const CepException.invalid();
    }

    final uri = Uri.parse('$_baseUrl$cep/json/');
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 10));
    } on Exception {
      throw const CepException.unavailable();
    }

    if (response.statusCode != 200) {
      throw const CepException.invalid();
    }

    // ViaCEP historically serves latin-1 bytes with a utf-8 charset header;
    // tolerate malformed sequences so accented addresses still parse.
    final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } on FormatException {
      throw const CepException.unavailable();
    }

    if (decoded is! Map<String, dynamic>) {
      throw const CepException.unavailable();
    }
    if (decoded['erro'] == true) {
      throw const CepException.notFound();
    }

    return PostalAddressLookup(
      postalCode: cep,
      street: decoded['logradouro']?.toString() ?? '',
      neighborhood: decoded['bairro']?.toString() ?? '',
      city: decoded['localidade']?.toString() ?? '',
      state: decoded['uf']?.toString() ?? '',
    );
  }
}
