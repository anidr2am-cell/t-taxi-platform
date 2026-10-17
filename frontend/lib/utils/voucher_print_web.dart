import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> printVoucher(Uint8List bytes) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final url = web.URL.createObjectURL(blob);
  final frame = web.HTMLIFrameElement()
    ..src = url
    ..style.position = 'fixed'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = '0';
  final loaded = Completer<void>();
  frame.addEventListener(
    'load',
    ((web.Event _) {
      if (!loaded.isCompleted) loaded.complete();
    }).toJS,
  );
  void cleanup() {
    frame.remove();
    web.URL.revokeObjectURL(url);
  }

  web.document.body?.appendChild(frame);
  try {
    await loaded.future.timeout(const Duration(seconds: 10));
    final window = frame.contentWindow;
    if (window == null) throw StateError('Print frame is unavailable');
    window.addEventListener('afterprint', ((web.Event _) => cleanup()).toJS);
    window.print();
  } catch (_) {
    cleanup();
    rethrow;
  }
}
