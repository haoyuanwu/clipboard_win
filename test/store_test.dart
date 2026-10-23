import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:clipboard_win/src/store.dart';
import 'package:clipboard_win/src/model.dart';

void main() {
  late Directory sandbox;
  late ClipboardStore store;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('superclipboard-test-');
    store = ClipboardStore(
      directory: Directory('${sandbox.path}/app'),
      usePlatform: false,
    );
    await store.initialize();
  });
  tearDown(() async {
    store.dispose();
    await sandbox.delete(recursive: true);
  });
  Future<void> ingest(Map<String, dynamic> data) async {
    expect(
      await store.command({'op': 'ingest', 'data': data}),
      isTrue,
      reason: store.error,
    );
  }

  for (final identity in ['', 'unrecognized-external-identity']) {
    test(
      'external folder with identity "$identity" still asks and remembers grouping',
      () async {
        final folder = await Directory('${sandbox.path}/external').create();
        await File('${folder.path}/first.txt').writeAsString('first');
        expect(
          await store.command({
            'op': 'drop',
            'data': {
              'paths': [folder.path],
              'fingerprint': identity,
            },
          }),
          isTrue,
        );
        expect(store.transfer, isEmpty);
        expect(store.folderDrops, hasLength(1));
        expect(
          await store.command({
            'op': 'resolveFolderDrop',
            'id': store.folderDrops.single['id'],
            'choice': 'group',
            'remember': true,
          }),
          isTrue,
        );
        expect(store.transfer.single.isFileGroup, isTrue);
        expect(store.transfer.single.paths.single, endsWith('first.txt'));
        final next = await Directory('${sandbox.path}/next').create();
        await File('${next.path}/next.txt').writeAsString('next');
        expect(
          await store.command({
            'op': 'drop',
            'data': {
              'paths': [next.path],
              'fingerprint': identity,
            },
          }),
          isTrue,
        );
        expect(store.folderDrops, isEmpty);
        expect(store.transfer.first.isFileGroup, isTrue);
        expect(store.transfer.first.paths.single, endsWith('next.txt'));
      },
    );
  }

  test(
    'folder drops ask, remember choice, and preserve nested directories',
    () async {
      final folder = await Directory('${sandbox.path}/输入').create();
      await File('${folder.path}/a.txt').writeAsString('a');
      final nested = await Directory('${folder.path}/子文件夹').create();
      await File('${nested.path}/b.txt').writeAsString('b');
      await store.command({
        'op': 'drop',
        'data': {
          'paths': [folder.path],
        },
      });
      expect(store.transfer, isEmpty);
      expect(store.folderDrops, hasLength(1));
      await store.command({
        'op': 'resolveFolderDrop',
        'id': store.folderDrops.single['id'],
        'choice': 'group',
        'remember': true,
      });
      expect(store.folderDrops, isEmpty);
      expect(store.settings['folderDropMode'], 'group');
      final group = store.transfer.single;
      expect(group.isFileGroup, isTrue);
      expect(group.paths, hasLength(2));
      expect(await File('${group.paths.last}/b.txt').readAsString(), 'b');
      expect(await File('${folder.path}/a.txt').readAsString(), 'a');
      final reopened = ClipboardStore(
        directory: store.root,
        usePlatform: false,
      );
      await reopened.initialize();
      expect(reopened.settings['folderDropMode'], 'group');
      expect(reopened.folderDrops, isEmpty);
      expect(reopened.transfer.single.isFileGroup, isTrue);
      reopened.dispose();
    },
  );

  test(
    'cancel leaves preferences and sources intact; preserve and reset work',
    () async {
      final folder = await Directory('${sandbox.path}/folder').create();
      await File('${folder.path}/a.txt').writeAsString('a');
      Future<void> drop() async {
        await store.command({
          'op': 'drop',
          'data': {
            'paths': [folder.path],
          },
        });
      }

      await drop();
      await store.command({
        'op': 'resolveFolderDrop',
        'id': store.folderDrops.single['id'],
        'choice': 'cancel',
        'remember': true,
      });
      expect(store.settings['folderDropMode'], 'ask');
      expect(store.transfer, isEmpty);
      await drop();
      await store.command({
        'op': 'resolveFolderDrop',
        'id': store.folderDrops.single['id'],
        'choice': 'folder',
        'remember': true,
      });
      expect(store.transfer.single.isFileGroup, isFalse);
      expect(
        await File('${store.transfer.single.paths.single}/a.txt')
            .readAsString(),
        'a',
      );
      await store.setting('folderDropMode', 'ask');
      await drop();
      expect(store.folderDrops, hasLength(1));
    },
  );

  test(
    'one-member groups survive archiving; empty folders retain their directory',
    () async {
      await store.setting('folderDropMode', 'group');
      final folder = await Directory('${sandbox.path}/one').create();
      await File('${folder.path}/only.txt').writeAsString('only');
      await store.command({
        'op': 'drop',
        'data': {
          'paths': [folder.path],
        },
      });
      final group = store.transfer.single;
      expect(group.isFileGroup, isTrue);
      expect(group.paths, hasLength(1));
      expect(ClipEntry.fromJson(group.toJson()).isFileGroup, isTrue);
      final empty = await Directory('${sandbox.path}/empty').create();
      await store.command({
        'op': 'drop',
        'data': {
          'paths': [empty.path],
        },
      });
      final saved = store.transfer.first;
      expect(saved.isFileGroup, isFalse);
      expect(await Directory(saved.paths.single).exists(), isTrue);
    },
  );

  test(
    'multi-file transfer dragged back as one folder is not duplicated',
    () async {
      final first = File('${sandbox.path}/one.txt');
      await first.writeAsString('one');
      final second = File('${sandbox.path}/two.txt');
      await second.writeAsString('two');
      await store.command({
        'op': 'drop',
        'data': {
          'paths': [first.path, second.path],
        },
      });
      final entry = store.transfer.single;
      final group = File(entry.paths.first).parent.parent.path;
      await store.command({
        'op': 'drop',
        'data': {
          'paths': [group],
          'fingerprint': entry.fingerprint,
        },
      });
      expect(store.transfer, hasLength(1));
      expect(store.history, isEmpty);
      expect(await File(entry.paths[1]).readAsString(), 'two');
    },
  );
  test('history limit applies only to unpinned entries', () async {
    final now = DateTime.now();
    store.history = List.generate(
      108,
      (i) => ClipEntry(
        id: 'fixture-$i',
        fingerprint: '$i',
        kind: EntryKind.text,
        text: '$i',
        createdAt: now.add(Duration(seconds: i)),
        lastCopiedAt: now,
        pinned: i < 5,
      ),
    );
    await store.setting('limit', 100);
    expect(store.history, hasLength(105));
    expect(store.history.where((e) => e.pinned), hasLength(5));
    expect(store.history.any((e) => e.text == '5'), isFalse);
    expect(store.history.any((e) => e.text == '107'), isTrue);
  });
  test(
    'duplicates merge; counts, pins and settings survive a restart',
    () async {
      await ingest({'text': '你好 Windows', 'html': '<b>你好 Windows</b>'});
      await ingest({'text': '你好 Windows'});
      expect(store.history, hasLength(1));
      expect(store.history.single.count, 2);
      final entry = store.history.single;
      await store.command({'op': 'pin', 'id': entry.id});
      await store.setting('appearance', 'dark');
      final reopened = ClipboardStore(
        directory: store.root,
        usePlatform: false,
      );
      await reopened.initialize();
      expect(reopened.history.single.pinned, isTrue);
      expect(reopened.history.single.html, '<b>你好 Windows</b>');
      expect(reopened.settings['appearance'], 'dark');
      reopened.dispose();
    },
  );
  test('notebook retains an independent file after source deletion and history clear', () async {
    final source = File('${sandbox.path}/original.txt');
    await source.writeAsString('独立副本');
    await ingest({
      'paths': [source.path],
    });
    final entry = store.history.single;
    expect(
      await store.command({
        'op': 'archive',
        'id': entry.id,
        'target': 'notebook',
      }),
      isTrue,
    );
    expect(store.notebook.single.paths.single, isNot(source.path));
    await source.delete();
    await store.command({'op': 'clear'});
    expect(store.history, isEmpty);
    expect(store.notebook, hasLength(1));
    expect(
      await File(store.notebook.single.paths.single).readAsString(),
      '独立副本',
    );
    expect(await store.copy(store.notebook.single), isTrue);
    expect(
      await store.command({
        'op': 'archive',
        'library': 'notebook',
        'id': store.notebook.single.id,
        'target': 'notebook',
      }),
      isTrue,
    );
    expect(store.notebook, hasLength(1));
  });
  test(
    'notebook migration rewrites attachments and rejects occupied destinations',
    () async {
      final source = File('${sandbox.path}/original.txt');
      await source.writeAsString('移动');
      await ingest({
        'paths': [source.path],
      });
      await store.command({
        'op': 'archive',
        'id': store.history.single.id,
        'target': 'notebook',
      });
      final parent = Directory('${sandbox.path}/destination');
      await parent.create();
      expect(
        await store.command({'op': 'migrate', 'path': parent.path}),
        isTrue,
        reason: store.error,
      );
      final movedPath = store.notebook.single.paths.single;
      expect(movedPath, startsWith(parent.path));
      expect(await File(movedPath).readAsString(), '移动');
      expect(
        await store.command({'op': 'migrate', 'path': parent.path}),
        isFalse,
      );
      expect(await File(movedPath).readAsString(), '移动');
      final reopened = ClipboardStore(
        directory: store.root,
        usePlatform: false,
      );
      await reopened.initialize();
      expect(reopened.notebook.single.paths.single, movedPath);
      reopened.dispose();
    },
  );
  test(
    'failed archives are rolled back and original paths are never deleted',
    () async {
      final source = File('${sandbox.path}/missing.txt');
      await ingest({
        'paths': [source.path],
      });
      expect(
        await store.command({
          'op': 'archive',
          'id': store.history.single.id,
          'target': 'notebook',
        }),
        isFalse,
      );
      expect(store.notebook, isEmpty);
      expect(store.busy, isFalse);
      await source.writeAsString('原始文件');
      await store.command({'op': 'delete', 'id': store.history.single.id});
      expect(await source.readAsString(), '原始文件');
    },
  );
  test(
    'transfer deduplicates drops, saves copies and keeps history opt-in',
    () async {
      final source = File('${sandbox.path}/transfer.txt');
      await source.writeAsString('中转');
      final drop = {
        'op': 'drop',
        'data': {
          'paths': [source.path],
        },
      };
      await store.command(drop);
      await store.command(drop);
      expect(store.transfer, hasLength(1));
      expect(store.history, isEmpty);
      await store.command({
        'op': 'drop',
        'data': {'paths': store.transfer.single.paths},
      });
      expect(store.transfer, hasLength(1));
      await source.delete();
      expect(await store.copy(store.transfer.single), isTrue);
      await store.setting('transferHistory', true);
      await store.command({
        'op': 'drop',
        'data': {'text': '写入历史'},
      });
      expect(store.history.single.text, '写入历史');
      await store.setting('transferMinutes', 2000);
      expect(store.settings['transferMinutes'], 1440);
      await store.setting('transferMinutes', 0);
      expect(store.settings['transferMinutes'], 1);
      await store.command({'op': 'transferVisibility', 'visible': false});
      expect(store.snapshot['deadline'], isNotNull);
      await store.command({'op': 'transferVisibility', 'visible': true});
      expect(store.snapshot['deadline'], isNull);
    },
  );
  test('clear protects pinned entries and never touches notebook', () async {
    await ingest({'text': '保留'});
    final pinned = store.history.single;
    await store.command({'op': 'pin', 'id': pinned.id});
    await store.command({
      'op': 'archive',
      'id': pinned.id,
      'target': 'notebook',
    });
    await ingest({'text': '删除'});
    await store.command({'op': 'clear'});
    expect(store.history.single.text, '保留');
    expect(store.notebook.single.text, '保留');
  });
  test('image copies are independent and duplicate bytes merge', () async {
    final image = File('${sandbox.path}/image.png');
    await image.writeAsBytes([1, 2, 3, 4]);
    await ingest({'imagePath': image.path});
    await ingest({'imagePath': image.path});
    expect(store.history, hasLength(1));
    expect(store.history.single.count, 2);
    await store.command({
      'op': 'archive',
      'id': store.history.single.id,
      'target': 'notebook',
    });
    await image.delete();
    await store.command({'op': 'clear'});
    expect(await File(store.notebook.single.imagePath).readAsBytes(), [
      1,
      2,
      3,
      4,
    ]);
  });
  test(
    'session order stays stable on copy and appends new entries until reopened',
    () {
      final now = DateTime.now();
      ClipEntry make(String id, int minute, int count, {bool pin = false}) =>
          ClipEntry(
            id: id,
            fingerprint: id,
            kind: EntryKind.text,
            createdAt: now.add(Duration(minutes: minute)),
            lastCopiedAt: now,
            count: count,
            pinned: pin,
          );
      final a = make('a', 0, 1), b = make('b', 1, 2), c = make('c', 2, 1);
      final session = ListSession()..begin([a, b], 'count');
      a.count = 10;
      expect(session.entries([a, b, c]).map((e) => e.id), ['b', 'a', 'c']);
      session.begin([a, b, c], 'count');
      expect(session.entries([a, b, c]).first.id, 'a');
      b.pinned = true;
      session.begin([a, b, c], 'time');
      expect(session.entries([a, b, c]).map((e) => e.id), ['b', 'c', 'a']);
    },
  );
  test(
    'window chrome defaults to Windows and saves an explicit macOS choice',
    () async {
      expect(store.windowsStyle, isTrue);
      await store.setting('titleBarStyle', 'mac');
      final reloaded = ClipboardStore(
        directory: store.root,
        usePlatform: false,
      );
      await reloaded.initialize();
      expect(reloaded.windowsStyle, isFalse);
      expect(reloaded.settings['titleBarStyle'], 'mac');
      reloaded.dispose();
      // Existing archives without the new preference also receive the Windows default.
      final file = File('${store.root.path}/state.json');
      final previous = await file.readAsString();
      await file.writeAsString(
        previous
            .replaceAll('"titleBarStyle":"mac",', '')
            .replaceAll(',"titleBarStyle":"mac"', ''),
      );
      final legacy = ClipboardStore(directory: store.root, usePlatform: false);
      await legacy.initialize();
      expect(legacy.windowsStyle, isTrue);
      legacy.dispose();
    },
  );
  test('partial groups copy and drag only existing members without changing drag counts', () async {
    final a = File('${sandbox.path}/a.txt')..writeAsStringSync('a');
    final b = File('${sandbox.path}/b.txt')..writeAsStringSync('b');
    await ingest({
      'paths': [a.path, b.path],
    });
    final entry = store.history.single;
    await b.delete();
    await store.refreshAvailability();
    expect(store.status(entry).isPartial, isTrue);
    expect((await store.dragPayload(entry))!['paths'], [a.path]);
    expect(entry.count, 1);
    expect(await store.copy(entry), isTrue);
    expect(entry.count, 2);
    expect(
      await store.command({'op': 'copy', 'id': entry.id, 'path': b.path}),
      isFalse,
    );
    expect(
      await store.command({
        'op': 'copy',
        'id': entry.id,
        'path': '${sandbox.path}/outside.txt',
      }),
      isFalse,
    );
    await a.delete();
    expect(await store.dragPayload(entry), isNull);
    expect(await store.copy(entry), isFalse);
    expect(entry.count, 2);
  });
  test('invalid cleanup protects pins, partial groups, notebook and restored files', () async {
    final lost = File('${sandbox.path}/lost.txt')..writeAsStringSync('lost');
    final pinned = File('${sandbox.path}/pinned.txt')..writeAsStringSync('pin');
    final alive = File('${sandbox.path}/alive.txt')..writeAsStringSync('alive');
    await ingest({
      'paths': [lost.path],
    });
    final first = store.history.single;
    await store.command({
      'op': 'archive',
      'id': first.id,
      'target': 'notebook',
    });
    await ingest({
      'paths': [pinned.path],
    });
    final pin = store.history.first;
    await store.command({'op': 'pin', 'id': pin.id});
    await ingest({
      'paths': [alive.path, lost.path],
    });
    await lost.delete();
    await pinned.delete();
    await store.refreshAvailability();
    expect(store.status(first).isMissing, isTrue);
    // The confirmation captured this ID; restoring before confirmation must save it.
    await lost.writeAsString('restored');
    expect(
      await store.command({
        'op': 'cleanInvalid',
        'ids': [first.id],
      }),
      isTrue,
    );
    expect(store.history, contains(first));
    await lost.delete();
    expect(await store.command({'op': 'cleanInvalid'}), isTrue);
    expect(store.history.map((e) => e.id), contains(pin.id));
    expect(store.history, hasLength(2));
    expect(
      await File(store.notebook.single.paths.single).readAsString(),
      'lost',
    );
    final reopened = ClipboardStore(directory: store.root, usePlatform: false);
    await reopened.initialize();
    expect(reopened.history, hasLength(2));
    reopened.dispose();
  });
  test('invalid cleanup rolls back its list if persistence fails', () async {
    final original = File('${sandbox.path}/gone.txt')
      ..writeAsStringSync('original');
    await ingest({
      'paths': [original.path],
    });
    final entry = store.history.single;
    await original.delete();
    final blocker = Directory('${store.root.path}/state.json.tmp');
    await blocker.create();
    expect(await store.command({'op': 'cleanInvalid'}), isFalse);
    expect(store.history.single.id, entry.id);
    await blocker.delete();
    expect(await store.command({'op': 'cleanInvalid'}), isTrue);
    expect(store.history, isEmpty);
  });
  test(
    'shortcut defaults and disabled custom combination survive reopening',
    () async {
      expect((store.settings['popoverShortcut'] as Map)['key'], 67);
      expect((store.settings['transferShortcut'] as Map)['key'], 86);
      final custom = {
        'enabled': false,
        'modifiers': 6,
        'key': 75,
        'label': 'Ctrl + Shift + K',
      };
      await store.setting('transferShortcut', custom);
      final reopened = ClipboardStore(
        directory: store.root,
        usePlatform: false,
      );
      await reopened.initialize();
      expect(reopened.settings['transferShortcut'], custom);
      reopened.dispose();
    },
  );
  test(
    'virtual file staging is released only after independent archive succeeds',
    () async {
      final staging = Directory('${store.root.path}/Cache/drop-123')
        ..createSync();
      final file = File('${staging.path}/attachment.txt')
        ..writeAsStringSync('attachment');
      expect(
        await store.command({
          'op': 'drop',
          'data': {
            'paths': [file.path],
            'temporaryDirectory': staging.path,
          },
        }),
        isTrue,
      );
      expect(await staging.exists(), isFalse);
      expect(
        await File(store.transfer.single.paths.single).readAsString(),
        'attachment',
      );
      final keep = Directory('${store.root.path}/Cache/drop-456')..createSync();
      final next = File('${keep.path}/mail.txt')..writeAsStringSync('mail');
      await store.setting('transferHistory', true);
      expect(
        await store.command({
          'op': 'drop',
          'data': {
            'paths': [next.path],
            'temporaryDirectory': keep.path,
          },
        }),
        isTrue,
      );
      expect(await keep.exists(), isTrue);
      expect(await store.copy(store.history.single), isTrue);
      final before = store.transfer.length;
      expect(
        await store.command({
          'op': 'drop',
          'data': {'error': '读取失败'},
        }),
        isFalse,
      );
      expect(store.transfer.length, before);
    },
  );
}
