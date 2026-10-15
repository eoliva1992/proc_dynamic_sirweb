class Snippet {
  /// Server id. Empty string when the snippet was never persisted.
  final String id;
  final String name;
  final String prefix;
  final String body;
  final String description;

  /// 'sql' | 'javascript' | 'any'
  final String language;

  /// User that owns the snippet (server-side ownership).
  final String ownerUser;

  /// User who last updated the snippet (optional/informative, managed by server).
  final String? modifiedBy;

  /// Timestamp of the last update (optional/informative, managed by server).
  final DateTime? updatedAt;

  /// Logical delete flag.
  final bool isActive;

  /// Optimistic locking version returned by the server.
  final int version;

  const Snippet({
    required this.id,
    required this.name,
    required this.prefix,
    required this.body,
    this.description = '',
    this.language = 'any',
    this.ownerUser = '',
    this.modifiedBy,
    this.updatedAt,
    this.isActive = true,
    this.version = 0,
  });

  bool get isPersisted => id.isNotEmpty;

  Snippet copyWith({
    String? id,
    String? name,
    String? prefix,
    String? body,
    String? description,
    String? language,
    String? ownerUser,
    String? modifiedBy,
    DateTime? updatedAt,
    bool? isActive,
    int? version,
  }) => Snippet(
    id: id ?? this.id,
    name: name ?? this.name,
    prefix: prefix ?? this.prefix,
    body: body ?? this.body,
    description: description ?? this.description,
    language: language ?? this.language,
    ownerUser: ownerUser ?? this.ownerUser,
    modifiedBy: modifiedBy ?? this.modifiedBy,
    updatedAt: updatedAt ?? this.updatedAt,
    isActive: isActive ?? this.isActive,
    version: version ?? this.version,
  );

  /// Case-insensitive match used by the snippets search box.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        prefix.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        body.toLowerCase().contains(q);
  }

  factory Snippet.fromJson(Map<String, dynamic> json) {
    String str(List<String> keys, [String fallback = '']) {
      for (final k in keys) {
        final v = json[k];
        if (v != null && v.toString().isNotEmpty) return v.toString();
      }
      return fallback;
    }

    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    final rawActive =
        json['isActive'] ?? json['is_active'] ?? json['IS_ACTIVE'];
    final rawVersion = json['version'] ?? json['VERSION'];

    return Snippet(
      id: str(['id', 'ID']),
      name: str(['name', 'NAME']),
      prefix: str(['prefix', 'PREFIX']),
      body: str(['body', 'BODY']),
      description: str(['description', 'DESCRIPTION']),
      language: str(['language', 'LANGUAGE'], 'any'),
      ownerUser: str(['ownerUser', 'owner_user', 'OWNER_USER']),
      modifiedBy:
          str([
            'modifiedBy',
            'modified_by',
            'MODIFIED_BY',
            'updatedBy',
            'updated_by',
            'UPDATED_BY',
          ]).trim().isEmpty
          ? null
          : str([
              'modifiedBy',
              'modified_by',
              'MODIFIED_BY',
              'updatedBy',
              'updated_by',
              'UPDATED_BY',
            ]).trim(),
      updatedAt: parseDate(
        json['updatedAt'] ??
            json['updated_at'] ??
            json['UPDATED_AT'] ??
            json['feModificacion'] ??
            json['FE_MODIFICACION'],
      ),
      isActive: switch (rawActive) {
        bool b => b,
        num n => n != 0,
        String s => s == '1' || s.toLowerCase() == 'true',
        _ => true,
      },
      version: switch (rawVersion) {
        num n => n.toInt(),
        String s => int.tryParse(s) ?? 0,
        _ => 0,
      },
    );
  }

  /// Payload for POST /tools/snippets (create).
  Map<String, dynamic> toCreateJson() => {
    'name': name,
    'prefix': prefix,
    'body': body,
    'description': description.isEmpty ? null : description,
    'language': language,
    'ownerUser': ownerUser,
    if (modifiedBy != null && modifiedBy!.isNotEmpty) 'modifiedBy': modifiedBy,
    'isActive': isActive,
    'id': id.isEmpty ? null : id,
  };

  /// Payload for PUT /tools/snippets/{id} (update).
  Map<String, dynamic> toUpdateJson() => {
    'version': version,
    'name': name,
    'prefix': prefix,
    'body': body,
    'description': description.isEmpty ? null : description,
    'language': language,
    'ownerUser': ownerUser,
    'modifiedBy': (modifiedBy != null && modifiedBy!.isNotEmpty)
        ? modifiedBy
        : ownerUser,
    'isActive': isActive,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'prefix': prefix,
    'body': body,
    'description': description,
    'language': language,
    'ownerUser': ownerUser,
    if (modifiedBy != null) 'modifiedBy': modifiedBy,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    'isActive': isActive,
    'version': version,
  };
}
