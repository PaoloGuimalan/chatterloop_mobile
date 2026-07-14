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
  final String id;
  final String username;
  final String firstname;
  final String middlename;
  final String lastname;
  final String? email;
  final bool isActivated;
  final bool isVerified;
  final String? profile;
  final String? coverphoto;
  final String? gender;
  final UserBirthDate? birthdate;

  const UserAccount(
      this.id,
      this.username,
      this.firstname,
      this.middlename,
      this.lastname,
      this.email,
      this.isActivated,
      this.isVerified,
      this.profile,
      this.coverphoto,
      this.gender,
      this.birthdate);

  @override
  String toString() {
    return 'UserAccount(id: $id, username: $username, firstname: $firstname, middlename: $middlename, lastname: $lastname, email: $email, isActivated: $isActivated, isVerified: $isVerified)';
  }

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
        json["id"],
        json["username"],
        json["firstname"],
        json["middlename"],
        json["lastname"],
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
