// The report sheet, shared by every surface that can file one.
//
// Extracted from user_profile_view.dart, which owned the only copy back when
// accounts were the only reportable thing. Mirrors webapp's ReportModal.tsx:
// a reason dropdown (default "spam"), an optional description, one POST to
// /api/user/reports.
//
// What differs per surface is only the target and the heading. The request
// shape is identical because the server resolves the responsible ENTITY
// itself - a post report and a page report both land on the same column.

import 'dart:math' as math;

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/requests/settings_api.dart';
import 'package:flutter/material.dart';

/// Mirrors Report.TARGET_TYPE_CHOICES in the user_service entity app.
///
/// For [user] and [realm] the target id is the ENTITY id (a realm also accepts
/// its own realm id, which is all a server screen tends to hold); for the
/// content types it is the artefact's own id.
enum ReportTargetType {
  user('user', 'Report this account'),
  realm('realm', 'Report this page'),
  post('post', 'Report this post'),
  comment('comment', 'Report this comment'),
  message('message', 'Report this message');

  final String wire;
  final String defaultTitle;
  const ReportTargetType(this.wire, this.defaultTitle);
}

/// Kept in sync with Report.REASON_CHOICES. Static rather than fetched: the
/// sheet must open instantly, and the server re-validates every value, so a
/// stale entry here fails closed with a 400 rather than filing a report under
/// the wrong reason.
const _kReportReasons = <(String, String)>[
  ('spam', 'Spam'),
  ('harassment', 'Harassment or bullying'),
  ('hate_speech', 'Hate speech'),
  ('violence', 'Violence or dangerous behavior'),
  ('nudity', 'Nudity or sexual content'),
  ('csae', 'Child sexual abuse or exploitation'),
  ('impersonation', 'Impersonation'),
  ('misinformation', 'Misinformation'),
  ('other', 'Other'),
];

/// The report affordance pinned to a realm card's top-right corner.
///
/// Meant to sit inside a [Stack] as the last child, so it paints over the
/// card's banner and takes the tap before the card's own InkWell does -
/// otherwise reporting a server would also open it.
///
/// Renders nothing without a target, which is what keeps it off cards whose
/// payload has no entity id rather than opening a sheet that can only fail.
class RealmCardReportButton extends StatelessWidget {
  /// Entity id of the realm - or its realm id, which the endpoint also
  /// resolves.
  final String targetId;

  /// "page" / "server" / "group" / ... Only used for the sheet heading.
  final String? realmType;

  /// Hidden while you ARE this realm; the server rejects self-reports anyway.
  final bool hidden;

  const RealmCardReportButton({
    super.key,
    required this.targetId,
    this.realmType,
    this.hidden = false,
  });

  @override
  Widget build(BuildContext context) {
    if (hidden || targetId.isEmpty) return const SizedBox.shrink();
    final noun =
        (realmType == null || realmType == 'page') ? 'page' : realmType!;

    return Positioned(
      top: 4,
      right: 4,
      child: Material(
        // Neutral scrim, NOT the danger red the labelled Report entries use.
        // This sits on a card's cover photo as a small icon-only affordance;
        // a red dot in the corner of every realm card reads as an alert about
        // the card rather than an action available on it. Red is reserved for
        // the menu/sheet entries that say "Report" in words.
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showReportSheet(
            context,
            targetType: ReportTargetType.realm,
            targetId: targetId,
            title: 'Report this $noun',
          ),
          child: const SizedBox(
            width: 28,
            height: 28,
            child: Icon(Icons.report, size: 15, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Opens the report sheet. Resolves true when a report was actually filed.
///
/// [title] overrides the target type's default heading - e.g. "Report this
/// server" for a realm whose type is server rather than page.
Future<bool> showReportSheet(
  BuildContext context, {
  required ReportTargetType targetType,
  required String targetId,
  String? title,
}) async {
  if (targetId.isEmpty) return false;
  final p = cl(context);
  final messenger = ScaffoldMessenger.of(context);

  String reason = 'spam';
  final descController = TextEditingController();
  bool submitting = false;

  final submitted = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetCtx) {
      return StatefulBuilder(builder: (sheetCtx, setSheet) {
        return PopScope(
          // Swiping the sheet away mid-request wouldn't abort it - it would
          // just hide whether the report went through. Held until the call
          // settles, which is also when this pops itself.
          canPop: !submitting,
          child: SingleChildScrollView(
            // viewInsets alone (the keyboard) left Submit sitting UNDER the
            // system navigation bar whenever the keyboard was down, because
            // viewInsets says nothing about the nav bar. viewPadding is the
            // nav bar, and the two are mutually exclusive in practice - the
            // keyboard covers the bar - so taking the larger clears whichever
            // is actually there without double-padding when the keyboard is up.
            //
            // Scrollable because with the keyboard open on a short screen the
            // sheet's content is taller than what's left of the viewport.
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: math.max(
                      MediaQuery.of(sheetCtx).viewInsets.bottom,
                      MediaQuery.of(sheetCtx).viewPadding.bottom,
                    ) +
                    20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.report, color: p.text, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title ?? targetType.defaultTitle,
                        style: TextStyle(
                            fontSize: CLType.sectionTitle,
                            fontWeight: FontWeight.w700,
                            color: p.text)),
                  ),
                ]),
                const SizedBox(height: 16),
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: p.input,
                    borderRadius: BorderRadius.circular(CLRadii.sm),
                    border: Border.all(color: p.border2),
                  ),
                  child: DropdownButton<String>(
                    value: reason,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: p.surface,
                    style: TextStyle(color: p.text, fontSize: CLType.title),
                    items: _kReportReasons
                        .map((r) =>
                            DropdownMenuItem(value: r.$1, child: Text(r.$2)))
                        .toList(),
                    // Everything locks while the request is in flight: the
                    // values have already been sent, so a change now would
                    // silently disagree with what gets filed. A null onChanged
                    // is how a DropdownButton disables itself.
                    onChanged: submitting
                        ? null
                        : (v) => setSheet(() => reason = v ?? 'spam'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  enabled: !submitting,
                  style: TextStyle(color: p.text, fontSize: CLType.title),
                  decoration: InputDecoration(
                    hintText: 'Add more details (optional)',
                    hintStyle: TextStyle(color: p.text3, fontSize: CLType.body),
                    filled: true,
                    fillColor: p.input,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CLRadii.sm),
                        borderSide: BorderSide(color: p.border2)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CLRadii.sm),
                        borderSide: BorderSide(color: p.border2)),
                    disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CLRadii.sm),
                        borderSide: BorderSide(color: p.border2)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CLRadii.sm),
                        borderSide: BorderSide(color: p.brand)),
                  ),
                ),
                const SizedBox(height: 16),
                CLBtn(
                  label: submitting ? 'Submitting…' : 'Submit report',
                  block: true,
                  size: CLBtnSize.lg,
                  onPressed: submitting
                      ? null
                      : () async {
                          setSheet(() => submitting = true);
                          final result = await SettingsApi().submitReport(
                            targetType: targetType.wire,
                            targetId: targetId,
                            reason: reason,
                            description: descController.text.trim(),
                          );
                          // The sheet's own context is the only one guaranteed
                          // to still be mounted here - the caller may have been
                          // disposed while the request was in flight - so pop
                          // through it and toast through the messenger captured
                          // before the sheet opened.
                          if (!sheetCtx.mounted) return;
                          Navigator.of(sheetCtx).pop(result.ok);
                          messenger.showSnackBar(SnackBar(
                              content: Text(result.message ??
                                  (result.ok
                                      ? 'Report submitted'
                                      : 'Could not submit report'))));
                        },
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      });
    },
  );

  descController.dispose();
  return submitted == true;
}
