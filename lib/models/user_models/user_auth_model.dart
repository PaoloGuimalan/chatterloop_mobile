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
  final String email;
  final bool isActivated;
  final bool isVerified;

  const UserAccount(this.userID, this.fullName, this.email, this.isActivated,
      this.isVerified);

  @override
  String toString() {
    return 'UserAccount(userID: $userID, fullname: $fullName, email: $email, isActivated: $isActivated, isVerified: $isVerified)';
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
}
