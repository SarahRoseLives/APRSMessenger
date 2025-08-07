import 'dart:html' as html;

Future<bool> launchPlatformUrl(String url) async {
  html.window.location.href = url;
  return true;
}