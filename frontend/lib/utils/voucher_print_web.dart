// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> printVoucher(Uint8List bytes) async {
  final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], 'image/png'));
  final frame = html.IFrameElement()
    ..src = url
    ..style.position = 'fixed'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = '0';
  void cleanup() { frame.remove(); html.Url.revokeObjectUrl(url); }
  html.document.body?.append(frame);
  try {
    await frame.onLoad.first.timeout(const Duration(seconds: 10));
    final window = frame.contentWindow as html.Window;
    window.addEventListener('afterprint', (_) => cleanup());
    window.print();
  } catch (_) { cleanup(); rethrow; }
}
