import 'package:appflowy_editor/appflowy_editor.dart';

/// Thin adapter around appflowy_editor's native markdown import/export API.
///
/// Kept as a single point of adaptation in case the underlying package API
/// changes across versions.
Document noteMarkdownToDocument(String markdown) {
  if (markdown.trim().isEmpty) {
    return Document.blank(withInitialText: true);
  }
  return markdownToDocument(markdown);
}

String noteDocumentToMarkdown(Document document) {
  return documentToMarkdown(document);
}
