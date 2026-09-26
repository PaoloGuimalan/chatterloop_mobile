"""Builds assets/images/watermark.png - the logo stamped into the corner of
every Moment the app encodes (lib/core/media/encoding_profile.dart,
Watermark) - from the full-size Chatterloop logo (the mark plus the white
wordmark, on transparency).

It trims the logo's empty margin, sizes it for the watermark, and bakes in
a soft dark shadow and a little transparency, so the white wordmark still
reads over a bright sky or a white wall. ffmpeg then only scales and
overlays it - with the filters the app's LGPL FFmpeg has.

Usage (from chatterloop_app/; needs Pillow):
  python tool/make_watermark.py path/to/chatterloop-logo.png
"""
import sys

from PIL import Image, ImageFilter

OUT = 'assets/images/watermark.png'

# About twice the size it is drawn at on a 1080-wide Moment (20% of the
# width), so a larger profile still gets a sharp downscale.
LOGO_WIDTH = 600
# The shadow, in pixels at LOGO_WIDTH: its blur, its drop, and how dark.
SHADOW_BLUR = 7.5
SHADOW_DROP = 3
SHADOW_ALPHA = 0.7
# Room around the logo for the shadow to fade out in.
PAD = 15
OPACITY = 0.9


def main(source):
    logo = Image.open(source).convert('RGBA')
    logo = logo.crop(logo.getchannel('A').getbbox())
    height = round(logo.height * LOGO_WIDTH / logo.width)
    logo = logo.resize((LOGO_WIDTH, height), Image.LANCZOS)

    size = (LOGO_WIDTH + 2 * PAD, height + 2 * PAD)
    shadow_alpha = Image.new('L', size, 0)
    shadow_alpha.paste(logo.getchannel('A'), (PAD, PAD + SHADOW_DROP))
    shadow_alpha = shadow_alpha.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))
    shadow_alpha = shadow_alpha.point(lambda a: round(a * SHADOW_ALPHA))
    out = Image.new('RGBA', size, (0, 0, 0, 0))
    out.putalpha(shadow_alpha)
    out.alpha_composite(logo, (PAD, PAD))

    alpha = out.getchannel('A').point(lambda a: round(a * OPACITY))
    out.putalpha(alpha)
    # Fully transparent pixels carry no colour (a smaller file, and nothing
    # odd if a scaler blends into them).
    clear = alpha.point(lambda a: 255 if a == 0 else 0)
    out = Image.composite(Image.new('RGBA', size, (0, 0, 0, 0)), out, clear)
    # No metadata - the source's Photoshop XMP and EXIF stay behind.
    out.save(OUT, optimize=True)
    print(OUT, '%dx%d' % out.size)


if __name__ == '__main__':
    main(sys.argv[1])
