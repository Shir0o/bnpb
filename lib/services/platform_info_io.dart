import 'dart:io';

Future<int?> androidSdkInt() async {
  final version = Platform.operatingSystemVersion;
  final sdkMatch = RegExp(r'SDK(?:\s+)?(\d+)').firstMatch(version);
  if (sdkMatch != null) {
    return int.tryParse(sdkMatch.group(1)!);
  }

  final androidMatch = RegExp(r'Android\s+(\d+)').firstMatch(version);
  if (androidMatch != null) {
    final major = int.tryParse(androidMatch.group(1)!);
    if (major != null) {
      if (major >= 12) {
        return 31;
      }
      return 30;
    }
  }

  return null;
}

bool get isAndroid => Platform.isAndroid;
