import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (stored, expected) in <(Object?, double)>[
    (null, 120),
    (120, 120),
    (150, 150),
    (150.5, 150.5),
    (0, 80),
    (300, 260),
    ('invalid', 120),
    (double.nan, 120),
    (double.infinity, 120),
  ]) {
    test('cover width safely reads $stored', () async {
      SharedPreferences.setMockInitialValues({
        if (stored != null) 'bookCoverWidth': stored,
      });
      await Prefs().initPrefs();
      expect(Prefs().bookCoverWidth, expected);
    });
  }
}
