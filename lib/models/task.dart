class StoryPhase {
  final int phase;
  final String name;
  final String content;
  final bool completed;

  StoryPhase({
    required this.phase,
    required this.name,
    required this.content,
    required this.completed,
  });

  factory StoryPhase.fromJson(Map<String, dynamic> j) => StoryPhase(
        phase: j['phase'] as int,
        name: j['name'] as String,
        content: j['content'] as String? ?? '',
        completed: j['completed'] as bool? ?? false,
      );
}

class Task {
  final String id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String creatorId;
  final String? reviewerGithubUsername;
  final String? reviewerName;
  final String? githubIssueUrl;
  final int? githubIssueNumber;
  final int currentPhase;
  final int totalPhases;
  final List<StoryPhase> storyPhases;
  final int maxReviewCycles;
  final int currentReviewCycle;
  final DateTime createdAt;
  final DateTime updatedAt;

  Task({
    required this.id,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    required this.creatorId,
    this.reviewerGithubUsername,
    this.reviewerName,
    this.githubIssueUrl,
    this.githubIssueNumber,
    required this.currentPhase,
    required this.totalPhases,
    required this.storyPhases,
    required this.maxReviewCycles,
    required this.currentReviewCycle,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        status: j['status'] as String,
        priority: j['priority'] as String? ?? 'Medium',
        creatorId: j['creator_id'] as String,
        reviewerGithubUsername: j['reviewer_github_username'] as String?,
        reviewerName: j['reviewer_name'] as String?,
        githubIssueUrl: j['github_issue_url'] as String?,
        githubIssueNumber: j['github_issue_number'] as int?,
        currentPhase: j['current_phase'] as int? ?? 0,
        totalPhases: j['total_phases'] as int? ?? 10,
        storyPhases: (j['story_phases'] as List<dynamic>? ?? [])
            .map((e) => StoryPhase.fromJson(e as Map<String, dynamic>))
            .toList(),
        maxReviewCycles: j['max_review_cycles'] as int? ?? 5,
        currentReviewCycle: j['current_review_cycle'] as int? ?? 0,
        createdAt: DateTime.parse('${j['created_at']}Z').toLocal(),
        updatedAt: DateTime.parse('${j['updated_at']}Z').toLocal(),
      );

  bool get isInProgress => status == 'In Progress';
  bool get isDone => status == 'Done';
  bool get canMarkReady => status == 'Backlog';
  bool get canRequestReview => status == 'In Review';
  int get completedPhases => storyPhases.where((p) => p.completed).length;
}
