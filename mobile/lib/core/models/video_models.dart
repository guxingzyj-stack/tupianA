class MotionPreset {
  const MotionPreset({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}

const motionPresets = [
  MotionPreset(id: 'slow_zoom', name: '缓慢推镜', description: '镜头慢慢靠近'),
  MotionPreset(id: 'env_breeze', name: '环境微动', description: '风景轻轻动'),
  MotionPreset(id: 'subtle_human', name: '人物轻动', description: '头发衣角轻动'),
];

class VideoCreateResult {
  const VideoCreateResult({
    required this.jobId,
    required this.status,
    required this.estimatedSeconds,
  });

  final String jobId;
  final String status;
  final int estimatedSeconds;

  factory VideoCreateResult.fromJson(Map<String, dynamic> json) {
    return VideoCreateResult(
      jobId: json['job_id'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      estimatedSeconds: json['estimated_seconds'] as int? ?? 120,
    );
  }
}

class JobStatusResult {
  const JobStatusResult({
    required this.jobId,
    required this.status,
    required this.progress,
    this.resultUrl,
    this.error,
  });

  final String jobId;
  final String status;
  final int progress;
  final String? resultUrl;
  final String? error;

  bool get isDone => status == 'success';
  bool get isFailed => status == 'failed';

  factory JobStatusResult.fromJson(Map<String, dynamic> json) {
    return JobStatusResult(
      jobId: json['job_id'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      progress: json['progress'] as int? ?? 0,
      resultUrl: json['result_url'] as String?,
      error: json['error'] as String?,
    );
  }
}

class VideoSetupArgs {
  const VideoSetupArgs({required this.imageUrl, this.isOldPhoto = false});

  final String imageUrl;
  final bool isOldPhoto;
}

class VideoWaitingArgs {
  const VideoWaitingArgs({
    required this.estimatedSeconds,
    this.resultTitle = '动态视频',
  });

  final int estimatedSeconds;
  final String resultTitle;
}

class VideoResultArgs {
  const VideoResultArgs({required this.videoUrl, this.title = '动态视频'});

  final String videoUrl;
  final String title;
}
