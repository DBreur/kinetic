// info_sheet.dart — uitleg bij een oefening of circuit tijdens een training:
// de beschrijving plus de video's, in een sheet die je weer wegveegt.

import 'package:flutter/material.dart';

import '../theme/kinetic_theme.dart';
import '../models/agenda.dart' show normalizeUrl;
import 'inline_video_player.dart';
import 'video_link_row.dart' show editVideoLabel;

/// [onAddVideo]: als gezet kun je hier een video-link toevoegen; die wordt
/// meteen in de lijst getoond zodra hij bewaard is.
Future<void> showInfoSheet(
  BuildContext context, {
  required String title,
  String description = '',
  List<String> videoUrls = const [],
  Future<void> Function(String url)? onAddVideo,
}) {
  var urls = List.of(videoUrls);
  final input = TextEditingController();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: urls.isEmpty ? .4 : .75,
      minChildSize: .25,
      maxChildSize: .95,
      builder: (c, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(c).padding.bottom,
        ),
        children: [
          Text(title, style: AppText.title),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: AppText.body.copyWith(color: AppColor.inkMuted),
            ),
          ],
          if (urls.isNotEmpty) ...[
            const SizedBox(height: 16),
            CollapsibleVideoList(urls: urls),
          ],
          if (onAddVideo != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    keyboardType: TextInputType.url,
                    style: AppText.body,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Video toevoegen: plak een link',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Video toevoegen',
                  icon: const Icon(Icons.add_link, color: AppColor.ice),
                  onPressed: () async {
                    final url = normalizeUrl(input.text);
                    if (url.isEmpty) return;
                    input.clear();
                    await onAddVideo(url);
                    if (!c.mounted) return;
                    setState(() => urls = [...urls, url]);
                    await editVideoLabel(c, url);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    ),
    ),
  );
}
