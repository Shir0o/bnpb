import 'dart:convert';
import 'dart:ffi';

typedef _SetenvC = Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Int32);
typedef _SetenvD = int Function(Pointer<Uint8>, Pointer<Uint8>, int);
typedef _MallocC = Pointer<Uint8> Function(IntPtr);
typedef _MallocD = Pointer<Uint8> Function(int);

/// Switches this test process's local time zone (setenv + tzset), so the
/// timezone tests bite on a UTC CI runner too. Each test file runs in its own
/// process, so this does not leak into other files.
void setProcessTimeZone(String tz) {
  final libc = DynamicLibrary.process();
  final malloc = libc.lookupFunction<_MallocC, _MallocD>('malloc');
  Pointer<Uint8> cString(String s) {
    final units = utf8.encode(s);
    final p = malloc(units.length + 1);
    for (var i = 0; i < units.length; i++) {
      p[i] = units[i];
    }
    p[units.length] = 0;
    return p;
  }

  libc.lookupFunction<_SetenvC, _SetenvD>('setenv')(
      cString('TZ'), cString(tz), 1);
  libc.lookupFunction<Void Function(), void Function()>('tzset')();
}
