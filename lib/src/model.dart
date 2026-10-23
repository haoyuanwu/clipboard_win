import 'dart:io';

import 'package:flutter/cupertino.dart';

enum EntryKind {
  text('文字', CupertinoIcons.text_alignleft),
  image('图片', CupertinoIcons.photo),
  file('文件', CupertinoIcons.doc),
  video('视频', CupertinoIcons.play_rectangle);

  const EntryKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

class ClipEntry {
  ClipEntry({
    required this.id,
    required this.fingerprint,
    required this.kind,
    required this.createdAt,
    required this.lastCopiedAt,
    this.text = '',
    this.title = '',
    this.paths = const [],
    this.imagePath = '',
    this.html = '',
    this.rtf = '',
    this.source = '未知应用',
    this.sourceIcon = '',
    this.tint = 0xff454d61,
    this.count = 1,
    this.pinned = false,
    this.library = 'history',
    this.originalPaths = const [],
    this.previewPath = '',
  });
  final String id, fingerprint, text, title, imagePath, html, rtf;
  final String source, sourceIcon, library, previewPath;
  final EntryKind kind;
  final List<String> paths, originalPaths;
  final DateTime createdAt;
  DateTime lastCopiedAt;
  int count, tint;
  bool pinned;
  String get searchText => '$text $title ${paths.join(' ')} $source';
  ClipEntry copyWith({
    String? id,
    String? library,
    List<String>? paths,
    String? imagePath,
    String? previewPath,
  }) => ClipEntry(
    id: id ?? this.id,
    fingerprint: fingerprint,
    kind: kind,
    createdAt: createdAt,
    lastCopiedAt: lastCopiedAt,
    text: text,
    title: title,
    paths: paths ?? this.paths,
    originalPaths: originalPaths.isEmpty ? this.paths : originalPaths,
    imagePath: imagePath ?? this.imagePath,
    previewPath: previewPath ?? this.previewPath,
    html: html,
    rtf: rtf,
    source: source,
    sourceIcon: sourceIcon,
    tint: tint,
    count: count,
    pinned: false,
    library: library ?? this.library,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'fingerprint': fingerprint,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'lastCopiedAt': lastCopiedAt.toIso8601String(),
    'text': text,
    'title': title,
    'paths': paths,
    'originalPaths': originalPaths,
    'imagePath': imagePath,
    'html': html,
    'rtf': rtf,
    'source': source,
    'sourceIcon': sourceIcon,
    'tint': tint,
    'count': count,
    'pinned': pinned,
    'library': library,
    'previewPath': previewPath,
  };
  factory ClipEntry.fromJson(Map<String, dynamic> j) => ClipEntry(
    id: j['id'] as String,
    fingerprint: j['fingerprint'] as String,
    kind: EntryKind.values.byName(j['kind'] as String),
    createdAt: DateTime.parse(j['createdAt']),
    lastCopiedAt: DateTime.parse(j['lastCopiedAt']),
    text: j['text'] ?? '',
    title: j['title'] ?? '',
    paths: List<String>.from(j['paths'] ?? []),
    originalPaths: List<String>.from(j['originalPaths'] ?? []),
    imagePath: j['imagePath'] ?? '',
    html: j['html'] ?? '',
    rtf: j['rtf'] ?? '',
    source: j['source'] ?? '未知应用',
    sourceIcon: j['sourceIcon'] ?? '',
    tint: j['tint'] ?? 0xff454d61,
    count: j['count'] ?? 1,
    pinned: j['pinned'] ?? false,
    library: j['library'] ?? 'history',
    previewPath: j['previewPath'] ?? '',
  );
}

/// Snapshot ordering is refreshed only when opening a window or changing sort.
class ListSession {
  final List<String> _ids = [];
  void begin(List<ClipEntry> entries, String sort) {
    final sorted = [...entries]
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        if (sort == 'count' && a.count != b.count) {
          return b.count.compareTo(a.count);
        }
        return b.createdAt.compareTo(a.createdAt);
      });
    _ids
      ..clear()
      ..addAll(sorted.map((e) => e.id));
  }

  List<ClipEntry> entries(List<ClipEntry> entries) {
    final byId = {for (final e in entries) e.id: e};
    _ids.removeWhere((id) => !byId.containsKey(id));
    final known = _ids.toSet();
    _ids.addAll(entries.where((e) => !known.contains(e.id)).map((e) => e.id));
    return _ids.map((id) => byId[id]!).toList();
  }
}

String timestamp(DateTime time, [DateTime? now]) {
  now ??= DateTime.now();
  final age = now.difference(time);
  String two(int n) => n.toString().padLeft(2, '0');
  final clock = '${two(time.hour)}:${two(time.minute)}';
  if (age.inMinutes < 1) return '刚才';
  if (age.inHours < 1) return '${age.inMinutes} 分钟前';
  if (age.inHours < 24) {
    return '${age.inHours} 小时${age.inMinutes % 60 == 0 ? '' : ' ${age.inMinutes % 60} 分钟'}前';
  }
  if (age.inHours < 48) return '昨天 $clock';
  return '${time.year}-${two(time.month)}-${two(time.day)} $clock';
}

/// Rechecked before copy, drag and cleanup; cached only for presentation.
class ContentAvailability {
  const ContentAvailability({
    this.total = 0,
    this.validPaths = const [],
    this.missing = 0,
  });
  final int total, missing;
  final List<String> validPaths;
  bool get isMissing => total > 0 && total == missing;
  bool get isPartial => missing > 0 && !isMissing;
  static Future<ContentAvailability> check(ClipEntry e) async {
    final paths = e.paths.isNotEmpty
        ? e.paths
        : e.kind == EntryKind.image
        ? [e.imagePath]
        : <String>[];
    final valid = <String>[];
    for (final path in paths) {
      try {
        final type = await FileSystemEntity.type(path);
        if (type == FileSystemEntityType.directory) {
          await Directory(path).list().take(1).drain<void>();
          valid.add(path);
        } else if (type == FileSystemEntityType.file) {
          final file = await File(path).open();
          await file.close();
          valid.add(path);
        }
      } on FileSystemException {
        /* Missing or inaccessible. */
      }
    }
    return ContentAvailability(
      total: paths.length,
      validPaths: valid,
      missing: paths.length - valid.length,
    );
  }
}
