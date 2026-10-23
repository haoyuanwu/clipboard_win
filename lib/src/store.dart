import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'model.dart';
import 'platform.dart';

class ClipboardStore extends ChangeNotifier {
  ClipboardStore({
    this.mode = 'main',
    Directory? directory,
    this.usePlatform = true,
    this.configureStartup = true,
    this.captureClipboard = true,
  }) : root =
           directory ??
           Directory(
             '${Platform.environment['APPDATA'] ?? Directory.systemTemp.path}/SuperClipboard',
           );
  final String mode;
  final Directory root;
  final bool usePlatform;
  final bool configureStartup;
  final bool captureClipboard;
  List<ClipEntry> history = [], notebook = [], transfer = [];
  Map<String, dynamic> settings = {
    'appearance': 'light',
    'titleBarStyle': 'windows',
    'sort': 'time',
    'limit': 500,
    'startup': true,
    'transferMinutes': 10,
    'transferHistory': false,
    'folderDropMode': 'ask',
    'popoverShortcut': {
      'enabled': true,
      'modifiers': 3,
      'key': 67,
      'label': 'Ctrl + Alt + C',
    },
    'transferShortcut': {
      'enabled': true,
      'modifiers': 3,
      'key': 86,
      'label': 'Ctrl + Alt + V',
    },
  };
  String notebookPath = '', error = '';
  final shortcutConflicts = <String, String>{};
  int shortcutSettingsRevision = 0;
  String shortcutName(String mode) => mode == 'popover' ? '打开快捷历史' : '打开悬浮中转';
  String get shortcutConflictMessage => shortcutConflicts.entries
      .map((e) => '${shortcutName(e.key)}：${e.value} 已被占用')
      .join('；');
  bool busy = false, dropTargeted = false;
  List<Map<String, dynamic>> folderDrops = [];
  bool windowMaximized = false, windowFocused = true;
  int _availabilityRevision = 0;
  bool _disposed = false;
  final availability = <String, ContentAvailability>{};
  ContentAvailability status(ClipEntry e) =>
      availability[e.id] ?? const ContentAvailability();
  Future<void> refreshAvailability() async {
    final revision = ++_availabilityRevision;
    final all = [...history, ...notebook, ...transfer];
    final checked = await Future.wait(all.map(ContentAvailability.check));
    if (_disposed || revision != _availabilityRevision) return;
    availability.clear();
    for (var i = 0; i < all.length; i++) {
      availability[all[i].id] = checked[i];
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>?> dragPayload(ClipEntry e, {String? path}) async {
    final state = await ContentAvailability.check(e);
    if (state.isMissing || (path != null && !state.validPaths.contains(path))) {
      return null;
    }
    final payload = e.toJson();
    if (e.paths.isNotEmpty) {
      payload['paths'] = path == null ? state.validPaths : [path];
    }
    return payload;
  }

  bool get windowsStyle => settings['titleBarStyle'] != 'mac';
  void setWindowMaximized(bool value) {
    if (windowMaximized == value) return;
    windowMaximized = value;
    notifyListeners();
  }

  int sessionRevision = 0;
  Timer? _cleanupTimer, _availabilityTimer;
  DateTime? _transferDeadline;
  Future<void> _tail = Future.value();
  int _serial = 0;
  String _lastCaptureFingerprint = '';
  DateTime? _lastCaptureAt;
  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_serial++}';
  List<ClipEntry> library(String name) => switch (name) {
    'notebook' => notebook,
    'transfer' => transfer,
    _ => history,
  };
  Map<String, dynamic> get snapshot => {
    'history': history.map((e) => e.toJson()).toList(),
    'notebook': notebook.map((e) => e.toJson()).toList(),
    'transfer': transfer.map((e) => e.toJson()).toList(),
    'settings': settings,
    'notebookPath': notebookPath,
    'busy': busy,
    'error': error,
    'shortcutConflicts': shortcutConflicts,
    'deadline': _transferDeadline?.toIso8601String(),
    'folderDrops': folderDrops,
  };
  void _readSnapshot(Map<String, dynamic> j) {
    history = _decode(j['history']);
    notebook = _decode(j['notebook']);
    transfer = _decode(j['transfer']);
    settings = {...settings, ...Map<String, dynamic>.from(j['settings'] ?? {})};
    notebookPath = j['notebookPath'] ?? notebookPath;
    busy = j['busy'] ?? false;
    error = j['error'] ?? '';
    shortcutConflicts
      ..clear()
      ..addAll(Map<String, String>.from(j['shortcutConflicts'] ?? {}));
    _transferDeadline = DateTime.tryParse(j['deadline'] ?? '');
    folderDrops = (j['folderDrops'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<ClipEntry> _decode(dynamic data) => (data as List? ?? [])
      .map((j) => ClipEntry.fromJson(Map<String, dynamic>.from(j)))
      .toList();
  Future<void> initialize() async {
    notebookPath = '${root.path}/Notebook';
    _availabilityTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(refreshAvailability()),
    );
    if (usePlatform) {
      WindowsBridge.channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'shortcutSettings':
            shortcutSettingsRevision++;
            notifyListeners();
          case 'windowFocus':
            windowFocused = call.arguments == true;
            notifyListeners();
          case 'windowState':
            setWindowMaximized(call.arguments == true);
          case 'state':
            _readSnapshot(Map<String, dynamic>.from(call.arguments));
            unawaited(refreshAvailability());
            notifyListeners();
          case 'action':
            return command(Map<String, dynamic>.from(call.arguments));
          case 'clipboardChanged':
            unawaited(command({'op': 'capture'}));
          case 'shown':
            unawaited(refreshAvailability());
            sessionRevision++;
            dropTargeted = false;
            notifyListeners();
          case 'transferVisibility':
            unawaited(
              command({'op': 'transferVisibility', 'visible': call.arguments}),
            );
          case 'drop':
            unawaited(() async {
              // Reveal the destination before archiving (which may take time).
              // A queued folder decision arrives through the shared snapshot.
              await WindowsBridge.call('show', 'transfer');
              await command({'op': 'drop', 'data': call.arguments});
              dropTargeted = false;
            }());
          case 'dropHover':
            dropTargeted = call.arguments == true;
            notifyListeners();
        }
        return null;
      });
    }
    if (mode != 'main') {
      final state = await WindowsBridge.connect();
      if (state != null) _readSnapshot(Map<String, dynamic>.from(state));
      await refreshAvailability();
      return;
    }
    await root.create(recursive: true);
    final file = File('${root.path}/state.json');
    if (await file.exists()) {
      try {
        _readSnapshot(
          Map<String, dynamic>.from(jsonDecode(await file.readAsString())),
        );
      } catch (_) {
        final backup = File('${file.path}.bak');
        if (await backup.exists()) {
          _readSnapshot(
            Map<String, dynamic>.from(jsonDecode(await backup.readAsString())),
          );
          error = '已从备份恢复数据。';
        } else {
          await file.copy('${file.path}.damaged-${_id()}');
          error = '存档无法读取，原文件已保留，请检查数据目录。';
        }
      }
    }
    // The notebook index is independent from history, and travels with its assets.
    final index = File('$notebookPath/notebook.json');
    if (await index.exists()) {
      try {
        notebook = _decode(jsonDecode(await index.readAsString()));
      } catch (_) {
        error = '记事本索引无法读取，已保留原存档。';
      }
    }
    busy = false;
    await Directory(notebookPath).create(recursive: true);
    await Directory('${root.path}/History').create(recursive: true);
    await Directory('${root.path}/Transfer').create(recursive: true);
    await Directory('${root.path}/Cache').create(recursive: true);
    if (_transferDeadline != null) {
      if (_transferDeadline!.isBefore(DateTime.now())) {
        await _clearTransfer();
      } else {
        _scheduleCleanup();
      }
    }
    if (usePlatform) {
      try {
        if (configureStartup) {
          settings['startup'] =
              await WindowsBridge.call<bool>('startup', {
                'enabled': settings.containsKey('startupConfigured')
                    ? null
                    : settings['startup'],
                'initialize': true,
              }) ??
              false;
          settings['startupConfigured'] = true;
        }
      } catch (e) {
        error = '开机启动设置失败：$e';
      }
      shortcutConflicts.clear();
      if (error == '部分全局快捷键已被占用，请在设置中重新录制。') error = '';
      for (final mode in ['popover', 'transfer']) {
        final value = settings['${mode}Shortcut'] as Map;
        final ok = await WindowsBridge.call<bool>('setShortcut', {
          'mode': mode,
          'shortcut': value,
        });
        if (ok != true) shortcutConflicts[mode] = value['label'] as String;
      }
      await WindowsBridge.call('broadcast', snapshot);
      await WindowsBridge.call('listen', {
        'cache': '${root.path}/Cache',
        'enabled': captureClipboard,
      });
      await _persist();
    }
    await refreshAvailability();
  }

  Future<bool> command(Map<String, dynamic> action) async {
    if (mode != 'main') {
      return await WindowsBridge.call<bool>('action', action) ?? false;
    }
    final result = Completer<bool>();
    _tail = _tail.then((_) async {
      try {
        final ok = await _perform(action);
        if (action['op'] != 'cleanInvalid') await _persist();
        await refreshAvailability();
        result.complete(ok);
      } catch (e) {
        error = '操作失败：${e is FileSystemException ? e.message : e}';
        busy = false;
        result.complete(false);
      } finally {
        notifyListeners();
        if (usePlatform) {
          try {
            await WindowsBridge.call('broadcast', snapshot);
          } catch (_) {
            /* A closing secondary engine must not break the write queue. */
          }
        }
      }
    });
    return result.future;
  }

  Future<bool> _perform(Map<String, dynamic> a) async {
    final op = a['op'];
    final lib = a['library'] ?? 'history';
    final items = library(lib);
    final entry = items.where((e) => e.id == a['id']).firstOrNull;
    switch (op) {
      case 'capture':
        final data = await WindowsBridge.call<Map>('readClipboard');
        if (data != null) await _capture(Map<String, dynamic>.from(data));
      case 'drop':
        final data = Map<String, dynamic>.from(a['data']);
        final choice = a['folderChoice'] ?? settings['folderDropMode'];
        final identity = data['fingerprint'];
        final savedDrag =
            identity is String &&
            identity.isNotEmpty &&
            [...transfer, ...notebook].any((e) => e.fingerprint == identity);
        if (choice == 'ask' && !savedDrag) {
          final folders = <String>[];
          for (final path in List<String>.from(data['paths'] ?? [])) {
            if (await FileSystemEntity.type(path, followLinks: false) ==
                FileSystemEntityType.directory) {
              folders.add(path);
            }
          }
          if (folders.isNotEmpty) {
            folderDrops.add({'id': _id(), 'data': data, 'folders': folders});
            break;
          }
        }
        final staged = data['temporaryDirectory'] as String? ?? '';
        var keepStaging = false;
        try {
          if (choice == 'cancel') break;
          if (choice == 'group' && !savedDrag) {
            final expanded = <String>[];
            var grouped = false;
            for (final path in List<String>.from(data['paths'] ?? [])) {
              if (await FileSystemEntity.type(path, followLinks: false) ==
                  FileSystemEntityType.directory) {
                final children = await Directory(path)
                    .list(followLinks: false)
                    .toList();
                children.sort((a, b) => a.path.compareTo(b.path));
                if (children.isNotEmpty) {
                  expanded.addAll(children.map((e) => e.path));
                  grouped = true;
                  continue;
                }
              }
              expanded.add(path); // Empty folders remain intact.
            }
            data['paths'] = expanded.toSet().toList();
            data['fileGroup'] = grouped;
          }
          final e = await _makeEntry(data);
          if (e == null ||
              transfer.any((x) => x.fingerprint == e.fingerprint)) {
            break;
          }
          await _archive(e, 'transfer');
          if (settings['transferHistory'] == true) {
            await _record(e);
            keepStaging = true;
          }
        } finally {
          // Native virtual files are staged under this application's cache only.
          final normalized = Directory(staged).absolute.path
              .replaceAll('\\', '/')
              .toLowerCase();
          final cache = Directory('${root.path}/Cache').absolute.path
              .replaceAll('\\', '/')
              .toLowerCase();
          if (!keepStaging &&
              staged.isNotEmpty &&
              normalized.startsWith('$cache/drop-') &&
              !normalized.substring(cache.length + 1).contains('/')) {
            final directory = Directory(staged);
            if (await directory.exists()) {
              await directory.delete(recursive: true);
            }
          }
        }
      case 'resolveFolderDrop':
        final pending = folderDrops
            .where((e) => e['id'] == a['id'])
            .firstOrNull;
        if (pending == null) return false;
        final choice = a['choice'];
        if (!['group', 'folder', 'cancel'].contains(choice)) return false;
        folderDrops.remove(pending);
        if (a['remember'] == true && choice != 'cancel') {
          settings['folderDropMode'] = choice;
        }
        return _perform({
          'op': 'drop',
          'data': pending['data'],
          'folderChoice': choice,
        });
      case 'copy':
        // Clipboard writes are handled by the owner engine to avoid recording ourselves.
        if (entry == null) return false;
        final payload = await dragPayload(entry, path: a['path'] as String?);
        if (payload == null) throw const FileSystemException('内容已移动、删除或无法访问。');
        final success =
            !usePlatform ||
            await WindowsBridge.call<bool>('writeClipboard', payload) == true;
        if (!success) throw const FileSystemException('剪贴板正被其他应用占用，请重试。');
        entry.count++;
        entry.lastCopiedAt = DateTime.now();
      case 'refreshAvailability':
        await refreshAvailability();
      case 'cleanInvalid':
        if (lib == 'notebook') return false;
        final ids = (a['ids'] as List?)?.cast<String>().toSet();
        final old = [...items];
        final removed = <ClipEntry>[];
        for (final e in old) {
          if (!e.pinned &&
              (ids == null || ids.contains(e.id)) &&
              (await ContentAvailability.check(e)).isMissing) {
            removed.add(e);
          }
        }
        items.removeWhere(removed.contains);
        try {
          await _persist();
        } catch (_) {
          items
            ..clear()
            ..addAll(old);
          rethrow;
        }
        for (final e in removed) {
          try {
            await _deleteAssets(e);
          } on FileSystemException {
            /* Index is committed; orphan can be removed later. */
          }
        }
      case 'pin':
        if (entry != null) entry.pinned = !entry.pinned;
      case 'delete':
        if (entry != null) {
          items.remove(entry);
          await _deleteAssets(entry);
        }
      case 'archive':
        if (entry != null) await _archive(entry, a['target']);
      case 'clear':
        if (lib == 'transfer') {
          await _clearTransfer();
        } else {
          final removed = items.where((e) => !e.pinned).toList();
          items.removeWhere((e) => !e.pinned);
          for (final e in removed) {
            await _deleteAssets(e);
          }
        }
      case 'settings':
        final key = a['key'] as String;
        dynamic value = a['value'];
        if (key == 'transferMinutes') {
          value = (value as num).toInt().clamp(1, 1440);
        }
        if (key == 'startup' && usePlatform) {
          value = await WindowsBridge.call<bool>('startup', {
            'enabled': value,
            'initialize': false,
          });
        }
        if (key.endsWith('Shortcut') && usePlatform) {
          final mode = key == 'popoverShortcut' ? 'popover' : 'transfer';
          final ok = await WindowsBridge.call<bool>('setShortcut', {
            'mode': mode,
            'shortcut': value,
          });
          if (ok != true) {
            shortcutConflicts[mode] = value['label'] as String;
            return false;
          }
          shortcutConflicts.remove(mode);
        }
        settings[key] = value;
        if (key == 'limit') await _trim();
      case 'transferVisibility':
        _cleanupTimer?.cancel();
        _transferDeadline = a['visible'] == true
            ? null
            : DateTime.now().add(
                Duration(minutes: settings['transferMinutes']),
              );
        _scheduleCleanup();
      case 'migrate':
        await _migrate(a['path']);
      case 'dismissError':
        error = '';
      case 'ingest':
        await _capture(Map<String, dynamic>.from(a['data']));
    }
    return true;
  }

  Future<void> _capture(Map<String, dynamic> data) async {
    final e = await _makeEntry(data);
    if (e == null) return;
    final now = DateTime.now();
    if (usePlatform &&
        e.fingerprint == _lastCaptureFingerprint &&
        _lastCaptureAt != null &&
        now.difference(_lastCaptureAt!).inMilliseconds < 120) {
      return;
    }
    _lastCaptureFingerprint = e.fingerprint;
    _lastCaptureAt = now;
    await _record(e);
  }

  Future<ClipEntry?> _makeEntry(Map<String, dynamic> d) async {
    if (d['error'] is String) throw FileSystemException(d['error']);
    final dragIdentity = d['fingerprint'];
    if (dragIdentity is String && dragIdentity.isNotEmpty) {
      final existing = [
        ...transfer,
        ...notebook,
      ].where((e) => e.fingerprint == dragIdentity).firstOrNull;
      if (existing != null) return existing;
    }
    final paths = List<String>.from(d['paths'] ?? []);
    final text = d['text'] as String? ?? '';
    final imagePath = d['imagePath'] as String? ?? '';
    if (paths.isEmpty && text.trim().isEmpty && imagePath.isEmpty) return null;
    final kind = paths.isNotEmpty
        ? (paths.length == 1 &&
                  d['fileGroup'] != true &&
                  RegExp(
                    r'\.(mp4|mov|mkv|avi|wmv|webm|m4v)$',
                    caseSensitive: false,
                  ).hasMatch(paths.first)
              ? EntryKind.video
              : EntryKind.file)
        : imagePath.isNotEmpty
        ? EntryKind.image
        : EntryKind.text;
    String key;
    if (paths.isNotEmpty) {
      final normalized =
          paths.map((p) => p.replaceAll('/', '\\').toLowerCase()).toList()
            ..sort();
      key =
          '${d['fileGroup'] == true ? 'group' : 'files'}:${normalized.join('\n')}';
      // Dragging a saved copy back uses its original fingerprint.
      for (final e in [...transfer, ...notebook]) {
        if (listEquals(e.paths, paths)) return e;
      }
    } else if (imagePath.isNotEmpty) {
      key = 'image:${await sha256.bind(File(imagePath).openRead()).first}';
    } else {
      key = 'text:$text';
    }
    final now = DateTime.now();
    var preview = d['previewPath'] as String? ?? '';
    if (kind == EntryKind.video && usePlatform) {
      preview =
          await WindowsBridge.call<String>('thumbnail', {
            'path': paths.first,
          }) ??
          '';
    }
    return ClipEntry(
      id: _id(),
      fingerprint: sha256.convert(utf8.encode(key)).toString(),
      kind: kind,
      createdAt: now,
      lastCopiedAt: now,
      text: text,
      title: paths.isNotEmpty
          ? paths.map((p) => p.replaceAll('\\', '/').split('/').last).join('、')
          : kind == EntryKind.image
          ? '图片 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'
          : '',
      paths: paths,
      imagePath: imagePath,
      html: d['html'] ?? '',
      rtf: d['rtf'] ?? '',
      source: d['source'] ?? '拖入内容',
      sourceIcon: d['sourceIcon'] ?? '',
      tint: d['tint'] ?? 0xff454d61,
      previewPath: preview,
      fileGroup: d['fileGroup'] == true,
    );
  }

  Future<void> _record(ClipEntry e) async {
    final existing = history
        .where((x) => x.fingerprint == e.fingerprint)
        .firstOrNull;
    if (existing != null) {
      existing.count++;
      existing.lastCopiedAt = DateTime.now();
    } else {
      var saved = e;
      if (e.imagePath.isNotEmpty) {
        final dir = Directory('${root.path}/History/${e.id}');
        await dir.create(recursive: true);
        final copy = await File(e.imagePath).copy('${dir.path}/image.png');
        saved = e.copyWith(imagePath: copy.path);
      }
      history.insert(0, saved);
    }
    await _trim();
  }

  Future<void> _trim() async {
    final unpinned = history.where((e) => !e.pinned).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final e in unpinned.skip(settings['limit'] as int)) {
      history.remove(e);
      await _deleteAssets(e);
    }
  }

  Future<void> _archive(ClipEntry entry, String target) async {
    final items = library(target);
    if (items.any((e) => e.fingerprint == entry.fingerprint)) return;
    busy = true;
    notifyListeners();
    if (usePlatform) await WindowsBridge.call('broadcast', snapshot);
    final id = _id();
    final dir = Directory(
      '${target == 'notebook' ? notebookPath : '${root.path}/Transfer'}/$id',
    );
    await dir.create(recursive: true);
    try {
      final status = await ContentAvailability.check(entry);
      if (status.isMissing) throw const FileSystemException('原内容暂时不可用，无法保存副本。');
      final sourcePaths = entry.paths.isEmpty ? <String>[] : status.validPaths;
      final savedPaths = <String>[];
      for (var i = 0; i < sourcePaths.length; i++) {
        final path = sourcePaths[i];
        final name = path.replaceAll('\\', '/').split('/').last;
        final destination = '${dir.path}/files/$i/$name';
        await _copyEntity(path, destination);
        savedPaths.add(destination);
      }
      var image = '', preview = '';
      if (entry.imagePath.isNotEmpty) {
        image = (await File(entry.imagePath).copy('${dir.path}/image.png'))
            .path;
      }
      if (entry.previewPath.isNotEmpty &&
          await File(entry.previewPath).exists()) {
        preview = (await File(
          entry.previewPath,
        ).copy('${dir.path}/preview.png')).path;
      }
      items.insert(
        0,
        entry.copyWith(
          id: id,
          library: target,
          paths: savedPaths,
          imagePath: image,
          previewPath: preview,
        ),
      );
    } catch (_) {
      await dir.delete(recursive: true);
      rethrow;
    } finally {
      busy = false;
    }
  }

  Future<void> _copyEntity(String source, String destination) async {
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.file) {
      await File(destination).parent.create(recursive: true);
      await File(source).copy(destination);
    } else if (type == FileSystemEntityType.directory) {
      await Directory(destination).create(recursive: true);
      await for (final child in Directory(source).list(followLinks: false)) {
        await _copyEntity(
          child.path,
          '$destination/${child.path.replaceAll('\\', '/').split('/').last}',
        );
      }
    } else {
      throw FileSystemException('无法保存文件，文件不存在或是链接。', source);
    }
  }

  Future<void> _deleteAssets(ClipEntry e) async {
    final base = e.library == 'notebook'
        ? notebookPath
        : '${root.path}/${e.library == 'transfer' ? 'Transfer' : 'History'}';
    // Only delete an application-owned entry directory, never its source paths.
    if (!RegExp(r'^\d+-\d+$').hasMatch(e.id)) return;
    final dir = Directory('$base/${e.id}');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> _clearTransfer() async {
    for (final e in transfer) {
      await _deleteAssets(e);
    }
    transfer.clear();
    _transferDeadline = null;
    _cleanupTimer?.cancel();
  }

  void _scheduleCleanup() {
    _cleanupTimer?.cancel();
    if (_transferDeadline == null) return;
    final duration = _transferDeadline!.difference(DateTime.now());
    _cleanupTimer = Timer(
      duration.isNegative ? Duration.zero : duration,
      () => unawaited(command({'op': 'clear', 'library': 'transfer'})),
    );
  }

  Future<void> _migrate(String parent) async {
    final destination = Directory('$parent/SuperClipboard Notebook');
    if (await destination.exists()) {
      throw const FileSystemException(
        '目标已有 SuperClipboard Notebook 文件夹，请选择其他位置。',
      );
    }
    final oldPath = notebookPath;
    final oldNotebook = notebook;
    final source = Directory(oldPath).absolute.path
        .replaceAll('\\', '/')
        .toLowerCase();
    final target = destination.absolute.path
        .replaceAll('\\', '/')
        .toLowerCase();
    if (target.startsWith('$source/') || target == source) {
      throw const FileSystemException('请选择记事本目录之外的位置。');
    }
    busy = true;
    notifyListeners();
    if (usePlatform) await WindowsBridge.call('broadcast', snapshot);
    try {
      await _copyEntity(oldPath, destination.path);
      String relocated(String p) =>
          p.isEmpty ? '' : p.replaceFirst(oldPath, destination.path);
      final moved = notebook
          .map(
            (e) => e.copyWith(
              id: e.id,
              library: 'notebook',
              paths: e.paths.map(relocated).toList(),
              imagePath: relocated(e.imagePath),
              previewPath: relocated(e.previewPath),
            )..pinned = e.pinned,
          )
          .toList();
      await _atomicWrite(
        File('${destination.path}/notebook.json'),
        jsonEncode(moved.map((e) => e.toJson()).toList()),
      );
      notebook = moved;
      notebookPath = destination.path;
      // Commit the new location before removing the previous application-owned archive.
      await _persist();
    } catch (_) {
      notebookPath = oldPath;
      notebook = oldNotebook;
      if (await destination.exists()) {
        await destination.delete(recursive: true);
      }
      rethrow;
    } finally {
      busy = false;
    }
    // Keep the old archive as a migration backup; it is no longer read or changed.
  }

  Future<void> _atomicWrite(File file, String content) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(content, flush: true);
    if (await file.exists()) await file.copy('${file.path}.bak');
    await temp.rename(file.path);
  }

  Future<void> _persist() async {
    await _atomicWrite(
      File('$notebookPath/notebook.json'),
      jsonEncode(notebook.map((e) => e.toJson()).toList()),
    );
    final state = {...snapshot}..remove('folderDrops');
    await _atomicWrite(File('${root.path}/state.json'), jsonEncode(state));
  }

  Future<bool> copy(ClipEntry e) =>
      command({'op': 'copy', 'id': e.id, 'library': e.library});
  Future<bool> setting(String key, dynamic value) =>
      command({'op': 'settings', 'key': key, 'value': value});
  @override
  void dispose() {
    _disposed = true;
    _availabilityTimer?.cancel();
    _cleanupTimer?.cancel();
    super.dispose();
  }
}
