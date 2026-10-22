import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/code_editor_panel.dart';

void main() {
  group('Dynamic Procedure Character Limits', () {
    test('constants have expected values', () {
      expect(kDynamicProcMaxChars, equals(32500));
      expect(kDynamicProcWarnChars, equals(30000));
    });

    test('format thousands helper works correctly', () {
      expect(formatDynamicProcCharCount(0), equals('0'));
      expect(formatDynamicProcCharCount(999), equals('999'));
      expect(formatDynamicProcCharCount(1000), equals('1,000'));
      expect(formatDynamicProcCharCount(30000), equals('30,000'));
      expect(formatDynamicProcCharCount(32500), equals('32,500'));
      expect(formatDynamicProcCharCount(32750), equals('32,750'));
    });
  });
}
