import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Servicio generador de hojas de cálculo Microsoft Excel (.xlsx) nativas
/// utilizando la especificación OpenXML empaquetada en un contenedor ZIP con [Archive].
/// No requiere dependencias de terceros conflictivas ni componentes pesados.
class ExcelExporterService {
  const ExcelExporterService();

  static const ExcelExporterService instance = ExcelExporterService();

  /// Genera los bytes crudos (.xlsx) a partir de una lista de encabezados y filas.
  /// [sheetName]: Nombre de la pestaña de la hoja (por defecto 'Pase Git').
  /// [headers]: Nombres de las columnas.
  /// [rows]: Matriz de celdas por fila (valores string o numéricos).
  Uint8List generateXlsx({
    String sheetName = 'Pase Git',
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) {
    final archive = Archive();

    // 1. [Content_Types].xml
    final contentTypesXml = _buildContentTypesXml();
    archive.addFile(
      ArchiveFile(
        '[Content_Types].xml',
        utf8.encode(contentTypesXml).length,
        utf8.encode(contentTypesXml),
      ),
    );

    // 2. _rels/.rels
    final rootRelsXml = _buildRootRelsXml();
    archive.addFile(
      ArchiveFile(
        '_rels/.rels',
        utf8.encode(rootRelsXml).length,
        utf8.encode(rootRelsXml),
      ),
    );

    // 3. xl/workbook.xml
    final safeSheetName = _escapeXml(sheetName);
    final workbookXml = _buildWorkbookXml(safeSheetName);
    archive.addFile(
      ArchiveFile(
        'xl/workbook.xml',
        utf8.encode(workbookXml).length,
        utf8.encode(workbookXml),
      ),
    );

    // 4. xl/_rels/workbook.xml.rels
    final workbookRelsXml = _buildWorkbookRelsXml();
    archive.addFile(
      ArchiveFile(
        'xl/_rels/workbook.xml.rels',
        utf8.encode(workbookRelsXml).length,
        utf8.encode(workbookRelsXml),
      ),
    );

    // 5. xl/styles.xml (estilo mínimo para headers y texto regular)
    final stylesXml = _buildStylesXml();
    archive.addFile(
      ArchiveFile(
        'xl/styles.xml',
        utf8.encode(stylesXml).length,
        utf8.encode(stylesXml),
      ),
    );

    // 6. xl/worksheets/sheet1.xml
    final worksheetXml = _buildWorksheetXml(headers, rows);
    archive.addFile(
      ArchiveFile(
        'xl/worksheets/sheet1.xml',
        utf8.encode(worksheetXml).length,
        utf8.encode(worksheetXml),
      ),
    );

    // Comprimir en formato ZIP estándar (.xlsx)
    final encoder = ZipEncoder();
    final bytes = encoder.encode(archive);
    return Uint8List.fromList(bytes);
  }

  static String _buildContentTypesXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>';
  }

  static String _buildRootRelsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>';
  }

  static String _buildWorkbookXml(String sheetName) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="20480" windowHeight="10240"/></bookViews>'
        '<sheets>'
        '<sheet name="$sheetName" sheetId="1" r:id="rId1"/>'
        '</sheets>'
        '</workbook>';
  }

  static String _buildWorkbookRelsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>';
  }

  static String _buildStylesXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2">'
        '<font><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
        '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/><family val="2"/></font>'
        '</fonts>'
        '<fills count="3">'
        '<fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FF0D6EFD"/></patternFill></fill>'
        '</fills>'
        '<borders count="1">'
        '<border><left/><right/><top/><bottom/><diagonal/></border>'
        '</borders>'
        '<cellStyleXfs count="1">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>'
        '</cellStyleXfs>'
        '<cellXfs count="2">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
        '</cellXfs>'
        '</styleSheet>';
  }

  static String _buildWorksheetXml(
    List<String> headers,
    List<List<dynamic>> rows,
  ) {
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buffer.write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    );

    // Auto-fit columnas estimado
    if (headers.isNotEmpty) {
      buffer.write('<cols>');
      for (var colIdx = 0; colIdx < headers.length; colIdx++) {
        var maxLen = headers[colIdx].length;
        for (final row in rows) {
          if (colIdx < row.length && row[colIdx] != null) {
            final valStr = row[colIdx].toString();
            if (valStr.length > maxLen) {
              maxLen = valStr.length;
            }
          }
        }
        final colWidth = (maxLen + 5).clamp(12, 60);
        buffer.write(
          '<col min="${colIdx + 1}" max="${colIdx + 1}" width="$colWidth" customWidth="1"/>',
        );
      }
      buffer.write('</cols>');
    }

    buffer.write('<sheetData>');

    // Fila 1: Encabezados (con estilo de celda 1)
    buffer.write('<row r="1">');
    for (var colIdx = 0; colIdx < headers.length; colIdx++) {
      final cellRef = '${_colLetter(colIdx)}1';
      final headerText = _escapeXml(headers[colIdx]);
      buffer.write(
        '<c r="$cellRef" s="1" t="inlineStr"><is><t>$headerText</t></is></c>',
      );
    }
    buffer.write('</row>');

    // Filas 2..N: Datos
    for (var rowIdx = 0; rowIdx < rows.length; rowIdx++) {
      final actualRowNum = rowIdx + 2;
      final row = rows[rowIdx];
      buffer.write('<row r="$actualRowNum">');

      for (var colIdx = 0; colIdx < headers.length; colIdx++) {
        final cellRef = '${_colLetter(colIdx)}$actualRowNum';
        if (colIdx >= row.length || row[colIdx] == null) {
          continue;
        }

        final value = row[colIdx];
        if (value is num) {
          buffer.write('<c r="$cellRef"><v>$value</v></c>');
        } else {
          final text = _escapeXml(value.toString());
          buffer.write(
            '<c r="$cellRef" t="inlineStr"><is><t>$text</t></is></c>',
          );
        }
      }

      buffer.write('</row>');
    }

    buffer.write('</sheetData>');
    buffer.write('</worksheet>');
    return buffer.toString();
  }

  static String _colLetter(int colIndex) {
    var result = '';
    var n = colIndex;
    while (n >= 0) {
      result = String.fromCharCode(65 + (n % 26)) + result;
      n = (n ~/ 26) - 1;
    }
    return result;
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
