// The Posts / Saved / Archived switcher that sits under a profile's composer.
//
// Shared by both profile screens. It is not a per-profile control: Saved and
// Archived are the ACTING ENTITY's own lists, never the profile's -
// PostSave rows are keyed on entity, and the profile feed endpoint replaces
// its handle filter with `Q(entity=entity)` outright when archive=true. So a
// page's profile may only show these while you are acting AS that page;
// viewing it as an admin of your own account would list YOUR saves under the
// page's name. Each caller owns that gate - see the isActingEntity checks.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:flutter/material.dart';

/// The three lists a profile's feed column can show.
enum ProfileFeedMode {
  posts("Posts", Icons.grid_view_outlined),
  saves("Saved", Icons.bookmark_border),
  archives("Archived", Icons.inventory_2_outlined);

  const ProfileFeedMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// One control with a moving highlight rather than three separate pills:
/// these are mutually exclusive views of the same column, and a single track
/// says "pick one of these" in a way a row of independent chips does not.
class ProfileFeedSwitcher extends StatelessWidget {
  final ProfileFeedMode active;
  final ValueChanged<ProfileFeedMode> onChanged;

  const ProfileFeedSwitcher(
      {super.key, required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);

    return Container(
      // The track. Segments sit INSIDE this padding, so the highlight never
      // touches the outer edge and the whole thing reads as one control.
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(CLRadii.md),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          for (final mode in ProfileFeedMode.values)
            Expanded(
              child: GestureDetector(
                // Opaque so the whole segment is the target, not just the
                // glyph and label inside it.
                behavior: HitTestBehavior.opaque,
                onTap: mode == active ? null : () => onChanged(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  height: 34,
                  decoration: BoxDecoration(
                    color: mode == active ? p.brand : Colors.transparent,
                    // One step down from the track, so the highlight sits
                    // concentrically inside it rather than fighting its
                    // corners.
                    borderRadius: BorderRadius.circular(CLRadii.sm),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(mode.icon,
                          size: 16,
                          color: mode == active ? Colors.white : p.text2),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          mode.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mode == active ? Colors.white : p.text2,
                            fontSize: CLType.bodySm,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
