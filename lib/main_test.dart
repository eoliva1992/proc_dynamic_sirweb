import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _TestApp());
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _EditorPage(),
    );
  }
}

class _EditorPage extends StatefulWidget {
  const _EditorPage();

  @override
  State<_EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<_EditorPage> {
  String _status = 'Iniciando…';
  String _error = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_status)),
      body: Column(
        children: [
          if (_error.isNotEmpty)
            Container(
              color: Colors.red.shade900,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              child: Text(_error, style: const TextStyle(color: Colors.white)),
            ),
          Expanded(
            child: fm.MonacoEditor(
              initialText: 'SELECT * FROM dual;',
              options: const fm.EditorOptions(
                language: fm.MonacoLanguage.sql,
                theme: fm.MonacoTheme.vsDark,
              ),
              onReady: (_) => setState(() => _status = 'Monaco listo ✓'),
              onError: (err, stack) => setState(() {
                _status = 'Error';
                _error = err.toString();
              }),
            ),
          ),
        ],
      ),
    );
  }
}
