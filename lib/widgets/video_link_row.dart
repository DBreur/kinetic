// video_link_row.dart — één toegevoegde video in een editor (techniek,
// combinatie, oefening, circuit): de eigen naam (of de link als die er nog
// niet is), een knop om de naam te geven/aan te passen en een
// verwijderknop. Namen staan in VideoLabels en gelden overal.

import 'package:flutter/material.dart';

import '../services/video_labels.dart';
import '../theme/kinetic_theme.dart';

/// Vraagt een naam voor [url] en bewaart die. Leeg maken wist de naam.
Future<void> editVideoLabel(BuildContext context, String url) async {
  final controller = TextEditingController(text: VideoLabels.labelOf(url));
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Naam van de video', style: AppText.cardTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            url.replaceFirst(RegExp(r'^https?://'), ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            autofocus: true,
            style: AppText.body,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Bv. "Instap" of "Detail grip"',
            ),
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Annuleer'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, controller.text),
          child: const Text('Opslaan'),
        ),
      ],
    ),
  );
  if (result != null) await VideoLabels.setLabel(url, result);
}

class VideoLinkRow extends StatelessWidget {
  const VideoLinkRow({super.key, required this.url, required this.onRemove});

  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: VideoLabels.labels,
      builder: (context, labels, _) {
        final label = labels[url.trim()];
        final shortUrl = url.replaceFirst(RegExp(r'^https?://(www\.)?'), '');
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(
            color: AppColor.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.play_circle_outline,
                size: 18,
                color: AppColor.ice,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => editVideoLabel(context, url),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label ?? 'Naam geven',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: label != null
                              ? AppText.bodyStrong
                              : AppText.body.copyWith(color: AppColor.ice),
                        ),
                        Text(
                          shortUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Naam aanpassen',
                visualDensity: VisualDensity.compact,
                onPressed: () => editVideoLabel(context, url),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppColor.inkFaint,
                ),
              ),
              IconButton(
                tooltip: 'Verwijderen',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(
                  Icons.close,
                  size: 16,
                  color: AppColor.inkFaint,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
