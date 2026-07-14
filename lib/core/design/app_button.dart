// Shared primary-button widget wrapping the ElevatedButton.styleFrom(...)
// pattern duplicated across login/signup/profile screens.

import 'package:chatterloop_app/core/design/app_colors.dart';
import 'package:flutter/material.dart';

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brand,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: EdgeInsets.symmetric(vertical: 14)),
        onPressed: loading ? null : onPressed,
        child: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.white))
            : Text(label,
                style: TextStyle(fontSize: 14, color: AppColors.white)),
      ),
    );
  }
}
