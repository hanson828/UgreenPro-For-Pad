import 'package:flutter_test/flutter_test.dart';
import 'package:ugreen_cloud_shell/main.dart';

void main() {
  testWidgets('登录页展示连接方式与主要操作', (tester) async {
    await tester.pumpWidget(const UgreenCloudShellApp());
    await tester.pumpAndSettle();

    expect(find.text('登录绿联云'), findsOneWidget);
    expect(find.text('登录并进入'), findsOneWidget);
    expect(find.text('记住账号密码'), findsOneWidget);
    expect(find.text('自动登录'), findsOneWidget);
    expect(find.text('局域网'), findsOneWidget);
    expect(find.text('UGREENlink'), findsOneWidget);
  });
}
