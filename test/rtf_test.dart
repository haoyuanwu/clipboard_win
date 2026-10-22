import 'package:flutter_test/flutter_test.dart';
import 'package:clipboard_win/src/rtf_preview.dart';

void main() {
  test('RTF preview retains styles, colors, Unicode and escaped text', () {
    final html = rtfPreview(
      r'{\rtf1\ansi{\colortbl;\red255\green0\blue0;}\cf1\b Hello\b0\par\u20320?\u22909?\i italic\i0 \{x\}}',
    );
    expect(html, contains('rgb(255,0,0)'));
    expect(html, contains('font-weight:bold'));
    expect(html, contains('font-style:italic'));
    expect(html.replaceAll(RegExp('<[^>]+>'), ''), contains('你好'));
    expect(html, contains('{x}'));
    expect(html, isNot(contains('colortbl')));
  });
  test('RTF destinations never leak metadata into content', () {
    final html = rtfPreview(
      r'{\rtf1{\fonttbl{\f0 Segoe UI;}}{\*\generator Test;}\f0 plain}',
    );
    expect(html, contains('plain'));
    expect(html, isNot(contains('generator')));
    expect(html, isNot(contains('Segoe')));
  });
}
