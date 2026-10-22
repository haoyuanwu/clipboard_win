import 'dart:convert';

/// Common RTF styles for preview; the original payload is retained for copying.
String rtfPreview(String rtf) {
  if (!rtf.startsWith(r'{\rtf')) return '';
  final colors = <String>['inherit'];
  final table =
      RegExp(r'\{\\colortbl([^}]*)\}').firstMatch(rtf)?.group(1) ?? '';
  for (final color in table.split(';').skip(1)) {
    int channel(String name) =>
        int.tryParse(
          RegExp('\\\\$name(\\d+)').firstMatch(color)?.group(1) ?? '',
        ) ??
        0;
    if (color.contains(r'\red')) {
      colors.add(
        'rgb(${channel('red')},${channel('green')},${channel('blue')})',
      );
    }
  }
  final stack = <Map<String, dynamic>>[];
  var state = <String, dynamic>{'skip': false, 'uc': 1};
  final output = StringBuffer();
  var text = StringBuffer();
  void flush() {
    if (text.isEmpty) return;
    if (state['skip'] != true) {
      final css = <String>[];
      if (state['b'] == true) css.add('font-weight:bold');
      if (state['i'] == true) css.add('font-style:italic');
      if (state['ul'] == true) css.add('text-decoration:underline');
      if (state['strike'] == true) css.add('text-decoration:line-through');
      if (state['fs'] != null) css.add('font-size:${state['fs'] / 2}pt');
      for (final pair in {
        'cf': 'color',
        'highlight': 'background-color',
      }.entries) {
        final n = state[pair.key] as int? ?? 0;
        if (n > 0 && n < colors.length) css.add('${pair.value}:${colors[n]}');
      }
      output.write(
        '<span style="${const HtmlEscape().convert(css.join(';'))}">${const HtmlEscape().convert(text.toString())}</span>',
      );
    }
    text = StringBuffer();
  }

  var fallback = 0;
  for (var i = 0; i < rtf.length;) {
    final char = rtf[i++];
    if (char == '{') {
      flush();
      stack.add({...state});
      continue;
    }
    if (char == '}') {
      flush();
      if (stack.isNotEmpty) state = stack.removeLast();
      continue;
    }
    if (char != r'\') {
      if (char != '\r' && char != '\n') {
        if (fallback > 0) {
          fallback--;
        } else {
          text.write(char);
        }
      }
      continue;
    }
    if (i >= rtf.length) break;
    final symbol = rtf[i];
    if (symbol == r'\' || symbol == '{' || symbol == '}') {
      i++;
      if (fallback > 0) {
        fallback--;
      } else {
        text.write(symbol);
      }
      continue;
    }
    if (symbol == "'" && i + 2 < rtf.length) {
      final n = int.tryParse(rtf.substring(i + 1, i + 3), radix: 16) ?? 32;
      i += 3;
      if (fallback > 0) {
        fallback--;
      } else {
        text.writeCharCode(n);
      }
      continue;
    }
    if (symbol == '*') {
      flush();
      state['skip'] = true;
      i++;
      continue;
    }
    if (!RegExp('[a-zA-Z]').hasMatch(symbol)) {
      i++;
      if (symbol == '~') text.write(' ');
      continue;
    }
    final m = RegExp(r'^([a-zA-Z]+)(-?\d+)? ?').firstMatch(rtf.substring(i))!;
    i += m.end;
    final word = m.group(1)!;
    final n = int.tryParse(m.group(2) ?? '');
    flush();
    if ([
      'fonttbl',
      'colortbl',
      'stylesheet',
      'info',
      'pict',
      'object',
      'header',
      'footer',
      'generator',
      'listtable',
      'listoverridetable',
    ].contains(word)) {
      state['skip'] = true;
    } else if (['b', 'i', 'ul', 'strike'].contains(word)) {
      state[word] = n != 0;
    } else if (word == 'ulnone') {
      state['ul'] = false;
    } else if (['cf', 'highlight', 'fs'].contains(word)) {
      state[word] = n;
    } else if (word == 'uc') {
      state['uc'] = n ?? 1;
    } else if (word == 'u' && n != null) {
      text.writeCharCode(n < 0 ? n + 65536 : n);
      fallback = state['uc'] as int;
    } else if (word == 'par' || word == 'line') {
      if (state['skip'] != true) output.write('<br>');
    } else if (word == 'tab') {
      text.write('    ');
    } else if (word == 'plain') {
      final skip = state['skip'];
      final uc = state['uc'];
      state = {'skip': skip, 'uc': uc};
    } else if (word == 'emdash') {
      text.write('—');
    } else if (word == 'endash') {
      text.write('–');
    } else if (word == 'bullet') {
      text.write('•');
    }
  }
  flush();
  return '<div>${output.toString()}</div>';
}
