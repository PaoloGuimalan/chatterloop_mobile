// Shared text-input widget replacing the ad hoc TextField + Container +
// BoxDecoration boilerplate duplicated in login_view.dart and needed again
// by signup/profile-edit.

import 'package:chatterloop_app/core/design/app_colors.dart';
import 'package:flutter/material.dart';

class AppTextField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? errorText;

  const AppTextField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.errorText,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscure = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 350),
          child: Container(
            height: 50,
            padding: EdgeInsets.only(left: 10, right: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.white,
              border: widget.errorText != null
                  ? Border.all(color: AppColors.danger, width: 1)
                  : null,
            ),
            child: TextField(
              obscureText: _obscure,
              keyboardType: widget.keyboardType,
              onChanged: widget.onChanged,
              style: TextStyle(fontSize: 14),
              decoration: InputDecoration(
                fillColor: AppColors.white,
                hintText: widget.hint,
                border: InputBorder.none,
                suffixIcon: widget.obscureText
                    ? IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      )
                    : null,
              ),
            ),
          ),
        ),
        if (widget.errorText != null)
          Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text(widget.errorText!,
                style: TextStyle(color: AppColors.danger, fontSize: 12)),
          ),
      ],
    );
  }
}
