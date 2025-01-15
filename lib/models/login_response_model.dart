class SchoolLoginResponse {
  final bool success;
  final String message;
  final String token;
  final String role;
  final String username;
  final String schoolName;
  final List<String> branches;

  SchoolLoginResponse({
    required this.success,
    required this.message,
    required this.token,
    required this.role,
    required this.username,
    required this.schoolName,
    required this.branches,
  });

  factory SchoolLoginResponse.fromJson(Map<String, dynamic> json) {
    return SchoolLoginResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      token: json['token'] ?? '',
      role: json['role'] ?? '',
      username: json['username'] ?? '',
      schoolName: json['schoolName'] ?? '',
      branches: List<String>.from(json['branches'] ?? []),
    );
  }
}

class BranchLoginResponse {
  final bool success;
  final String message;
  final String token;
  final String role;
  final String schoolName;
  final String branchName;

  BranchLoginResponse({
    required this.success,
    required this.message,
    required this.token,
    required this.role,
    required this.schoolName,
    required this.branchName,
  });

  factory BranchLoginResponse.fromJson(Map<String, dynamic> json) {
    return BranchLoginResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      token: json['token'] ?? '',
      role: json['role'] ?? '',
      schoolName: json['schoolName'] ?? '',
      branchName: json['branchName'] ?? '',
    );
  }
}

enum LoginType {
  parent,
  branch,
}
