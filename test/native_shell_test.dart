import 'package:ai_music/src/presentation/native_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a tab being left cannot clear the bar the shown tab just wrote', () {
    final shell = NativeShell.instance;
    final home = Object(), downloads = Object();
    addTearDown(() {
      shell.clearPage(0, nested: true);
    });

    shell.updatePage(0, {'title': 'Downloads'}, nested: true, owner: downloads);
    // Switching back to Home: Home rebuilds first and writes its bar…
    shell.updatePage(0, {'title': 'Home'}, nested: true, owner: home);
    // …then Downloads, now hidden, clears what it wrote.
    shell.clearPage(0, nested: true, owner: downloads);

    expect(shell.nestedSpecFor(0), {'title': 'Home'});

    shell.clearPage(0, nested: true, owner: home);
    expect(shell.nestedSpecFor(0), isNull);
  });
}
