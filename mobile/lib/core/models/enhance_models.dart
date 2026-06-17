class RepairOption {
  const RepairOption({required this.name, required this.intent});

  final String name;
  final String intent;

  factory RepairOption.fromJson(Map<String, dynamic> json) {
    return RepairOption(
      name: json['name'] as String? ?? '',
      intent: json['intent'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'intent': intent};
  }
}

class PhotoAnalysis {
  const PhotoAnalysis({
    required this.scene,
    required this.subject,
    required this.problems,
    required this.options,
  });

  final String scene;
  final String subject;
  final List<String> problems;
  final List<RepairOption> options;

  factory PhotoAnalysis.fromJson(Map<String, dynamic> json) {
    final rawProblems = json['problems'] as List<dynamic>? ?? const [];
    final rawOptions = json['options'] as List<dynamic>? ?? const [];
    return PhotoAnalysis(
      scene: json['scene'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      problems: rawProblems.map((item) => item.toString()).toList(),
      options: rawOptions
          .whereType<Map<String, dynamic>>()
          .map(RepairOption.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scene': scene,
      'subject': subject,
      'problems': problems,
      'options': [for (final option in options) option.toJson()],
    };
  }
}

class AnalyzeResult {
  const AnalyzeResult({
    required this.jobId,
    required this.baseImageUrl,
    required this.analysis,
    this.isOldPhoto = false,
  });

  final String jobId;
  final String baseImageUrl;
  final PhotoAnalysis analysis;
  final bool isOldPhoto;

  factory AnalyzeResult.fromJson(Map<String, dynamic> json) {
    return AnalyzeResult(
      jobId: json['job_id'] as String? ?? '',
      baseImageUrl: json['base_image_url'] as String? ?? '',
      analysis: PhotoAnalysis.fromJson(
        json['analysis'] as Map<String, dynamic>? ?? const {},
      ),
      isOldPhoto: json['is_old_photo'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'job_id': jobId,
      'base_image_url': baseImageUrl,
      'analysis': analysis.toJson(),
      'is_old_photo': isOldPhoto,
    };
  }
}

class EnhanceResult {
  const EnhanceResult({
    required this.resultImageUrl,
    required this.processingMs,
  });

  final String resultImageUrl;
  final int processingMs;

  factory EnhanceResult.fromJson(Map<String, dynamic> json) {
    return EnhanceResult(
      resultImageUrl: json['result_image_url'] as String? ?? '',
      processingMs: json['processing_ms'] as int? ?? 0,
    );
  }
}

class ResultPageArgs {
  const ResultPageArgs({
    required this.originalImagePath,
    required this.analyzeResult,
    this.baseLocalPath,
    this.cachedResultPaths = const {},
  });

  final String originalImagePath;
  final AnalyzeResult analyzeResult;
  final String? baseLocalPath;
  final Map<int, String> cachedResultPaths;
}

class AnalyzePageArgs {
  const AnalyzePageArgs({required this.imagePath, this.isShotPaper = false});

  final String imagePath;
  final bool isShotPaper;
}
