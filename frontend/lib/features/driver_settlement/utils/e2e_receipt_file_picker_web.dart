// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import '../pages/driver_settlement_list_page.dart';

ReceiptFilePicker? e2eWebReceiptFilePicker() => _pickReceiptWithNativeInput;

Future<ReceiptPickResult?> _pickReceiptWithNativeInput() async {
  final input = html.FileUploadInputElement()
    ..accept = '.jpg,.jpeg,.png,.pdf'
    ..multiple = false
    ..style.display = 'none'
    ..setAttribute('aria-label', 'E2E receipt file input');
  html.document.body?.append(input);

  try {
    final change = input.onChange.first;
    input.click();
    await change;

    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) return null;

    final reader = html.FileReader();
    final load = reader.onLoad.first;
    final error = reader.onError.first.then<void>((_) {
      throw StateError('E2E receipt file could not be read');
    });
    reader.readAsArrayBuffer(file);
    await Future.any([load, error]);

    final result = reader.result;
    if (result is ByteBuffer) {
      return (bytes: Uint8List.view(result), filename: file.name);
    }
    if (result is Uint8List) {
      return (bytes: result, filename: file.name);
    }
    return null;
  } finally {
    input.remove();
  }
}
