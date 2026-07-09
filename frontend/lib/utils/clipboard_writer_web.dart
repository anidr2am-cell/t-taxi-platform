// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:flutter/services.dart';

Future<void> writeClipboardText(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return;
  } catch (_) {
    final textArea = html.TextAreaElement()
      ..value = text
      ..style.position = 'fixed'
      ..style.opacity = '0'
      ..style.pointerEvents = 'none';
    html.document.body?.append(textArea);
    textArea
      ..focus()
      ..select();
    try {
      final copied = html.document.execCommand('copy');
      if (!copied) {
        throw StateError('Browser clipboard copy failed');
      }
    } finally {
      textArea.remove();
    }
  }
}
