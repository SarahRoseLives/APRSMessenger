import 'dart:convert';
import 'dart:html' as html;

void exportData(dynamic data) {
  final prettyJson = JsonEncoder.withIndent('  ').convert(data); // REMOVE "const"
  final blob = html.Blob([prettyJson], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute("download", "aprs_chat_export.json")
    ..click();
  html.Url.revokeObjectUrl(url);
}