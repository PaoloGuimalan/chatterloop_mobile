// Mirrors webapp's LinkPreviewCard.tsx "display" variant (the composer's
// removable-card variant doesn't apply here - this only renders already-
// persisted messages). Embeds (YouTube/Vimeo/SoundCloud/Spotify/TikTok/
// Twitter) now play inline via webview_flutter instead of opening
// externally, matching webapp's iframe-on-tap behavior; non-embed cards
// (a plain link with just an image/title/description) still open
// externally via url_launcher - webapp does the same, the whole card is
// just an <a> there.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/messages_models/link_preview_model.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// image/favicon come back as relative proxy paths (server's
/// build_image_proxy_path) except for the occasional data: URI - matches
/// LinkPreviewCard.tsx's resolveImageSrc.
String? _resolveImageSrc(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('data:')) {
    return path;
  }
  return '${Endpoints().userApiUrl}$path';
}

class LinkPreviewCard extends StatefulWidget {
  final LinkPreviewData? preview;

  const LinkPreviewCard({super.key, required this.preview});

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  bool _isPlaying = false;
  WebViewController? _controller;

  Future<void> _openExternally() async {
    final data = widget.preview;
    final target = data?.resolvedUrl ?? data?.url;
    if (target == null || target.isEmpty) return;
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _startPlaying() {
    final embedUrl = widget.preview?.embedUrl;
    if (embedUrl == null || embedUrl.isEmpty) return;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(embedUrl));
    setState(() {
      _controller = controller;
      _isPlaying = true;
    });
  }

  /// Matches LinkPreviewCard.tsx's mediaContainerStyle sizing rules exactly
  /// - see that file's comment for why each layout is shaped this way.
  double? _mediaHeight(LinkPreviewData data, double cardWidth) {
    switch (data.embedLayout) {
      case "landscape":
        return (data.embedHeight ?? 200).toDouble();
      case "portrait":
        final w = data.embedWidth ?? 9;
        final h = data.embedHeight ?? 16;
        final portraitWidth = cardWidth < 320 ? cardWidth : 320.0;
        return portraitWidth * h / w;
      default:
        final w = data.embedWidth ?? 16;
        final h = data.embedHeight ?? 9;
        return cardWidth * h / w;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final data = widget.preview;
    if (data == null || !data.isOk) return const SizedBox.shrink();

    final imageSrc = _resolveImageSrc(data.image);
    final faviconSrc = _resolveImageSrc(data.favicon);

    // Material wrapper is required, not decorative - InkWell needs a
    // Material ancestor to paint its ripple, and this widget also renders
    // inside flutter_chat_reactions' long-press preview (HeroDialogRoute),
    // which doesn't provide one on its own. Without this, holding a
    // message with a link preview crashed with "No Material widget found".
    return Material(
      color: Colors.transparent,
      child: Container(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: p.surface2,
          border: Border.all(color: p.border),
          borderRadius: BorderRadius.circular(CLRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final mediaHeight = data.hasEmbed
                  ? _mediaHeight(data, constraints.maxWidth)
                  : 160.0;
              if (data.hasEmbed && _isPlaying && _controller != null) {
                return SizedBox(
                  width: double.infinity,
                  height: mediaHeight,
                  child: WebViewWidget(controller: _controller!),
                );
              }
              if (data.hasEmbed) {
                return InkWell(
                  onTap: _startPlaying,
                  child: SizedBox(
                    width: double.infinity,
                    height: mediaHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      fit: StackFit.expand,
                      children: [
                        if (imageSrc != null)
                          CLNetworkImage(
                            src: imageSrc,
                            placeholderHeight: mediaHeight ?? 160,
                            errorBuilder: (_) => Container(color: Colors.black),
                          )
                        else
                          Container(color: Colors.black),
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.6),
                          ),
                          child: const Icon(Icons.play_arrow,
                              color: Colors.white, size: 26),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (imageSrc != null) {
                return InkWell(
                  onTap: _openExternally,
                  child: CLNetworkImage(
                    src: imageSrc,
                    width: double.infinity,
                    height: 160,
                    errorBuilder: (_) => const SizedBox.shrink(),
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
            // Only the info area links out for embeds - tapping the media
            // area plays instead of navigating, matching webapp exactly.
            // Non-embed cards keep the whole card as one tap target.
            InkWell(
              onTap: _openExternally,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (faviconSrc != null ||
                        (data.siteName?.isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (faviconSrc != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: Image.network(faviconSrc,
                                    width: 14,
                                    height: 14,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox(width: 14, height: 14)),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (data.siteName?.isNotEmpty ?? false)
                              Flexible(
                                child: Text(
                                  data.siteName!.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 0.4,
                                      color: p.text2),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (data.title?.isNotEmpty ?? false)
                      Text(
                        data.title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: p.text),
                      ),
                    if (data.description?.isNotEmpty ?? false)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          data.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.text2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
