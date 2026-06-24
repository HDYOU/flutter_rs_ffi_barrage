// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_rs_ffi_barrage_example/main.dart';

void main() {
  testWidgets('Barrage demo app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BarrageDemoApp());

    // Verify that the app title is present.
    expect(find.text('Flutter Rust FFI 弹幕演示'), findsOneWidget);

    // Verify the barrage demo page is rendered.
    expect(find.text('发送'), findsOneWidget);

    // Verify control buttons are present.
    expect(find.text('暂停'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);
  });
}
