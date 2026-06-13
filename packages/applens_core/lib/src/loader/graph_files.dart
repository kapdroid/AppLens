import 'dart:io';

/// File access for the graph loader, so the same loader walks a host directory
/// (the CLI) or bundled assets (on-device runs). Paths are `/`-separated.
abstract interface class GraphFiles {
  bool exists(String path);

  /// Immediate child directory paths of [path].
  List<String> listDirs(String path);

  /// Immediate child file paths of [path].
  List<String> listFiles(String path);

  String read(String path);
}

/// Reads from the real filesystem (the CLI/host default).
class IoGraphFiles implements GraphFiles {
  const IoGraphFiles();

  @override
  bool exists(String path) =>
      Directory(path).existsSync() || File(path).existsSync();

  @override
  List<String> listDirs(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      return const [];
    }
    return [
      for (final e in dir.listSync())
        if (e is Directory) e.path
    ]..sort();
  }

  @override
  List<String> listFiles(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      return const [];
    }
    return [
      for (final e in dir.listSync())
        if (e is File) e.path
    ]..sort();
  }

  @override
  String read(String path) => File(path).readAsStringSync();
}

/// An in-memory file tree (path → content). On-device runs pre-load the bundled
/// `qa_graph` assets into this, so the loader needs no synchronous file I/O.
class MapGraphFiles implements GraphFiles {
  MapGraphFiles(this._files) {
    for (final path in _files.keys) {
      final parts = path.split('/');
      for (var i = 1; i < parts.length; i++) {
        _dirs.add(parts.sublist(0, i).join('/'));
      }
    }
  }

  final Map<String, String> _files;
  final Set<String> _dirs = {};

  String _norm(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  @override
  bool exists(String path) {
    final p = _norm(path);
    return _files.containsKey(p) || _dirs.contains(p);
  }

  @override
  List<String> listDirs(String path) {
    final prefix = '${_norm(path)}/';
    final dirs = <String>{};
    for (final dir in _dirs) {
      if (dir.startsWith(prefix) &&
          !dir.substring(prefix.length).contains('/')) {
        dirs.add(dir);
      }
    }
    return dirs.toList()..sort();
  }

  @override
  List<String> listFiles(String path) {
    final prefix = '${_norm(path)}/';
    return _files.keys
        .where((f) =>
            f.startsWith(prefix) && !f.substring(prefix.length).contains('/'))
        .toList()
      ..sort();
  }

  @override
  String read(String path) {
    final content = _files[_norm(path)];
    if (content == null) {
      throw ArgumentError('no file at "$path"');
    }
    return content;
  }
}
