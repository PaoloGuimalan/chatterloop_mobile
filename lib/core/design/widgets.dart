// Shared widgets — Flutter counterparts of the webapp's design primitives
// (Avatar, Btn, IconBtn, Card, Badge, Chip, Toggle, SegTabs, Field).

import 'package:flutter/material.dart';

import 'tokens.dart';

// -------- Avatar -------------------------------------------------------------

const _avatarGradients = <List<Color>>[
  [Color(0xFF1C7DEF), Color(0xFF5AA9FF)],
  [Color(0xFF20BD7C), Color(0xFF5BE0A8)],
  [Color(0xFFE69500), Color(0xFFFFC24D)],
  [Color(0xFFFF5B6B), Color(0xFFFF97A1)],
  [Color(0xFF8B5CF6), Color(0xFFB794FF)],
  [Color(0xFF0EA5B7), Color(0xFF4FD6E6)],
  [Color(0xFFF0518C), Color(0xFFFF8FBF)],
  [Color(0xFF3B6FE0), Color(0xFF6FA0FF)],
];

int _avHash(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  return h;
}

String _initials(String name) {
  final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

class CLAvatar extends StatelessWidget {
  final String? id;
  final String? name;
  final String? src;
  final double size;
  final bool online;
  final bool ring;

  const CLAvatar({
    super.key,
    this.id,
    this.name,
    this.src,
    this.size = 40,
    this.online = false,
    this.ring = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final key = id ?? name ?? 'x';
    final grad = _avatarGradients[_avHash(key) % _avatarGradients.length];
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: grad,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(name ?? ''),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.38,
          letterSpacing: 0.4,
        ),
      ),
    );

    Widget content = (src != null && src!.isNotEmpty && src != 'none')
        ? ClipOval(
            child: Image.network(
              src!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Same gradient+initials placeholder for "still downloading"
              // as for "failed to load" - previously there was no
              // loadingBuilder at all, so the circle was simply blank
              // (transparent) for however long the request took, which
              // read as a rendering bug rather than a photo on its way in.
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : placeholder,
              errorBuilder: (_, __, ___) => placeholder,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
            ),
          )
        : placeholder;

    if (ring) {
      content = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.surface, width: 2),
          boxShadow: [
            BoxShadow(color: p.brand, blurRadius: 0, spreadRadius: 2)
          ],
        ),
        child: content,
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          content,
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: (size * 0.28).clamp(9, 18),
                height: (size * 0.28).clamp(9, 18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.online,
                  border: Border.all(color: p.surface, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// -------- Skeleton -------------------------------------------------------------

/// A pulsing placeholder box - use in place of an avatar/text while its real
/// data hasn't loaded yet, instead of rendering the real widget against
/// empty strings (a blank-initialed avatar, an empty text line), which
/// reads as broken rather than as "still loading". Mirrors webapp's
/// react-loading-skeleton usage on the profile page.
class CLSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadiusGeometry borderRadius;

  const CLSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  @override
  State<CLSkeleton> createState() => _CLSkeletonState();
}

class _CLSkeletonState extends State<CLSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            // surface3/surfaceHover (the original pair here) sit only 2-8
            // RGB units from p.bg in light mode - on any screen whose
            // Scaffold background is p.bg directly (Messages/Contacts/
            // Notifications/Search/Profile all are, unlike the
            // conversation screen, which wraps everything in a p.surface
            // container first), the skeleton was rendering the entire
            // time, just essentially invisible against its own
            // background. border2 gives real contrast against both p.bg
            // and p.surface, in both themes, regardless of what it's
            // sitting on.
            color: Color.lerp(p.surface3, p.border2, _controller.value),
            borderRadius: widget.borderRadius,
          ),
        );
      },
    );
  }
}

// -------- Network image --------------------------------------------------------

/// Image.network wrapped with a pulsing skeleton while bytes are still
/// downloading (instead of a blank gap that pops in once loaded), a fade-in
/// once the first frame decodes, a static neutral placeholder on failure
/// (not a forever-pulsing skeleton, which would misleadingly imply it's
/// still loading), and an AnimatedSize so the swap between skeleton and
/// real content doesn't jump instantly when no explicit height is given
/// (e.g. message/link-preview images, whose real aspect ratio isn't known
/// until the bytes actually arrive).
class CLNetworkImage extends StatelessWidget {
  final String src;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadiusGeometry? borderRadius;
  final double placeholderHeight;
  final WidgetBuilder? errorBuilder;

  const CLNetworkImage({
    super.key,
    required this.src,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderHeight = 160,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final resolvedPlaceholderHeight = height ?? placeholderHeight;

    final image = Image.network(
      src,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return CLSkeleton(
          width: width ?? double.infinity,
          height: resolvedPlaceholderHeight,
          borderRadius: borderRadius ?? BorderRadius.zero,
        );
      },
      errorBuilder: (context, error, stack) =>
          errorBuilder?.call(context) ??
          Container(
            width: width,
            height: resolvedPlaceholderHeight,
            color: p.surface3,
            alignment: Alignment.center,
            child: Icon(Icons.image_not_supported_outlined,
                color: p.text3, size: 22),
          ),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );

    final clipped = borderRadius != null
        ? ClipRRect(borderRadius: borderRadius!, child: image)
        : image;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: clipped,
    );
  }
}

/// Centered icon-badge + title + subtitle, for a screen's "nothing to show
/// yet" states - mirrors webapp's Search.tsx empty-state Card exactly
/// (circular icon badge, bold title, muted subtitle).
class CLEmptyState extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final Color? iconBorderColor;
  final String title;
  final String subtitle;

  const CLEmptyState({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    this.iconBorderColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconBg,
            border: iconBorderColor != null
                ? Border.all(color: iconBorderColor!)
                : null,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 34, color: iconColor),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: p.text),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: p.text2),
        ),
      ],
    );
  }
}

/// One skeleton row shaped like an avatar-list-item (Messages/Contacts/
/// Notifications/Search) - avatar circle + two text bars.
class CLListRowSkeleton extends StatelessWidget {
  final double avatarSize;
  final EdgeInsetsGeometry padding;

  const CLListRowSkeleton({
    super.key,
    this.avatarSize = 46,
    this.padding = const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          CLSkeleton(
            width: avatarSize,
            height: avatarSize,
            borderRadius: BorderRadius.circular(avatarSize / 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const CLSkeleton(width: 140, height: 13),
                const SizedBox(height: 7),
                const CLSkeleton(width: 90, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A handful of CLListRowSkeleton rows, standing in for a list that hasn't
/// loaded yet - use instead of a bare spinner/blank space so the screen
/// reads as "content is on its way" rather than "empty" or "broken".
class CLListSkeleton extends StatelessWidget {
  final int count;
  final double avatarSize;

  const CLListSkeleton({super.key, this.count = 6, this.avatarSize = 46});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (_) => CLListRowSkeleton(avatarSize: avatarSize),
      ),
    );
  }
}

/// Alternating left/right pulsing bubble shapes, standing in for a
/// conversation's messages while the initial fetch is still in flight -
/// closer to what's about to render than a plain centered spinner.
class CLMessageListSkeleton extends StatelessWidget {
  const CLMessageListSkeleton({super.key});

  static const _widths = [190.0, 130.0, 220.0, 150.0, 170.0, 120.0];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _widths.length,
      itemBuilder: (context, index) {
        final isSender = index.isOdd;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment:
                isSender ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              CLSkeleton(
                width: _widths[index],
                height: 34,
                borderRadius: BorderRadius.circular(CLRadii.md),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------- Buttons ------------------------------------------------------------

enum CLBtnVariant { primary, soft, ghost, outline, danger }

enum CLBtnSize { sm, md, lg }

class CLBtn extends StatelessWidget {
  final String label;
  final IconData? iconL;
  final IconData? iconR;
  final VoidCallback? onPressed;
  final CLBtnVariant variant;
  final CLBtnSize size;
  final bool block;

  const CLBtn({
    super.key,
    required this.label,
    this.iconL,
    this.iconR,
    required this.onPressed,
    this.variant = CLBtnVariant.primary,
    this.size = CLBtnSize.md,
    this.block = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final (h, padX, fs) = switch (size) {
      CLBtnSize.sm => (32.0, 12.0, 13.0),
      CLBtnSize.md => (38.0, 16.0, 14.0),
      CLBtnSize.lg => (46.0, 22.0, 15.0),
    };
    final (bg, fg, border) = switch (variant) {
      CLBtnVariant.primary => (p.brand, Colors.white, null),
      CLBtnVariant.soft => (p.brandSoft, p.brand, null),
      CLBtnVariant.ghost => (Colors.transparent, p.text, null),
      CLBtnVariant.outline => (p.surface, p.text, p.border2),
      CLBtnVariant.danger => (p.pink, Colors.white, null),
    };

    final child = Container(
      height: h,
      padding: EdgeInsets.symmetric(horizontal: padX),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CLRadii.sm),
        border: border != null ? Border.all(color: border) : null,
        boxShadow: variant == CLBtnVariant.primary
            ? [
                BoxShadow(
                    color: p.brand.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (iconL != null) ...[
            Icon(iconL, size: fs + 4, color: fg),
            const SizedBox(width: 7),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: fs,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (iconR != null) ...[
            const SizedBox(width: 7),
            Icon(iconR, size: fs + 4, color: fg),
          ],
        ],
      ),
    );

    final wrapped = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(CLRadii.sm),
      child: Opacity(opacity: onPressed == null ? 0.55 : 1.0, child: child),
    );
    return block ? SizedBox(width: double.infinity, child: wrapped) : wrapped;
  }
}

class CLIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? color;

  const CLIconBtn({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 40,
    this.iconSize = 22,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: iconSize,
      icon: Icon(icon, color: color ?? p.text2),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CLRadii.sm),
        ),
        minimumSize: Size(size, size),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

// -------- Card ---------------------------------------------------------------

class CLCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const CLCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(CLRadii.md),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 3,
              offset: const Offset(0, 1)),
        ],
      ),
      child: child,
    );
  }
}

// -------- Badge --------------------------------------------------------------

enum CLBadgeTone { brand, green, gold, pink, grey }

class CLBadge extends StatelessWidget {
  final String label;
  final CLBadgeTone tone;

  const CLBadge(
      {super.key, required this.label, this.tone = CLBadgeTone.brand});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final (bg, fg) = switch (tone) {
      CLBadgeTone.brand => (p.brandSoft, p.brand),
      CLBadgeTone.green => (p.greenSoft, p.green),
      CLBadgeTone.gold => (p.goldSoft, p.gold),
      CLBadgeTone.pink => (p.pinkSoft, p.pink),
      CLBadgeTone.grey => (p.surface3, p.text2),
    };
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CLRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// -------- Chip ---------------------------------------------------------------

class CLChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback? onTap;

  const CLChip(
      {super.key,
      required this.label,
      this.icon,
      this.active = false,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CLRadii.pill),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? p.brand : p.surface,
          borderRadius: BorderRadius.circular(CLRadii.pill),
          border: Border.all(color: active ? Colors.transparent : p.border2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: active ? Colors.white : p.text2),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : p.text2,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------- Field --------------------------------------------------------------

class CLField extends StatelessWidget {
  final String? label;
  final String? placeholder;
  final IconData? icon;
  final bool obscure;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const CLField({
    super.key,
    this.label,
    this.placeholder,
    this.icon,
    this.obscure = false,
    this.controller,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 12,
                color: p.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: p.input,
            borderRadius: BorderRadius.circular(CLRadii.sm),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: p.text3),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  onChanged: onChanged,
                  style: TextStyle(color: p.text, fontSize: 14),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: placeholder,
                    hintStyle: TextStyle(color: p.text3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -------- BrandPanel (used on auth screens) ----------------------------------

class CLBrandPanel extends StatelessWidget {
  const CLBrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(46, 44, 46, 44),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1C7DEF),
            Color(0xFF1257B0),
            Color(0xFF0E3F87),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -120,
            top: -120,
            child: Container(
              width: 420,
              height: 420,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x1AFFFFFF),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0x2EFFFFFF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Image.asset(
                      'assets/images/chatterloop.png',
                      color: Colors.white,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Chatterloop',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 420,
                    child: Text(
                      'A more visible way to stay connected.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -1.2,
                      ),
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'Link · Share · Explore',
                    style: TextStyle(
                      color: Color(0xD9FFFFFF),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Text(
                '© Neon Systems · ChatterLoop',
                style: TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
