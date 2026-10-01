/// Modelos de datos para el endpoint de búsqueda en código fuente de esquemas Oracle:
/// `GET /tools/schema/search-source?texto=&owner=&ambiente=&maxResultados=200`
class SchemaSourceObject {
  final String owner;
  final String name;
  final String objectType;
  final int matchCount;
  final int firstLine;

  const SchemaSourceObject({
    required this.owner,
    required this.name,
    required this.objectType,
    this.matchCount = 0,
    this.firstLine = 1,
  });

  factory SchemaSourceObject.fromJson(Map<String, dynamic> json) {
    return SchemaSourceObject(
      owner: (json['owner'] ?? json['OWNER'] ?? '') as String,
      name: (json['name'] ?? json['NAME'] ?? '') as String,
      objectType: ((json['objectType'] ?? json['OBJECT_TYPE'] ?? '') as String)
          .toUpperCase(),
      matchCount: ((json['matchCount'] ?? json['MATCH_COUNT'] ?? 0) as num)
          .toInt(),
      firstLine: ((json['firstLine'] ?? json['FIRST_LINE'] ?? 1) as num)
          .toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'owner': owner,
    'name': name,
    'objectType': objectType,
    'matchCount': matchCount,
    'firstLine': firstLine,
  };
}

class SchemaSourceMatch {
  final String owner;
  final String name;
  final String objectType;
  final int line;
  final String text;

  const SchemaSourceMatch({
    required this.owner,
    required this.name,
    required this.objectType,
    required this.line,
    required this.text,
  });

  factory SchemaSourceMatch.fromJson(Map<String, dynamic> json) {
    return SchemaSourceMatch(
      owner: (json['owner'] ?? json['OWNER'] ?? '') as String,
      name: (json['name'] ?? json['NAME'] ?? '') as String,
      objectType: ((json['objectType'] ?? json['OBJECT_TYPE'] ?? '') as String)
          .toUpperCase(),
      line: ((json['line'] ?? json['LINE'] ?? 1) as num).toInt(),
      text: (json['text'] ?? json['TEXT'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'owner': owner,
    'name': name,
    'objectType': objectType,
    'line': line,
    'text': text,
  };
}

class SchemaSourceSearchResult {
  final List<SchemaSourceObject> objects;
  final List<SchemaSourceMatch> matches;

  const SchemaSourceSearchResult({
    this.objects = const [],
    this.matches = const [],
  });

  factory SchemaSourceSearchResult.fromJson(Map<String, dynamic> json) {
    final rawObjects = json['objects'] ?? json['OBJECTS'];
    final rawMatches = json['matches'] ?? json['MATCHES'];

    final objs = <SchemaSourceObject>[];
    if (rawObjects is List) {
      for (final item in rawObjects) {
        if (item is Map<String, dynamic>) {
          objs.add(SchemaSourceObject.fromJson(item));
        } else if (item is Map) {
          objs.add(
            SchemaSourceObject.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final mtchs = <SchemaSourceMatch>[];
    if (rawMatches is List) {
      for (final item in rawMatches) {
        if (item is Map<String, dynamic>) {
          mtchs.add(SchemaSourceMatch.fromJson(item));
        } else if (item is Map) {
          mtchs.add(
            SchemaSourceMatch.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return SchemaSourceSearchResult(objects: objs, matches: mtchs);
  }

  bool get isEmpty => objects.isEmpty && matches.isEmpty;
  bool get isNotEmpty => !isEmpty;
}
