import 'package:chatterloop_app/core/design/app_button.dart';
import 'package:chatterloop_app/core/design/app_colors.dart';
import 'package:chatterloop_app/core/design/app_text_field.dart';
import 'package:chatterloop_app/core/requests/http_requests.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  String code = "";
  bool isSubmitting = false;
  String? errorMessage;
  bool verified = false;

  Future<void> _submit() async {
    if (code.trim().isEmpty) {
      setState(() => errorMessage = "Enter the code sent to your email");
      return;
    }

    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });

    final ok = await APIRequests().verifyEmailRequest(code.trim());

    if (!mounted) return;
    if (!ok) {
      setState(() {
        isSubmitting = false;
        errorMessage = "Invalid or expired code";
      });
      return;
    }

    setState(() {
      isSubmitting = false;
      verified = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brand,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Verify your email",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white)),
              SizedBox(height: 6),
              Text("We sent a verification code to your email address.",
                  style: TextStyle(color: AppColors.white, fontSize: 13)),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16)),
                child: verified
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Your account is verified.",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary)),
                          SizedBox(height: 12),
                          AppButton(
                              label: "Continue",
                              onPressed: () => context.go('/home')),
                        ],
                      )
                    : Column(
                        children: [
                          AppTextField(
                              hint: "Verification code",
                              keyboardType: TextInputType.number,
                              onChanged: (v) => code = v),
                          if (errorMessage != null)
                            Padding(
                              padding: EdgeInsets.only(top: 4, bottom: 10),
                              child: Text(errorMessage!,
                                  style: TextStyle(
                                      color: AppColors.danger, fontSize: 13)),
                            )
                          else
                            SizedBox(height: 10),
                          AppButton(
                              label: "Verify",
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
