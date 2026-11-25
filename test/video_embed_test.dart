import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/widgets/video_player_page.dart';

void main() {
  test('YouTube, Shorts, Instagram, TikTok en Vimeo worden insluitbaar', () {
    expect(embedUrl('https://youtu.be/abc123'), startsWith('https://www.youtube.com/embed/abc123'));
    expect(embedUrl('https://www.youtube.com/watch?v=xyz&t=10'), startsWith('https://www.youtube.com/embed/xyz'));
    expect(embedUrl('https://youtube.com/shorts/SHORT1'), startsWith('https://www.youtube.com/embed/SHORT1'));
    expect(embedUrl('https://www.instagram.com/reel/C0de/?igsh=1'), 'https://www.instagram.com/reel/C0de/embed');
    expect(embedUrl('https://www.tiktok.com/@judo/video/7312345'), 'https://www.tiktok.com/embed/v2/7312345');
    expect(embedUrl('https://vimeo.com/123456'), startsWith('https://player.vimeo.com/video/123456'));
    expect(embedUrl('https://photos.app.goo.gl/abc'), isNull);
  });
}
