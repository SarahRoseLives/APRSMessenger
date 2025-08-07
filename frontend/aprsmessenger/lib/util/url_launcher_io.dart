import 'package:url_launcher/url_launcher.dart';

Future<bool> launchPlatformUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return false;
}