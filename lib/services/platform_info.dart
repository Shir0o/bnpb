import 'platform_info_stub.dart' if (dart.library.io) 'platform_info_io.dart'
    as impl;

Future<int?> androidSdkInt() => impl.androidSdkInt();

bool get isAndroid => impl.isAndroid;
