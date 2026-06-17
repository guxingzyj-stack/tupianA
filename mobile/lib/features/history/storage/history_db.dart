import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/models/enhance_models.dart';
import '../../../core/models/video_models.dart';

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository();
});

final historyEntriesProvider = FutureProvider<List<HistoryEntry>>((ref) async {
  final repository = ref.watch(historyRepositoryProvider);
  await repository.cleanupOldEntries();
  return repository.listEntries();
});

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.jobId,
    required this.originalPath,
    required this.basePath,
    required this.resultPaths,
    required this.createdAt,
    required this.intentName,
    required this.analyzeResult,
    this.mediaType = 'image',
    this.videoPath,
    this.thumbnailOverridePath,
  });

  final String id;
  final String jobId;
  final String originalPath;
  final String? basePath;
  final Map<int, String> resultPaths;
  final DateTime createdAt;
  final String intentName;
  final AnalyzeResult analyzeResult;
  final String mediaType;
  final String? videoPath;
  final String? thumbnailOverridePath;

  bool get isVideo => mediaType == 'video';

  String? get thumbnailPath {
    if (thumbnailOverridePath != null) {
      return thumbnailOverridePath;
    }
    if (resultPaths.isNotEmpty) {
      return resultPaths.entries.last.value;
    }
    return basePath;
  }

  ResultPageArgs toResultArgs() {
    return ResultPageArgs(
      originalImagePath: originalPath,
      analyzeResult: analyzeResult,
      baseLocalPath: basePath,
      cachedResultPaths: resultPaths,
    );
  }

  VideoResultArgs toVideoArgs() {
    return VideoResultArgs(videoUrl: videoPath ?? '', title: intentName);
  }

  factory HistoryEntry.fromRow(Map<String, Object?> row) {
    final resultPathsJson = jsonDecode(
      row['result_paths_json'] as String? ?? '{}',
    ) as Map<String, dynamic>;
    final resultPaths = <int, String>{};
    String? basePath;
    for (final entry in resultPathsJson.entries) {
      if (entry.key == 'base') {
        basePath = entry.value as String?;
      } else {
        final index = int.tryParse(entry.key);
        if (index != null && entry.value is String) {
          resultPaths[index] = entry.value as String;
        }
      }
    }

    return HistoryEntry(
      id: row['id'] as String,
      jobId: row['job_id'] as String,
      originalPath: row['original_path'] as String,
      basePath: basePath,
      resultPaths: resultPaths,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as int) * 1000,
      ),
      intentName: row['intent_name'] as String? ?? '修好的照片',
      analyzeResult: AnalyzeResult.fromJson(
        jsonDecode(row['analysis_json'] as String? ?? '{}')
            as Map<String, dynamic>,
      ),
      mediaType: row['media_type'] as String? ?? 'image',
      videoPath: row['video_path'] as String?,
      thumbnailOverridePath: row['thumbnail_path'] as String?,
    );
  }
}

class HistoryRepository {
  Database? _db;

  Future<Database> _database() async {
    if (kIsWeb) {
      throw UnsupportedError('Local history database is not available on web.');
    }
    final existing = _db;
    if (existing != null) {
      return existing;
    }
    final dbPath = p.join(await getDatabasesPath(), 'laozhao_history.db');
    final db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE history (
            id TEXT PRIMARY KEY,
            job_id TEXT NOT NULL,
            original_path TEXT NOT NULL,
            result_paths_json TEXT NOT NULL,
            analysis_json TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            intent_name TEXT NOT NULL,
            media_type TEXT NOT NULL DEFAULT 'image',
            video_path TEXT,
            thumbnail_path TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_history_created ON history(created_at DESC)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE history ADD COLUMN media_type TEXT NOT NULL DEFAULT 'image'",
          );
          await db.execute("ALTER TABLE history ADD COLUMN video_path TEXT");
          await db.execute(
            "ALTER TABLE history ADD COLUMN thumbnail_path TEXT",
          );
        }
      },
    );
    _db = db;
    return db;
  }

  Future<List<HistoryEntry>> listEntries() async {
    if (kIsWeb) {
      return const [];
    }
    final db = await _database();
    final rows = await db.query(
      'history',
      orderBy: 'created_at DESC',
      limit: 200,
    );
    return rows.map(HistoryEntry.fromRow).toList();
  }

  Future<void> upsertBaseResult({
    required String jobId,
    required String originalImagePath,
    required AnalyzeResult analyzeResult,
    required String baseImagePath,
  }) async {
    if (kIsWeb) {
      return;
    }
    final db = await _database();
    final originalCopy = await _copyOriginalIfNeeded(jobId, originalImagePath);
    final existing = await _getRow(jobId);
    final paths = existing == null
        ? <String, dynamic>{}
        : jsonDecode(existing['result_paths_json'] as String)
              as Map<String, dynamic>;
    paths['base'] = baseImagePath;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await db.insert('history', {
      'id': jobId,
      'job_id': jobId,
      'original_path': originalCopy,
      'result_paths_json': jsonEncode(paths),
      'analysis_json': jsonEncode(analyzeResult.toJson()),
      'created_at': existing?['created_at'] ?? now,
      'intent_name': existing?['intent_name'] ?? '基础修复',
      'media_type': 'image',
      'video_path': existing?['video_path'],
      'thumbnail_path': existing?['thumbnail_path'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertOptionResult({
    required String jobId,
    required String originalImagePath,
    required AnalyzeResult analyzeResult,
    required int optionIndex,
    required String resultImagePath,
    required String intentName,
  }) async {
    if (kIsWeb) {
      return;
    }
    final db = await _database();
    final originalCopy = await _copyOriginalIfNeeded(jobId, originalImagePath);
    final existing = await _getRow(jobId);
    final paths = existing == null
        ? <String, dynamic>{}
        : jsonDecode(existing['result_paths_json'] as String)
              as Map<String, dynamic>;
    paths['$optionIndex'] = resultImagePath;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await db.insert('history', {
      'id': jobId,
      'job_id': jobId,
      'original_path': originalCopy,
      'result_paths_json': jsonEncode(paths),
      'analysis_json': jsonEncode(analyzeResult.toJson()),
      'created_at': existing?['created_at'] ?? now,
      'intent_name': intentName,
      'media_type': 'image',
      'video_path': existing?['video_path'],
      'thumbnail_path': existing?['thumbnail_path'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertVideoResult({
    required String jobId,
    required String videoPath,
    required String intentName,
    String? thumbnailPath,
  }) async {
    if (kIsWeb) {
      return;
    }
    final db = await _database();
    final existing = await _getRow(jobId);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final analysisJson =
        existing?['analysis_json'] as String? ??
        jsonEncode(
          AnalyzeResult(
            jobId: jobId,
            baseImageUrl: '',
            analysis: const PhotoAnalysis(
              scene: '视频',
              subject: '动态',
              problems: [],
              options: [],
            ),
          ).toJson(),
        );

    await db.insert('history', {
      'id': jobId,
      'job_id': jobId,
      'original_path': existing?['original_path'] ?? '',
      'result_paths_json': existing?['result_paths_json'] ?? '{}',
      'analysis_json': analysisJson,
      'created_at': existing?['created_at'] ?? now,
      'intent_name': intentName,
      'media_type': 'video',
      'video_path': videoPath,
      'thumbnail_path': thumbnailPath,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<File> cacheResultVideo({
    required Dio dio,
    required String videoUrl,
    required String jobId,
    required String name,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Video caching is not available on web.');
    }
    final dir = await _jobDir(jobId);
    final file = File(p.join(dir.path, '$name.mp4'));
    if (await file.exists()) {
      return file;
    }

    await dio.download(videoUrl, file.path);
    if (!await file.exists() || await file.length() == 0) {
      throw StateError('empty video');
    }
    return file;
  }

  Future<File> cacheResultImage({
    required Dio dio,
    required String imageUrl,
    required String jobId,
    required String name,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Image caching is not available on web.');
    }
    final dir = await _jobDir(jobId);
    final file = File(p.join(dir.path, '$name.jpg'));
    if (await file.exists()) {
      return file;
    }

    final response = await dio.get<List<int>>(
      imageUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(response.data ?? const []);
    if (bytes.isEmpty) {
      throw StateError('empty image');
    }
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> cleanupOldEntries() async {
    if (kIsWeb) {
      return;
    }
    final db = await _database();
    final cutoff =
        DateTime.now()
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch ~/
        1000;
    final oldRows = await db.query(
      'history',
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
    for (final row in oldRows) {
      final jobId = row['job_id'] as String;
      final dir = await _jobDir(jobId);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
    await db.delete('history', where: 'created_at < ?', whereArgs: [cutoff]);
  }

  Future<void> deleteEntry(String jobId) async {
    if (kIsWeb) {
      return;
    }
    final db = await _database();
    await db.delete('history', where: 'job_id = ?', whereArgs: [jobId]);
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(documents.path, 'laozhao_history', jobId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<Map<String, Object?>?> _getRow(String jobId) async {
    final db = await _database();
    final rows = await db.query(
      'history',
      where: 'job_id = ?',
      whereArgs: [jobId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> _copyOriginalIfNeeded(
    String jobId,
    String originalImagePath,
  ) async {
    final dir = await _jobDir(jobId);
    final extension = p.extension(originalImagePath).isEmpty
        ? '.jpg'
        : p.extension(originalImagePath);
    final target = File(p.join(dir.path, 'original$extension'));
    if (await target.exists()) {
      return target.path;
    }
    await File(originalImagePath).copy(target.path);
    return target.path;
  }

  Future<Directory> _jobDir(String jobId) async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(documents.path, 'laozhao_history', jobId));
    await dir.create(recursive: true);
    return dir;
  }
}
