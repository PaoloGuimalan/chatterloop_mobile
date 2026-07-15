// Mirrors webapp's LinkPreviewCard.tsx "display" variant (the composer's
// removable-card variant doesn't apply here - this only renders already-
// persisted messages). Embeds (YouTube/Vimeo/etc.) open externally instead
// of playing inline via iframe, since that needs a WebView dependency this
// app doesn't otherwise carry.

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/utils/endpoints.dart';
import 'package:chatterloop_app/models/messages_models/link_preview_model.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

class LinkPreviewCard extends StatelessWidget {
  final LinkPreviewData? preview;

  const LinkPreviewCard({super.key, required this.preview});

  Future<void> _open() async {
    final target = preview?.resolvedUrl ?? preview?.url;
    if (target == null || target.isEmpty) return;
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final data = preview;
    if (data == null || !data.isOk) return const SizedBox.shrink();

    final imageSrc = _resolveImageSrc(data.image);
    final faviconSrc = _resolveImageSrc(data.favicon);

    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(CLRadii.md),
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
            if (data.hasEmbed)
              Stack(
                alignment: Alignment.center,
                children: [
                  if (imageSrc != null)
                    Image.network(
                      imageSrc,
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(height: 160, color: p.surface3),
                    )
                  else
                    Container(height: 160, color: Colors.black),
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
              )
            else if (imageSrc != null)
              Image.network(
                imageSrc,
                width: double.infinity,
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Padding(
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
          ],
        ),
      ),
    );
  }
}
