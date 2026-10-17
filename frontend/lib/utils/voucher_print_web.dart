// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'dart:typed_data';

void printVoucher(Uint8List bytes) {
  final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], 'image/png'));
  final frame = html.IFrameElement()
    ..src = url
    ..style.position = 'fixed'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = '0';
  html.document.body?.append(frame);
  frame.onLoad.first.then((_) {
    if (frame.contentWindow != null)
      (frame.contentWindow as html.Window).print();
  });
  // Keep the frame alive for the print dialog; remove after it has closed.
  html.window.addEventListener('afterprint', (_) {
    frame.remove();
    html.Url.revokeObjectUrl(url);
  });
}
