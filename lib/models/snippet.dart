class Snippet {
  final String id;
  final String name;
  final String prefix;
  final String body;
  final String description;
  // 'sql' | 'javascript' | 'any'
  final String language;

  const Snippet({
    required this.id,
    required this.name,
    required this.prefix,
    required this.body,
    this.description = '',
    this.language = 'any',
  });

  Snippet copyWith({
    String? id,
    String? name,
    String? prefix,
    String? body,
    String? description,
    String? language,
  }) => Snippet(
    id: id ?? this.id,
    name: name ?? this.name,
    prefix: prefix ?? this.prefix,
    body: body ?? this.body,
    description: description ?? this.description,
    language: language ?? this.language,
  );

  factory Snippet.fromJson(Map<String, dynamic> json) => Snippet(
    id: json['id'] as String,
    name: json['name'] as String,
    prefix: json['prefix'] as String,
    body: json['body'] as String,
    description: (json['description'] as String?) ?? '',
    language: (json['language'] as String?) ?? 'any',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'prefix': prefix,
    'body': body,
    'description': description,
    'language': language,
  };
}
