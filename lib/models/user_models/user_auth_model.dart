class UserAuth {
  final bool? auth;
  final UserAccount user;

  const UserAuth(this.auth, this.user);

  @override
  String toString() {
    return 'UserAuth(auth: $auth, user: $user)';
  }
}

class UserAccount {
  final String userID;
  final UserFullname fullName;
  final String? email;
  final bool isActivated;
  final bool isVerified;
  final String? profile;
  final String? coverphoto;
  final String? gender;
  final UserBirthDate? birthdate;

  const UserAccount(
      this.userID,
      this.fullName,
      this.email,
      this.isActivated,
      this.isVerified,
      this.profile,
      this.coverphoto,
      this.gender,
      this.birthdate);

  @override
  String toString() {
    return 'UserAccount(userID: $userID, fullname: $fullName, email: $email, isActivated: $isActivated, isVerified: $isVerified)';
  }

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
        json["userID"],
        UserFullname.fromJson(json["fullName"] ?? json["fullname"]),
        json["email"],
        json["isActivated"],
        json["isVerified"],
        json["profile"],
        json["coverphoto"],
        json["gender"],
        UserBirthDate.fromJson(json["birthdate"]));
  }
}

class UserBirthDate {
  final String month;
  final String day;
  final String year;

  UserBirthDate(this.month, this.day, this.year);

  factory UserBirthDate.fromJson(Map<String, dynamic> json) {
    return UserBirthDate(
      json["month"],
      json["day"],
      json["year"],
    );
  }
}

class UserFullname {
  final String firstName;
  final String middleName;
  final String lastName;

  const UserFullname(this.firstName, this.middleName, this.lastName);

  @override
  String toString() {
    return 'UserFullname(firstName: $firstName, middleName; $middleName, lastName: $lastName)';
  }

  factory UserFullname.fromJson(Map<String, dynamic> json) {
    return UserFullname(
      json["firstName"],
      json["middleName"],
      json["lastName"],
    );
  }
}
