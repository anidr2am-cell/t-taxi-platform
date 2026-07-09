import 'package:flutter/services.dart';

Future<void> writeClipboardText(String text) {
  return Clipboard.setData(ClipboardData(text: text));
}
