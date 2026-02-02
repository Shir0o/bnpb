import 'package:flutter_test/flutter_test.dart';

class A {
  int foo() => 1;
}

class MockA extends Fake implements A {
  @override
  int foo() => 2;
}

void main() {
  test('fake test', () {
    expect(MockA().foo(), 2);
  });
}
