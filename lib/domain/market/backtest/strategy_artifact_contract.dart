import 'dart:io';

import '../../../agent/tool_context.dart';

class StrategyArtifactPaths {
  final String strategyDir;
  final String itemDir;
  final String libraryPath;
  final String legacyLibraryPath;

  const StrategyArtifactPaths({
    required this.strategyDir,
    required this.itemDir,
    required this.libraryPath,
    required this.legacyLibraryPath,
  });

  Map<String, String> toJson() => {
    'strategyDir': strategyDir,
    'itemDir': itemDir,
    'libraryPath': libraryPath,
    'legacyLibraryPath': legacyLibraryPath,
  };
}

const strategyArtifactContract = 'strategy-library-v1';
const strategyArtifactDir = 'strategies';
const strategyItemDir = 'items';
const strategyLibraryFile = 'custom-strategies.json';

StrategyArtifactPaths strategyArtifactPaths(String basePath) {
  final sep = Platform.pathSeparator;
  final strategyDirPath = '$basePath$sep$strategyArtifactDir';
  return StrategyArtifactPaths(
    strategyDir: strategyDirPath,
    itemDir: '$strategyDirPath$sep$strategyItemDir',
    libraryPath: '$strategyDirPath$sep$strategyLibraryFile',
    legacyLibraryPath: '$basePath${sep}data$sep$strategyLibraryFile',
  );
}

String strategyItemPath(String basePath, String strategyId) {
  final safeId = strategyId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-');
  final name = safeId.isEmpty ? 'strategy' : safeId;
  return '${strategyArtifactPaths(basePath).itemDir}${Platform.pathSeparator}$name.json';
}

String readableStrategyLibraryPath(String basePath) {
  final paths = strategyArtifactPaths(basePath);
  if (File(paths.libraryPath).existsSync()) return paths.libraryPath;
  if (File(paths.legacyLibraryPath).existsSync()) {
    return paths.legacyLibraryPath;
  }
  return paths.libraryPath;
}

StrategyArtifactPaths ensureStrategyArtifactDirs(ToolContext context) {
  final paths = strategyArtifactPaths(context.basePath);
  Directory(paths.strategyDir).createSync(recursive: true);
  Directory(paths.itemDir).createSync(recursive: true);
  return paths;
}
