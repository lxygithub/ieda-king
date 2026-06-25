import 'package:flutter_test/flutter_test.dart';
import 'package:idea_king/models/shared_file.dart';

void main() {
  group('SharedFile', () {
    test('toJson and fromJson round-trip', () {
      final file = SharedFile(
        id: 'test-123',
        name: 'test.png',
        type: SharedFileType.image,
        localPath: '/tmp/test.png',
        receivedAt: DateTime(2026, 6, 17, 14, 30),
        mimeType: 'image/png',
        fileSize: 102400,
      );

      final json = file.toJson();
      final restored = SharedFile.fromJson(json);

      expect(restored.id, file.id);
      expect(restored.name, file.name);
      expect(restored.type, file.type);
      expect(restored.localPath, file.localPath);
      expect(restored.receivedAt, file.receivedAt);
      expect(restored.mimeType, file.mimeType);
      expect(restored.fileSize, file.fileSize);
    });

    test('displayDate returns yyyy-MM-dd', () {
      final file = SharedFile(
        id: '1',
        name: 'a.txt',
        type: SharedFileType.text,
        textContent: 'hello',
        receivedAt: DateTime(2026, 6, 17, 8, 15),
      );
      expect(file.displayDate, '2026-06-17');
    });

    test('equality by id', () {
      final a = SharedFile(
        id: '1',
        name: 'a.txt',
        type: SharedFileType.text,
        textContent: 'a',
        receivedAt: DateTime(2026, 1, 1),
      );
      final b = SharedFile(
        id: '1',
        name: 'renamed.txt',
        type: SharedFileType.image,
        localPath: '/x/y.png',
        receivedAt: DateTime(2026, 6, 1),
      );
      expect(a == b, true);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('SharedFileType', () {
    test('labels are non-empty', () {
      for (final t in SharedFileType.values) {
        expect(t.label.isNotEmpty, true);
        expect(t.icon, isNotNull);
      }
    });
  });
}
