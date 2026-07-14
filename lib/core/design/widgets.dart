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
              errorBuilder: (_, __, ___) => placeholder,
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
