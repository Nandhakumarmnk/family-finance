// Picks the browser implementation on web and the no-op stub everywhere else,
// so `dart:html` never leaks into the mobile/desktop build.
export 'web_notifier_stub.dart'
    if (dart.library.html) 'web_notifier_html.dart';
