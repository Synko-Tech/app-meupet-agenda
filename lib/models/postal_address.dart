/// Structured postal address stored in the user's private profile.
///
/// Serialized with English keys (matching the `completeOwnProfile` callable
/// contract) and read with Portuguese fallbacks for legacy documents.
class PostalAddress {
  const PostalAddress({
    required this.postalCode,
    required this.street,
    required this.number,
    this.complement,
    required this.neighborhood,
    required this.city,
    required this.state,
    this.country = 'BR',
  });

  final String postalCode;
  final String street;
  final String number;
  final String? complement;
  final String neighborhood;
  final String city;
  final String state;
  final String country;

  factory PostalAddress.fromMap(Map<String, dynamic> map) {
    return PostalAddress(
      postalCode: map['postalCode']?.toString() ?? map['cep']?.toString() ?? '',
      street: map['street']?.toString() ?? map['logradouro']?.toString() ?? '',
      number: map['number']?.toString() ?? map['numero']?.toString() ?? '',
      complement:
          map['complement']?.toString() ?? map['complemento']?.toString(),
      neighborhood:
          map['neighborhood']?.toString() ?? map['bairro']?.toString() ?? '',
      city: map['city']?.toString() ?? map['cidade']?.toString() ?? '',
      state: map['state']?.toString() ?? map['uf']?.toString() ?? '',
      country: map['country']?.toString() ?? map['pais']?.toString() ?? 'BR',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'postalCode': postalCode,
      'street': street,
      'number': number,
      'complement': complement,
      'neighborhood': neighborhood,
      'city': city,
      'state': state,
      'country': country,
    };
  }
}
