/// Access level a given user has over a [Note], as reported by the server.
enum NoteAccessLevel {
  owner,
  edit,
  readOnly,
  unknown;

  /// Tolerant, case-insensitive parser for the server's `accessLevel` value.
  static NoteAccessLevel parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'owner':
        return NoteAccessLevel.owner;
      case 'edit':
        return NoteAccessLevel.edit;
      case 'readonly':
      case 'read_only':
      case 'read-only':
        return NoteAccessLevel.readOnly;
      default:
        return NoteAccessLevel.unknown;
    }
  }

  bool get canEdit =>
      this == NoteAccessLevel.owner || this == NoteAccessLevel.edit;
  bool get canShare => this == NoteAccessLevel.owner;
  bool get canDelete => this == NoteAccessLevel.owner;
}

/// Permission granted to a user when sharing a [Note].
enum NotePermission {
  readOnly,
  edit;

  /// Server string used in the compact `asignaciones` payload (POST /compartir).
  String get asignacionLabel => switch (this) {
    NotePermission.readOnly => 'ReadOnly',
    NotePermission.edit => 'Edit',
  };

  /// Tolerant parser from the server's representation (string "ReadOnly"/"Edit"
  /// or int 0/1=ReadOnly, 1/2=Edit).
  static NotePermission parse(dynamic raw) {
    if (raw == null) return NotePermission.readOnly;
    if (raw is num) {
      final n = raw.toInt();
      // C# enum NotePermission { ReadOnly = 0, Edit = 1 }
      // O formato 1-based tradicional: 1 = ReadOnly, 2 = Edit
      return (n == 1 || n == 2) ? (n == 1 ? NotePermission.edit : NotePermission.edit) : NotePermission.readOnly;
    }
    final s = raw.toString().trim().toLowerCase();
    switch (s) {
      case '1': // C# Enum.Edit cuando se serializa como int (0=ReadOnly, 1=Edit)
      case '2': // 1-based representation
      case 'edit':
      case 'edicion':
      case 'edición':
        return NotePermission.edit;
      case '0': // C# Enum.ReadOnly cuando se serializa como int (0=ReadOnly)
      case 'readonly':
      case 'read_only':
      case 'read-only':
      case 'lectura':
      default:
        return NotePermission.readOnly;
    }
  }

  /// Tolerant parser from the numeric or string representation returned by
  /// `/comparticiones` or `/compartir`.
  static NotePermission fromInt(dynamic raw) => parse(raw);
}

class Note {
  /// Server id. Empty string when the note was never persisted.
  final String id;
  final String title;

  /// Markdown source serialized from the visual block editor.
  final String content;
  final List<String> tags;

  /// User that owns the note (server-side ownership).
  final String ownerUser;

  /// Logical delete flag.
  final bool isActive;

  /// Optimistic locking version returned by the server.
  final int version;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    this.tags = const [],
    this.ownerUser = '',
    this.isActive = true,
    this.version = 0,
    this.createdAt,
    this.updatedAt,
  });

  bool get isPersisted => id.isNotEmpty;

  Note copyWith({
    String? id,
    String? title,
    String? content,
    List<String>? tags,
    String? ownerUser,
    bool? isActive,
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Note(
    id: id ?? this.id,
    title: title ?? this.title,
    content: content ?? this.content,
    tags: tags ?? this.tags,
    ownerUser: ownerUser ?? this.ownerUser,
    isActive: isActive ?? this.isActive,
    version: version ?? this.version,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory Note.fromJson(Map<String, dynamic> json) {
    String str(List<String> keys, [String fallback = '']) {
      for (final k in keys) {
        final v = json[k];
        if (v != null && v.toString().isNotEmpty) return v.toString();
      }
      return fallback;
    }

    final rawActive =
        json['isActive'] ?? json['is_active'] ?? json['IS_ACTIVE'];
    final rawVersion = json['version'] ?? json['VERSION'];
    final rawTags = json['tags'] ?? json['TAGS'];

    return Note(
      id: str(['id', 'ID']),
      title: str(['title', 'TITLE']),
      content: str(['content', 'CONTENT']),
      tags: switch (rawTags) {
        List list => list.map((e) => e.toString()).toList(),
        String s when s.isNotEmpty =>
          s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        _ => const [],
      },
      ownerUser: str(['ownerUser', 'owner_user', 'OWNER_USER']),
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
      createdAt: _parseDate(
        json['createdAt'] ?? json['created_at'] ?? json['CREATED_AT'],
      ),
      updatedAt: _parseDate(
        json['updatedAt'] ?? json['updated_at'] ?? json['UPDATED_AT'],
      ),
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  /// Payload for POST /tools/notas (create).
  Map<String, dynamic> toCreateJson() {
    final cleanContent = content.trim().isEmpty ? ' ' : content;
    return {
      'title': title,
      'content': cleanContent,
      'ownerUser': ownerUser,
      'tags': tags.isEmpty ? null : tags.join(','),
      'isActive': isActive,
      'id': id.isEmpty ? null : id,
    };
  }

  /// Payload for PUT /tools/notas/{id} (update).
  Map<String, dynamic> toUpdateJson({required String requestingUser}) {
    final cleanContent = content.trim().isEmpty ? ' ' : content;
    return {
      'version': version,
      'title': title,
      'content': cleanContent,
      'requestingUser': requestingUser,
      'tags': tags.isEmpty ? null : tags.join(','),
      'isActive': isActive,
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'ownerUser': ownerUser,
    'tags': tags,
    'isActive': isActive,
    'version': version,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };
}

/// A [Note] paired with the requesting user's access level, as returned by
/// the search/list and getById endpoints.
class NoteListItem {
  final Note note;
  final NoteAccessLevel accessLevel;

  const NoteListItem({required this.note, required this.accessLevel});

  factory NoteListItem.fromJson(Map<String, dynamic> json) {
    final rawNote = json['note'] ?? json['NOTE'] ?? json;
    return NoteListItem(
      note: Note.fromJson(rawNote as Map<String, dynamic>),
      accessLevel: NoteAccessLevel.parse(
        (json['accessLevel'] ?? json['access_level'] ?? json['ACCESS_LEVEL'])
            ?.toString(),
      ),
    );
  }
}

/// A single share grant for a [Note], as returned by GET /comparticiones.
class NoteShare {
  final String noteId;
  final String sharedWithUser;
  final NotePermission permission;
  final String sharedBy;
  final DateTime? sharedAt;

  const NoteShare({
    required this.noteId,
    required this.sharedWithUser,
    required this.permission,
    required this.sharedBy,
    this.sharedAt,
  });

  factory NoteShare.fromJson(Map<String, dynamic> json) {
    String str(List<String> keys, [String fallback = '']) {
      for (final k in keys) {
        final v = json[k];
        if (v != null && v.toString().isNotEmpty) return v.toString();
      }
      return fallback;
    }

    final rawDate = json['sharedAt'] ?? json['shared_at'] ?? json['SHARED_AT'];
    return NoteShare(
      noteId: str(['noteId', 'note_id', 'NOTE_ID']),
      sharedWithUser: str([
        'sharedWithUser',
        'shared_with_user',
        'SHARED_WITH_USER',
      ]),
      permission: NotePermission.parse(
        json['permission'] ??
            json['PERMISSION'] ??
            json['permiso'] ??
            json['PERMISO'] ??
            json['accessLevel'] ??
            json['ACCESS_LEVEL'] ??
            json['access_level'],
      ),
      sharedBy: str(['sharedBy', 'shared_by', 'SHARED_BY']),
      sharedAt: rawDate == null ? null : DateTime.tryParse(rawDate.toString()),
    );
  }
}

/// A single applied share grant, as reported inside [NoteShareResult].
class NoteShareApplied {
  final String user;
  final NotePermission permission;

  const NoteShareApplied({required this.user, required this.permission});

  factory NoteShareApplied.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] ?? json['USER'] ?? '').toString();
    return NoteShareApplied(
      user: user,
      permission: NotePermission.parse(
        json['permission'] ??
            json['PERMISSION'] ??
            json['permiso'] ??
            json['PERMISO'] ??
            json['accessLevel'] ??
            json['ACCESS_LEVEL'] ??
            json['access_level'],
      ),
    );
  }
}

/// Result of POST /tools/notas/{id}/compartir.
class NoteShareResult {
  final int status;
  final List<NoteShareApplied> aplicados;
  final List<String> omitidos;

  const NoteShareResult({
    required this.status,
    this.aplicados = const [],
    this.omitidos = const [],
  });

  factory NoteShareResult.fromJson(Map<String, dynamic> json) {
    final rawAplicados = json['aplicados'] ?? json['APLICADOS'];
    final rawOmitidos = json['omitidos'] ?? json['OMITIDOS'];
    final rawStatus = json['status'] ?? json['STATUS'];
    return NoteShareResult(
      status: switch (rawStatus) {
        num n => n.toInt(),
        String s => int.tryParse(s) ?? 0,
        _ => 0,
      },
      aplicados: switch (rawAplicados) {
        List list =>
          list
              .whereType<Map<String, dynamic>>()
              .map(NoteShareApplied.fromJson)
              .toList(),
        _ => const [],
      },
      omitidos: switch (rawOmitidos) {
        List list => list.map((e) => e.toString()).toList(),
        _ => const [],
      },
    );
  }
}
