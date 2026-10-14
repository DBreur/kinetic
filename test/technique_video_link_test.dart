import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/widgets/inline_video_player.dart';

void main() {
  testWidgets(
    'een lege of ongeldige videolink toont een foutmelding in plaats van te '
    'crashen',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InlineVideoPlayer(url: '   ')),
        ),
      );
      await tester.pump();

      expect(find.text('Ongeldige videolink.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  group('videoEmbedUri', () {
    test('zet een YouTube watch-link om naar de embed-URL', () {
      final result = videoEmbedUri(
        Uri.parse('https://www.youtube.com/watch?v=abc123'),
      );
      expect(result.toString(), 'https://www.youtube.com/embed/abc123');
    });

    test('zet een youtu.be-kortlink om naar de embed-URL', () {
      final result = videoEmbedUri(Uri.parse('https://youtu.be/abc123'));
      expect(result.toString(), 'https://www.youtube.com/embed/abc123');
    });

    test(
      'laat een TikTok-videolink ongewijzigd (embed heeft lagere kwaliteit '
      'dan de gewone kijkpagina)',
      () {
        final uri = Uri.parse(
          'https://www.tiktok.com/@someuser/video/1234567890123456789',
        );
        expect(videoEmbedUri(uri), uri);
      },
    );

    test('zet een Instagram post-link om naar de embed-URL', () {
      final result = videoEmbedUri(
        Uri.parse('https://www.instagram.com/p/AbC123xyz/'),
      );
      expect(result.toString(), 'https://www.instagram.com/p/AbC123xyz/embed/');
    });

    test('zet een Instagram reel-link om naar de embed-URL', () {
      final result = videoEmbedUri(
        Uri.parse('https://www.instagram.com/reel/AbC123xyz/'),
      );
      expect(result.toString(), 'https://www.instagram.com/reel/AbC123xyz/embed/');
    });

    test('zet een Instagram /reels/-link ook om naar de /reel/-embed-URL', () {
      final result = videoEmbedUri(
        Uri.parse('https://www.instagram.com/reels/AbC123xyz/'),
      );
      expect(result.toString(), 'https://www.instagram.com/reel/AbC123xyz/embed/');
    });

    test(
      'laat onbekende bronnen ongewijzigd (bv. Google Drive, directe video)',
      () {
        final uri = Uri.parse('https://drive.google.com/file/d/xyz/preview');
        expect(videoEmbedUri(uri), uri);
      },
    );
  });

  group('CollapsibleVideoList', () {
    testWidgets(
      'toont ook bij precies één video de titelbalk, meteen opengeklapt',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: CollapsibleVideoList(urls: ['   '])),
          ),
        );
        await tester.pump();

        expect(find.text('Video 1'), findsOneWidget);
        expect(find.text('Ongeldige videolink.'), findsOneWidget);

        await tester.tap(find.text('Video 1'));
        await tester.pump();

        expect(find.text('Ongeldige videolink.'), findsNothing);
      },
    );

    testWidgets(
      'begint ingeklapt bij meerdere video\'s en klapt open bij een tik',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: CollapsibleVideoList(urls: ['   ', '   '])),
          ),
        );
        await tester.pump();

        expect(find.text('Video 1'), findsOneWidget);
        expect(find.text('Video 2'), findsOneWidget);
        expect(find.text('Ongeldige videolink.'), findsNothing);

        await tester.tap(find.text('Video 1'));
        await tester.pump();

        expect(find.text('Ongeldige videolink.'), findsOneWidget);
      },
    );
  });
}
