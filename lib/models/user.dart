class UserData {
  final int userId;
  final String username;
  final String name;
  final String email;
  final String role;
  final String? phone;
  final String? purok;
  final String? completeAddress;
  final String? licenseNumber;
  final String? preferredTruck;
  final int isArchived;
  final String? createdAt;

  UserData({
    this.userId = 0,
    this.username = '',
    this.name = '',
    this.email = '',
    this.role = '',
    this.phone,
    this.purok,
    this.completeAddress,
    this.licenseNumber,
    this.preferredTruck,
    this.isArchived = 0,
    this.createdAt,
  });

  factory UserData.fromJson(Map<String, dynamic> json) {
    return UserData(
      userId: int.tryParse(json['user_id'].toString()) ?? 0,
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      phone: json['phone']?.toString(),
      purok: json['purok']?.toString(),
      completeAddress: json['complete_address']?.toString(),
      licenseNumber: json['license_number']?.toString(),
      preferredTruck: json['preferred_truck']?.toString(),
      isArchived: int.tryParse(json['is_archived'].toString()) ?? 0,
      createdAt: json['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'username': username,
      'name': name,
      'email': email,
      'role': role,
      'phone': phone,
      'purok': purok,
      'complete_address': completeAddress,
      'license_number': licenseNumber,
      'preferred_truck': preferredTruck,
      'is_archived': isArchived,
      'created_at': createdAt,
    };
  }
}
