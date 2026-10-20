import 'dart:ui';
import 'package:flutter/material.dart';
import 'tokens.dart';

/// Shared app modal surface matching the web dialogs.
class AppDialog extends StatelessWidget {
  const AppDialog(
      {super.key,
      required this.title,
      required this.description,
      this.children = const [],
      required this.actions,
      this.icon = Icons.info_outline,
      this.iconBesideTitle = false});

  final String title, description;
  final IconData icon;
  final bool iconBesideTitle;
  final List<Widget> children, actions;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Dialog(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 450),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: p.border)),
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: DefaultTextStyle(
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: CLType.caption, color: p.text),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!iconBesideTitle) ...[
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Icon(icon, size: 25, color: p.text)),
                      const SizedBox(height: 14),
                    ],
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (iconBesideTitle) ...[
                            Icon(icon, size: 22, color: p.text),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                              child: Semantics(
                                  header: true,
                                  child: Text(title,
                                      style: TextStyle(
                                          fontSize: CLType.screenTitle,
                                          fontWeight: FontWeight.w600,
                                          color: p.text)))),
                        ]),
                    const SizedBox(height: 6),
                    Text(description,
                        style: TextStyle(color: p.text2, height: 1.6)),
                    ...children,
                    const SizedBox(height: 22),
                    Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: actions),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}

class AppDialogAction extends StatelessWidget {
  const AppDialogAction(
      {super.key,
      required this.label,
      required this.onPressed,
      this.primary = false,
      this.destructive = false});
  final String label;
  final VoidCallback? onPressed;
  final bool primary, destructive;

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: primary ? p.brand : p.surface2,
        foregroundColor: primary
            ? Colors.white
            : destructive
                ? Theme.of(context).colorScheme.error
                : p.text,
        disabledBackgroundColor:
            primary ? p.brand.withValues(alpha: .5) : p.surface2,
        disabledForegroundColor: primary ? Colors.white70 : p.text3,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: primary ? Colors.transparent : p.border)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: CLType.label),
      ),
      child: Text(label),
    );
  }
}
