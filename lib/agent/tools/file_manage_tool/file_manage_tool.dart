import 'dart:io';

import 'package:path/path.dart' as p;

import '../../tool.dart';
import '../../message.dart';
import '../../tool_context.dart';
import '../utils/file_utils.dart';

/// Callback: opens a file picker and returns the picked file path (or null).
/// [fileTypes] is an optional list of allowed extensions (e.g. ['pdf', 'csv']).
typedef ImportHandler = Future<String?> Function(List<String>? fileTypes);

/// Callback: exports a file to user-accessible storage (Downloads, share sheet, etc.).
/// [sourcePath] is the absolute path to the file to export.
/// Returns the destination path or a description of what happened.
typedef ExportHandler = Future<String> Function(String sourcePath);

/// File management tool: copy, move, rename, mkdir, delete, import, export.
/// Mobile-friendly alternative to Bash file operations.
class FileManageTool extends Tool {
  ImportHandler? importHandler;
  ExportHandler? exportHandler;

  @override
  String get name => 'FileManage';

  @override
  String get description =>
      'Copy, move, create directory, delete, import, or export files.';

  @override
  String get prompt =>
      'Manage files and directories without Bash. Works on all platforms including mobile.\n'
      'Actions:\n'
      '- copy: Copy a file or directory to a new location\n'
      '- move: Move/rename a file or directory\n'
      '- mkdir: Create a directory (recursive)\n'
      '- delete: Delete a file or empty directory\n'
      '- import: Open file picker to import a file from device storage into the agent workspace\n'
      '- export: Export a file from workspace to the device Downloads directory\n'
      'Parameters:\n'
      '- action (required): "copy", "move", "mkdir", "delete", "import", or "export"\n'
      '- path (required for copy/move/mkdir/delete/export): Source path (or target path for mkdir)\n'
      '- destination: Destination path (required for copy/move, optional for import)\n'
      '- file_types: Allowed file extensions for import (e.g. ["pdf", "csv"])\n'
      '\n'
      'After moving or renaming files that are referenced in INDEX.md or MEMORY.md, '
      'update those index files to reflect the new paths.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['copy', 'move', 'mkdir', 'delete', 'import', 'export'],
        'description': 'The operation to perform',
      },
      'path': {
        'type': 'string',
        'description': 'Source file/directory path (or target for mkdir)',
      },
      'destination': {
        'type': 'string',
        'description': 'Destination path (for copy/move, optional for import)',
      },
      'file_types': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'Allowed file extensions for import (e.g. ["pdf", "csv"])',
      },
    },
    'required': ['action'],
  };

  @override
  bool get isReadOnly => false;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = input['action'] as String? ?? '';
    final path = input['path'] as String? ?? '';
    final destination = input['destination'] as String?;

    if (action != 'import' && path.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'path is required for $action',
        isError: true,
      );
    }

    try {
      switch (action) {
        case 'copy':
          return _copy(toolUseId, path, destination, context);
        case 'move':
          return _move(toolUseId, path, destination, context);
        case 'mkdir':
          final resolved = normalizePath(path, context.basePath);
          Directory(resolved).createSync(recursive: true);
          return ToolResult(
            toolUseId: toolUseId,
            content: 'Created directory: $path',
          );
        case 'delete':
          return _delete(toolUseId, path, context);
        case 'import':
          return _import(toolUseId, input, context);
        case 'export':
          return _export(toolUseId, path, context);
        default:
          return ToolResult(
            toolUseId: toolUseId,
            content: 'unknown action: $action',
            isError: true,
          );
      }
    } catch (e) {
      return ToolResult(toolUseId: toolUseId, content: '$e', isError: true);
    }
  }

  ToolResult _copy(
    String toolUseId,
    String path,
    String? destination,
    ToolContext context,
  ) {
    if (destination == null || destination.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'destination is required for copy',
        isError: true,
      );
    }
    final resolved = normalizePath(path, context.basePath);
    final resolvedDest = normalizePath(destination, context.basePath);
    final entity = FileSystemEntity.typeSync(resolved);
    if (entity == FileSystemEntityType.file) {
      File(resolvedDest).parent.createSync(recursive: true);
      File(resolved).copySync(resolvedDest);
    } else if (entity == FileSystemEntityType.directory) {
      _copyDirectory(Directory(resolved), Directory(resolvedDest));
    } else {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'not found: $path',
        isError: true,
      );
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: 'Copied $path → $destination (${_sizeDesc(resolvedDest)})',
    );
  }

  ToolResult _move(
    String toolUseId,
    String path,
    String? destination,
    ToolContext context,
  ) {
    if (destination == null || destination.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'destination is required for move',
        isError: true,
      );
    }
    final resolved = normalizePath(path, context.basePath);
    final resolvedDest = normalizePath(destination, context.basePath);
    final entity = FileSystemEntity.typeSync(resolved);
    if (entity == FileSystemEntityType.file) {
      File(resolvedDest).parent.createSync(recursive: true);
      File(resolved).renameSync(resolvedDest);
    } else if (entity == FileSystemEntityType.directory) {
      Directory(resolvedDest).parent.createSync(recursive: true);
      Directory(resolved).renameSync(resolvedDest);
    } else {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'not found: $path',
        isError: true,
      );
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: 'Moved $path → $destination (${_sizeDesc(resolvedDest)})',
    );
  }

  ToolResult _delete(String toolUseId, String path, ToolContext context) {
    final resolved = normalizePath(path, context.basePath);
    final entity = FileSystemEntity.typeSync(resolved);
    if (entity == FileSystemEntityType.file) {
      File(resolved).deleteSync();
    } else if (entity == FileSystemEntityType.directory) {
      Directory(resolved).deleteSync(recursive: true);
    } else {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'not found: $path',
        isError: true,
      );
    }
    return ToolResult(toolUseId: toolUseId, content: 'Deleted: $path');
  }

  Future<ToolResult> _import(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    if (importHandler == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'import not available (no handler registered)',
        isError: true,
      );
    }
    final fileTypes = (input['file_types'] as List<dynamic>?)?.cast<String>();
    final pickedPath = await importHandler!(fileTypes);
    if (pickedPath == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Import cancelled by user',
      );
    }

    final destination = input['destination'] as String?;
    final fileName = p.basename(pickedPath);
    final destDir = destination != null && destination.isNotEmpty
        ? normalizePath(destination, context.basePath)
        : '${context.basePath}/memory/imports';
    Directory(destDir).createSync(recursive: true);
    final destPath = '$destDir/$fileName';
    File(pickedPath).copySync(destPath);

    final sizeKb = (File(pickedPath).lengthSync() / 1024).toStringAsFixed(1);
    return ToolResult(
      toolUseId: toolUseId,
      content: 'Imported $fileName → $destPath (${sizeKb}KB)',
    );
  }

  Future<ToolResult> _export(
    String toolUseId,
    String path,
    ToolContext context,
  ) async {
    if (exportHandler == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'export not available (no handler registered)',
        isError: true,
      );
    }
    final resolved = normalizePath(path, context.basePath);
    if (!File(resolved).existsSync()) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'file not found: $path',
        isError: true,
      );
    }
    final result = await exportHandler!(resolved);
    return ToolResult(toolUseId: toolUseId, content: result);
  }

  void _copyDirectory(Directory source, Directory dest) {
    dest.createSync(recursive: true);
    for (final entity in source.listSync()) {
      final name = p.basename(entity.path);
      if (entity is File) {
        entity.copySync('${dest.path}/$name');
      } else if (entity is Directory) {
        _copyDirectory(entity, Directory('${dest.path}/$name'));
      }
    }
  }

  String _sizeDesc(String path) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.file) {
      return '${(File(path).lengthSync() / 1024).toStringAsFixed(1)}KB';
    } else if (type == FileSystemEntityType.directory) {
      return 'directory';
    }
    return '';
  }
}
