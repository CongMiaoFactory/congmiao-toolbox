import 'dart:convert';

/// Python literal → JSON conversion for the Python tool window: a small
/// recursive-descent parser over dict / list / tuple / str / num / bool /
/// None literals (the "字典转换" half of the original ruff-wasm tool).
class PythonConvertException implements Exception {
  const PythonConvertException(this.message);

  final String message;

  @override
  String toString() => message;
}

String pythonLiteralToJson(String source, {bool pretty = true}) {
  final parser = _PythonLiteralParser(source);
  final value = parser.parse();
  return pretty
      ? const JsonEncoder.withIndent('  ').convert(value)
      : jsonEncode(value);
}

class _PythonLiteralParser {
  _PythonLiteralParser(this.source);

  final String source;
  int _index = 0;

  Object? parse() {
    final value = _value();
    _skipWhitespace();
    if (_index != source.length) {
      throw const PythonConvertException('末尾存在多余内容');
    }
    return value;
  }

  Object? _value() {
    _skipWhitespace();
    if (_index >= source.length) {
      throw const PythonConvertException('输入不完整');
    }
    final char = source[_index];
    if (char == '{') return _dict();
    if (char == '[') return _sequence(']');
    if (char == '(') return _sequence(')');
    if (char == "'" || char == '"') return _string();
    if (_matchWord('True')) return true;
    if (_matchWord('False')) return false;
    if (_matchWord('None')) return null;
    return _number();
  }

  Map<String, Object?> _dict() {
    _index++; // {
    final result = <String, Object?>{};
    _skipWhitespace();
    if (_take('}')) return result;
    while (true) {
      final key = _value();
      _skipWhitespace();
      if (!_take(':')) throw const PythonConvertException('字典缺少冒号');
      final value = _value();
      result[key is String ? key : jsonEncode(key)] = value;
      _skipWhitespace();
      if (_take('}')) return result;
      if (!_take(',')) throw const PythonConvertException('字典缺少逗号');
      _skipWhitespace();
      if (_take('}')) return result; // trailing comma
    }
  }

  List<Object?> _sequence(String closer) {
    _index++; // [ or (
    final result = <Object?>[];
    _skipWhitespace();
    if (_take(closer)) return result;
    while (true) {
      result.add(_value());
      _skipWhitespace();
      if (_take(closer)) return result;
      if (!_take(',')) throw const PythonConvertException('列表缺少逗号');
      _skipWhitespace();
      if (_take(closer)) return result; // trailing comma
    }
  }

  String _string() {
    final quote = source[_index];
    _index++;
    final buffer = StringBuffer();
    while (true) {
      if (_index >= source.length) {
        throw const PythonConvertException('字符串未闭合');
      }
      final char = source[_index];
      if (char == quote) {
        _index++;
        return buffer.toString();
      }
      if (char == r'\') {
        _index++;
        if (_index >= source.length) {
          throw const PythonConvertException('转义序列不完整');
        }
        final escape = source[_index];
        _index++;
        switch (escape) {
          case 'n':
            buffer.write('\n');
          case 't':
            buffer.write('\t');
          case 'r':
            buffer.write('\r');
          case 'b':
            buffer.write('\b');
          case 'f':
            buffer.write('\f');
          case '0':
            buffer.write('\x00');
          case 'x':
            buffer.writeCharCode(_hex(2));
          case 'u':
            buffer.writeCharCode(_hex(4));
          default:
            buffer.write(escape);
        }
        continue;
      }
      buffer.write(char);
      _index++;
    }
  }

  int _hex(int digits) {
    if (_index + digits > source.length) {
      throw const PythonConvertException('转义序列不完整');
    }
    final value =
        int.tryParse(source.substring(_index, _index + digits), radix: 16);
    if (value == null) {
      throw const PythonConvertException('非法的十六进制转义');
    }
    _index += digits;
    return value;
  }

  Object _number() {
    final match = RegExp(r'^[+-]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?')
        .firstMatch(source.substring(_index));
    if (match == null) {
      throw const PythonConvertException('无法识别的字面量');
    }
    final text = match.group(0)!;
    _index += text.length;
    final asInt = int.tryParse(text);
    if (asInt != null) return asInt;
    return double.parse(text);
  }

  bool _matchWord(String word) {
    if (!source.startsWith(word, _index)) return false;
    final end = _index + word.length;
    if (end < source.length &&
        RegExp(r'[A-Za-z0-9_]').hasMatch(source[end])) {
      return false;
    }
    _index = end;
    return true;
  }

  bool _take(String char) {
    if (_index < source.length && source[_index] == char) {
      _index++;
      return true;
    }
    return false;
  }

  void _skipWhitespace() {
    while (_index < source.length &&
        RegExp(r'\s').hasMatch(source[_index])) {
      _index++;
    }
  }
}
