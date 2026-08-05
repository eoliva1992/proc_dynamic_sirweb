import 'package:flutter_monaco/flutter_monaco.dart';

// Completions estáticas PL/SQL Oracle — snippets, keywords, funciones, tipos
final plsqlCompletionItems = <CompletionItem>[
  // ── Snippets estructurales
  CompletionItem(
    label: 'BEGIN...END',
    kind: CompletionItemKind.snippet,
    detail: 'Bloque PL/SQL anónimo',
    insertText: 'BEGIN\n\t\${1:NULL};\nEND;',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'DECLARE...BEGIN',
    kind: CompletionItemKind.snippet,
    detail: 'Bloque con sección DECLARE',
    insertText:
        'DECLARE\n\t\${1:v_var VARCHAR2(100)};\nBEGIN\n\t\${2:NULL};\nEXCEPTION\n\tWHEN OTHERS THEN\n\t\tDBMS_OUTPUT.PUT_LINE(SQLERRM);\nEND;',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'IF...THEN...END IF',
    kind: CompletionItemKind.snippet,
    detail: 'Condicional IF simple',
    insertText: 'IF \${1:condicion} THEN\n\t\${2:NULL};\nEND IF;',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'IF...THEN...ELSE',
    kind: CompletionItemKind.snippet,
    detail: 'Condicional IF/ELSE',
    insertText:
        'IF \${1:condicion} THEN\n\t\${2:NULL};\nELSE\n\t\${3:NULL};\nEND IF;',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'IF...ELSIF...ELSE',
    kind: CompletionItemKind.snippet,
    detail: 'Condicional con múltiples ramas',
    insertText:
        'IF \${1:cond1} THEN\n\t\${2:NULL};\nELSIF \${3:cond2} THEN\n\t\${4:NULL};\nELSE\n\t\${5:NULL};\nEND IF;',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'CASE...WHEN',
    kind: CompletionItemKind.snippet,
    detail: 'Expresión CASE buscada',
    insertText:
        'CASE \${1:expr}\n\tWHEN \${2:val1} THEN \${3:NULL}\n\tWHEN \${4:val2} THEN \${5:NULL}\n\tELSE \${6:NULL}\nEND;',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'FOR...LOOP (numérico)',
    kind: CompletionItemKind.snippet,
    detail: 'Bucle FOR con rango numérico',
    insertText:
        'FOR \${1:i} IN \${2:1}..\${3:10} LOOP\n\t\${4:NULL};\nEND LOOP;',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'FOR...IN (cursor implícito)',
    kind: CompletionItemKind.snippet,
    detail: 'Bucle FOR sobre consulta inline',
    insertText:
        'FOR \${1:rec} IN (\${2:SELECT * FROM \${3:tabla}}) LOOP\n\t\${4:NULL};\nEND LOOP;',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'WHILE...LOOP',
    kind: CompletionItemKind.snippet,
    detail: 'Bucle WHILE',
    insertText: 'WHILE \${1:condicion} LOOP\n\t\${2:NULL};\nEND LOOP;',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'CURSOR declaration',
    kind: CompletionItemKind.snippet,
    detail: 'Declaración de cursor nombrado',
    insertText:
        'CURSOR \${1:c_nombre} IS\n\tSELECT \${2:*}\n\tFROM \${3:tabla}\n\tWHERE \${4:1=1};',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'EXCEPTION block',
    kind: CompletionItemKind.snippet,
    detail: 'Bloque de manejo de excepciones',
    insertText:
        'EXCEPTION\n\tWHEN NO_DATA_FOUND THEN\n\t\t\${1:NULL};\n\tWHEN OTHERS THEN\n\t\tDBMS_OUTPUT.PUT_LINE(\'Error: \' || SQLERRM);\n\t\tRAISE;',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'CREATE OR REPLACE PROCEDURE',
    kind: CompletionItemKind.snippet,
    detail: 'Plantilla de procedimiento',
    insertText:
        'CREATE OR REPLACE PROCEDURE \${1:nombre}\n(\n\tp_param IN \${2:VARCHAR2}\n)\nAS\nBEGIN\n\t\${3:NULL};\nEXCEPTION\n\tWHEN OTHERS THEN\n\t\tRAISE;\nEND \${1:nombre};',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'CREATE OR REPLACE FUNCTION',
    kind: CompletionItemKind.snippet,
    detail: 'Plantilla de función',
    insertText:
        'CREATE OR REPLACE FUNCTION \${1:nombre}\n(\n\tp_param IN \${2:VARCHAR2}\n)\nRETURN \${3:VARCHAR2}\nAS\n\tv_result \${3:VARCHAR2};\nBEGIN\n\t\${4:NULL};\n\tRETURN v_result;\nEXCEPTION\n\tWHEN OTHERS THEN\n\t\tRAISE;\nEND \${1:nombre};',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'BULK COLLECT INTO',
    kind: CompletionItemKind.snippet,
    detail: 'Carga masiva en colección',
    insertText:
        'SELECT \${1:col}\nBULK COLLECT INTO \${2:v_arr}\nFROM \${3:tabla}\nWHERE \${4:1=1};',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'FORALL',
    kind: CompletionItemKind.snippet,
    detail: 'DML masivo sobre colección',
    insertText:
        'FORALL \${1:i} IN 1..\${2:v_arr}.COUNT\n\t\${3:INSERT INTO tabla VALUES v_arr(i)};',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'RAISE_APPLICATION_ERROR',
    kind: CompletionItemKind.functionType,
    detail: 'Lanzar error ORA-20xxx personalizado',
    insertText:
        'RAISE_APPLICATION_ERROR(-20\${1:001}, \${2:\'mensaje de error\'});',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  // ── DBMS_OUTPUT
  CompletionItem(
    label: 'DBMS_OUTPUT.PUT_LINE',
    kind: CompletionItemKind.functionType,
    detail: 'Imprimir línea de debug',
    insertText: 'DBMS_OUTPUT.PUT_LINE(\${1:\'mensaje\'});',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'DBMS_OUTPUT.ENABLE',
    kind: CompletionItemKind.functionType,
    detail: 'Habilitar buffer de salida',
    insertText: 'DBMS_OUTPUT.ENABLE(1000000);',
  ),
  // ── Funciones de error
  CompletionItem(
    label: 'SQLERRM',
    kind: CompletionItemKind.keyword,
    detail: 'Mensaje del último error ORA-',
    insertText: 'SQLERRM',
  ),
  CompletionItem(
    label: 'SQLCODE',
    kind: CompletionItemKind.keyword,
    detail: 'Código del último error',
    insertText: 'SQLCODE',
  ),
  CompletionItem(
    label: 'DBMS_UTILITY.FORMAT_ERROR_STACK',
    kind: CompletionItemKind.functionType,
    detail: 'Stack completo del error',
    insertText: 'DBMS_UTILITY.FORMAT_ERROR_STACK',
  ),
  CompletionItem(
    label: 'DBMS_UTILITY.FORMAT_ERROR_BACKTRACE',
    kind: CompletionItemKind.functionType,
    detail: 'Línea de origen del error',
    insertText: 'DBMS_UTILITY.FORMAT_ERROR_BACKTRACE',
  ),
  // ── DML keywords
  CompletionItem(
    label: 'SELECT',
    kind: CompletionItemKind.keyword,
    insertText: 'SELECT ',
  ),
  CompletionItem(
    label: 'INSERT INTO',
    kind: CompletionItemKind.keyword,
    insertText: 'INSERT INTO ',
  ),
  CompletionItem(
    label: 'UPDATE',
    kind: CompletionItemKind.keyword,
    insertText: 'UPDATE ',
  ),
  CompletionItem(
    label: 'DELETE FROM',
    kind: CompletionItemKind.keyword,
    insertText: 'DELETE FROM ',
  ),
  CompletionItem(
    label: 'MERGE INTO',
    kind: CompletionItemKind.keyword,
    insertText: 'MERGE INTO ',
  ),
  CompletionItem(
    label: 'COMMIT',
    kind: CompletionItemKind.keyword,
    insertText: 'COMMIT;',
  ),
  CompletionItem(
    label: 'ROLLBACK',
    kind: CompletionItemKind.keyword,
    insertText: 'ROLLBACK;',
  ),
  CompletionItem(
    label: 'SAVEPOINT',
    kind: CompletionItemKind.keyword,
    insertText: 'SAVEPOINT \${1:nombre}',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'EXECUTE IMMEDIATE',
    kind: CompletionItemKind.keyword,
    insertText: 'EXECUTE IMMEDIATE ',
  ),
  // ── Tipos Oracle
  CompletionItem(
    label: 'VARCHAR2',
    kind: CompletionItemKind.keyword,
    insertText: 'VARCHAR2(\${1:100})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'NUMBER',
    kind: CompletionItemKind.keyword,
    insertText: 'NUMBER(\${1:10},\${2:2})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'DATE',
    kind: CompletionItemKind.keyword,
    insertText: 'DATE',
  ),
  CompletionItem(
    label: 'TIMESTAMP',
    kind: CompletionItemKind.keyword,
    insertText: 'TIMESTAMP',
  ),
  CompletionItem(
    label: 'BOOLEAN',
    kind: CompletionItemKind.keyword,
    insertText: 'BOOLEAN',
  ),
  CompletionItem(
    label: 'INTEGER',
    kind: CompletionItemKind.keyword,
    insertText: 'INTEGER',
  ),
  CompletionItem(
    label: 'PLS_INTEGER',
    kind: CompletionItemKind.keyword,
    insertText: 'PLS_INTEGER',
  ),
  CompletionItem(
    label: 'CLOB',
    kind: CompletionItemKind.keyword,
    insertText: 'CLOB',
  ),
  CompletionItem(
    label: 'BLOB',
    kind: CompletionItemKind.keyword,
    insertText: 'BLOB',
  ),
  CompletionItem(
    label: 'CHAR',
    kind: CompletionItemKind.keyword,
    insertText: 'CHAR(\${1:1})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  // ── Funciones Oracle
  CompletionItem(
    label: 'NVL',
    kind: CompletionItemKind.functionType,
    insertText: 'NVL(\${1:expr}, \${2:default})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'NVL2',
    kind: CompletionItemKind.functionType,
    insertText: 'NVL2(\${1:expr}, \${2:si_no_nulo}, \${3:si_nulo})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'COALESCE',
    kind: CompletionItemKind.functionType,
    insertText: 'COALESCE(\${1:expr1}, \${2:expr2})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'TO_DATE',
    kind: CompletionItemKind.functionType,
    insertText: 'TO_DATE(\${1:str}, \${2:\'DD/MM/YYYY\'})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'TO_CHAR',
    kind: CompletionItemKind.functionType,
    insertText: 'TO_CHAR(\${1:val}, \${2:\'DD/MM/YYYY\'})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'TO_NUMBER',
    kind: CompletionItemKind.functionType,
    insertText: 'TO_NUMBER(\${1:str})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'SUBSTR',
    kind: CompletionItemKind.functionType,
    insertText: 'SUBSTR(\${1:str}, \${2:pos}, \${3:len})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'INSTR',
    kind: CompletionItemKind.functionType,
    insertText: 'INSTR(\${1:str}, \${2:buscar})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'TRIM',
    kind: CompletionItemKind.functionType,
    insertText: 'TRIM(\${1:str})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'UPPER',
    kind: CompletionItemKind.functionType,
    insertText: 'UPPER(\${1:str})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'LOWER',
    kind: CompletionItemKind.functionType,
    insertText: 'LOWER(\${1:str})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'LENGTH',
    kind: CompletionItemKind.functionType,
    insertText: 'LENGTH(\${1:str})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'LPAD',
    kind: CompletionItemKind.functionType,
    insertText: 'LPAD(\${1:str}, \${2:n}, \${3:\' \'})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'DECODE',
    kind: CompletionItemKind.functionType,
    insertText: 'DECODE(\${1:expr}, \${2:val1}, \${3:res1}, \${4:default})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'SYSDATE',
    kind: CompletionItemKind.keyword,
    insertText: 'SYSDATE',
  ),
  CompletionItem(
    label: 'SYSTIMESTAMP',
    kind: CompletionItemKind.keyword,
    insertText: 'SYSTIMESTAMP',
  ),
  CompletionItem(
    label: 'TRUNC',
    kind: CompletionItemKind.functionType,
    insertText: 'TRUNC(\${1:val})',
    insertTextRules: {InsertTextRule.insertAsSnippet},
  ),
  CompletionItem(
    label: 'ROWNUM',
    kind: CompletionItemKind.keyword,
    insertText: 'ROWNUM',
  ),
  // ── Pseudo-columns y atributos
  CompletionItem(
    label: '%ROWTYPE',
    kind: CompletionItemKind.keyword,
    insertText: '%ROWTYPE',
  ),
  CompletionItem(
    label: '%TYPE',
    kind: CompletionItemKind.keyword,
    insertText: '%TYPE',
  ),
  CompletionItem(
    label: '%FOUND',
    kind: CompletionItemKind.keyword,
    insertText: '%FOUND',
  ),
  CompletionItem(
    label: '%NOTFOUND',
    kind: CompletionItemKind.keyword,
    insertText: '%NOTFOUND',
  ),
  CompletionItem(
    label: '%ISOPEN',
    kind: CompletionItemKind.keyword,
    insertText: '%ISOPEN',
  ),
  CompletionItem(
    label: '%ROWCOUNT',
    kind: CompletionItemKind.keyword,
    insertText: '%ROWCOUNT',
  ),
  CompletionItem(
    label: 'SQL%FOUND',
    kind: CompletionItemKind.keyword,
    insertText: 'SQL%FOUND',
  ),
  CompletionItem(
    label: 'SQL%NOTFOUND',
    kind: CompletionItemKind.keyword,
    insertText: 'SQL%NOTFOUND',
  ),
  CompletionItem(
    label: 'SQL%ROWCOUNT',
    kind: CompletionItemKind.keyword,
    insertText: 'SQL%ROWCOUNT',
  ),
];
