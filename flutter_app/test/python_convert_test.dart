import 'dart:convert';

import 'package:congmiao_toolbox_flutter/core/python_convert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('python literal to JSON', () {
    test('converts dicts, tuples, booleans and None', () {
      final json = pythonLiteralToJson(
          "{'name': '丛苗', 'ok': True, 'skip': None, 'items': (1, 2.5, 'x'),}");
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['name'], '丛苗');
      expect(decoded['ok'], isTrue);
      expect(decoded['skip'], isNull);
      expect(decoded['items'], [1, 2.5, 'x']);
    });

    test('handles escapes and nested structures', () {
      final json = pythonLiteralToJson(
          r"{'text': 'line1\nline2', 'uni': '你好', 'deep': [{'a': [1, 2]}]}",
          pretty: false);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['text'], 'line1\nline2');
      expect(decoded['uni'], '你好');
      expect((decoded['deep'] as List).first, {'a': [1, 2]});
    });

    test('stringifies non-string dict keys', () {
      final decoded = jsonDecode(pythonLiteralToJson("{1: 'a', True: 'b'}"))
          as Map<String, dynamic>;
      expect(decoded['1'], 'a');
      expect(decoded['true'], 'b');
    });

    test('rejects malformed literals', () {
      expect(() => pythonLiteralToJson("{'a' 1}"),
          throwsA(isA<PythonConvertException>()));
      expect(() => pythonLiteralToJson("{'a': 1} extra"),
          throwsA(isA<PythonConvertException>()));
      expect(() => pythonLiteralToJson("'unterminated"),
          throwsA(isA<PythonConvertException>()));
    });
  });
}
