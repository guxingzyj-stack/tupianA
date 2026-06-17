class BlessingTemplate {
  const BlessingTemplate({
    required this.id,
    required this.name,
    required this.motion,
    required this.textPresets,
  });

  final String id;
  final String name;
  final String motion;
  final List<String> textPresets;

  factory BlessingTemplate.fromJson(Map<String, dynamic> json) {
    final rawPresets = json['text_presets'] as List<dynamic>? ?? const [];
    return BlessingTemplate(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      motion: json['motion'] as String? ?? 'slow_zoom',
      textPresets: rawPresets.map((item) => item.toString()).toList(),
    );
  }
}

class TemplateCategory {
  const TemplateCategory({
    required this.id,
    required this.name,
    required this.templates,
  });

  final String id;
  final String name;
  final List<BlessingTemplate> templates;

  factory TemplateCategory.fromJson(Map<String, dynamic> json) {
    final rawTemplates = json['templates'] as List<dynamic>? ?? const [];
    return TemplateCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      templates: rawTemplates
          .whereType<Map<String, dynamic>>()
          .map(BlessingTemplate.fromJson)
          .toList(),
    );
  }
}

class TemplateCatalog {
  const TemplateCatalog({required this.categories});

  final List<TemplateCategory> categories;

  factory TemplateCatalog.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'] as List<dynamic>? ?? const [];
    return TemplateCatalog(
      categories: rawCategories
          .whereType<Map<String, dynamic>>()
          .map(TemplateCategory.fromJson)
          .toList(),
    );
  }
}

class TemplateApplyResult {
  const TemplateApplyResult({
    required this.jobId,
    required this.status,
    required this.estimatedSeconds,
  });

  final String jobId;
  final String status;
  final int estimatedSeconds;

  factory TemplateApplyResult.fromJson(Map<String, dynamic> json) {
    return TemplateApplyResult(
      jobId: json['job_id'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      estimatedSeconds: json['estimated_seconds'] as int? ?? 120,
    );
  }
}
