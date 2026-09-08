import 'firestore_converters.dart';

class ServiceModel {
  const ServiceModel({
    required this.id,
    required this.name,
    required this.description,
    required this.durationMinutes,
    required this.price,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final int durationMinutes;
  final double price;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ServiceModel.empty() {
    return const ServiceModel(
      id: '',
      name: '',
      description: '',
      durationMinutes: 60,
      price: 0,
    );
  }

  factory ServiceModel.fromMap(String id, Map<String, dynamic> map) {
    return ServiceModel(
      id: id,
      name: map['nome']?.toString() ?? map['name']?.toString() ?? '',
      description:
          map['descricao']?.toString() ?? map['description']?.toString() ?? '',
      durationMinutes: intFromFirestore(
        map['duracao_minutos'] ?? map['durationMinutes'],
      ),
      price: doubleFromFirestore(map['valor'] ?? map['price']),
      isActive: map['ativo'] as bool? ?? map['isActive'] as bool? ?? true,
      createdAt: map['createdAt'] == null
          ? null
          : dateTimeFromFirestore(map['createdAt']),
      updatedAt: map['updatedAt'] == null
          ? null
          : dateTimeFromFirestore(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nome': name,
      'descricao': description,
      'duracao_minutos': durationMinutes,
      'valor': price,
      'ativo': isActive,
      'updatedAt': updatedAt,
    };
  }

  ServiceModel copyWith({
    String? id,
    String? name,
    String? description,
    int? durationMinutes,
    double? price,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServiceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      price: price ?? this.price,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
