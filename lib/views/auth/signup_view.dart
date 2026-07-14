import 'package:chatterloop_app/core/configs/keys.dart';
import 'package:chatterloop_app/core/design/app_button.dart';
import 'package:chatterloop_app/core/design/app_colors.dart';
import 'package:chatterloop_app/core/design/app_text_field.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:chatterloop_app/core/utils/jwt_tools.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final storage = FlutterSecureStorage();

  String firstName = "";
  String middleName = "";
  String lastName = "";
  String email = "";
  String password = "";
  String? gender;
  String birthday = "";
  String birthmonth = "";
  String birthyear = "";
  bool agreedToTerms = false;
  bool isSubmitting = false;
  String? errorMessage;

  Future<void> _submit() async {
    final day = int.tryParse(birthday);
    final month = int.tryParse(birthmonth);
    final year = int.tryParse(birthyear);

    if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
      setState(() => errorMessage = "First and last name are required");
      return;
    }
    if (email.trim().isEmpty || !email.contains('@')) {
      setState(() => errorMessage = "A valid email is required");
      return;
    }
    if (password.length < 8) {
      setState(() => errorMessage = "Password must be at least 8 characters");
      return;
    }
    if (gender == null) {
      setState(() => errorMessage = "Gender is required");
      return;
    }
    if (day == null || month == null || year == null) {
      setState(() => errorMessage = "A valid birthdate is required");
      return;
    }
    if (!agreedToTerms) {
      setState(
          () => errorMessage = "You must agree to the Terms and Conditions");
      return;
    }

    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });

    LoginResponse? response = await APIRequests().signupRequest(
      firstName: firstName.trim(),
      middleName: middleName.trim().isEmpty ? null : middleName.trim(),
      lastName: lastName.trim(),
      email: email.trim(),
      password: password,
      gender: gender!,
      agreedToTerms: agreedToTerms,
      birthday: day,
      birthmonth: month,
      birthyear: year,
    );

    if (!mounted) return;

    if (response?.authtoken == null || response?.usertoken == null) {
      setState(() {
        isSubmitting = false;
        errorMessage = "Could not create your account. Please try again.";
      });
      return;
    }

    await storage.write(key: 'token', value: response!.authtoken);
    Map<String, dynamic>? userResponse =
        JwtTools().verifyJwt(response.usertoken, secretKey);

    if (!mounted) return;
    StoreProvider.of<AppState>(context).dispatch(DispatchModel(
        setUserAuthT,
        UserAuth(
            true,
            UserAccount.fromDjangoJwt(userResponse ?? const {},
                allowedModules: response.allowedModules,
                activeEntity: response.activeEntity,
                personalEntityId: response.personalEntityId))));

    context.go('/verify-email');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brand,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppColors.white),
              ),
              Text("Create your account",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white)),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    AppTextField(
                        hint: "First name", onChanged: (v) => firstName = v),
                    SizedBox(height: 10),
                    AppTextField(
                        hint: "Middle name (optional)",
                        onChanged: (v) => middleName = v),
                    SizedBox(height: 10),
                    AppTextField(
                        hint: "Last name", onChanged: (v) => lastName = v),
                    SizedBox(height: 10),
                    AppTextField(
                        hint: "Email",
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (v) => email = v),
                    SizedBox(height: 10),
                    AppTextField(
                        hint: "Password",
                        obscureText: true,
                        onChanged: (v) => password = v),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: 50),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(10)),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  hint: Text("Gender"),
                                  value: gender,
                                  items: ["male", "female", "other"]
                                      .map((g) => DropdownMenuItem(
                                          value: g, child: Text(g)))
                                      .toList(),
                                  onChanged: (v) => setState(() => gender = v),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: AppTextField(
                                hint: "Day",
                                keyboardType: TextInputType.number,
                                onChanged: (v) => birthday = v)),
                        SizedBox(width: 8),
                        Expanded(
                            child: AppTextField(
                                hint: "Month",
                                keyboardType: TextInputType.number,
                                onChanged: (v) => birthmonth = v)),
                        SizedBox(width: 8),
                        Expanded(
                            child: AppTextField(
                                hint: "Year",
                                keyboardType: TextInputType.number,
                                onChanged: (v) => birthyear = v)),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: agreedToTerms,
                          onChanged: (v) =>
                              setState(() => agreedToTerms = v ?? false),
                        ),
                        Expanded(
                            child: Text(
                                "I agree to the Terms and Conditions and Privacy Policy",
                                style: TextStyle(fontSize: 12))),
                      ],
                    ),
                    if (errorMessage != null)
                      Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 10),
                        child: Text(errorMessage!,
                            style: TextStyle(
                                color: AppColors.danger, fontSize: 13)),
                      ),
                    SizedBox(height: 6),
                    AppButton(
                        label: "Sign Up",
                        onPressed: _submit,
                        loading: isSubmitting),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
