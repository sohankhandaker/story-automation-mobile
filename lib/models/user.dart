class ReviewerItem {
  final String name;
  final String githubUsername;
  final String? email;

  ReviewerItem({required this.name, required this.githubUsername, this.email});

  factory ReviewerItem.fromJson(Map<String, dynamic> j) => ReviewerItem(
        name: j['name'] as String,
        githubUsername: j['github_username'] as String,
        email: j['email'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'github_username': githubUsername,
        if (email != null && email!.isNotEmpty) 'email': email,
      };
}

class User {
  final String id;
  final String name;
  final String email;
  final String? githubUsername;
  final String? avatarUrl;
  final List<ReviewerItem> reviewerList;
  final String? ghToken;
  final String? ghOwner;
  final String? ghRepo;
  final int? ghProjectNumber;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.githubUsername,
    this.avatarUrl,
    required this.reviewerList,
    this.ghToken,
    this.ghOwner,
    this.ghRepo,
    this.ghProjectNumber,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        githubUsername: j['github_username'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        reviewerList: (j['reviewer_list'] as List<dynamic>? ?? [])
            .map((e) => ReviewerItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        ghToken: j['gh_token'] as String?,
        ghOwner: j['gh_owner'] as String?,
        ghRepo: j['gh_repo'] as String?,
        ghProjectNumber: j['gh_project_number'] as int?,
      );
}
