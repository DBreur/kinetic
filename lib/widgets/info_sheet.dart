// info_sheet.dart — uitleg bij een oefening of circuit tijdens een training:
// de beschrijving plus de video's, in een sheet die je weer wegveegt.

import 'package:flutter/material.dart';

import '../theme/kinetic_theme.dart';
import 'inline_video_player.dart';

Future<void> showInfoSheet(
  BuildContext context, {
  required String title,
  String description = '',
  List<String> videoUrls = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: videoUrls.isEmpty ? .4 : .75,
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
          if (videoUrls.isNotEmpty) ...[
            const SizedBox(height: 16),
            CollapsibleVideoList(urls: videoUrls),
          ],
        ],
      ),
    ),
  );
}
