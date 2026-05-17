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
  final List<ReviewerItem> reviewerList;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.githubUsername,
    required this.reviewerList,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        githubUsername: j['github_username'] as String?,
        reviewerList: (j['reviewer_list'] as List<dynamic>? ?? [])
            .map((e) => ReviewerItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
