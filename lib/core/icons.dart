import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Icon names bundled in assets/icons (Streamline "Mingcute" Line + Fill, CC BY 4.0).
/// Use these constants instead of raw strings so a typo is a compile error.
abstract final class Ic {
  // Navigation
  static const home = 'home', homeFill = 'home_fill';
  static const cards = 'cards', cardsFill = 'cards_fill';
  static const moonStars = 'moon_stars', moonStarsFill = 'moon_stars_fill';
  static const hand = 'hand', handFill = 'hand_fill';
  static const user = 'user', userFill = 'user_fill';
  // Mystic
  static const moon = 'moon', moonFill = 'moon_fill', fullMoon = 'full_moon';
  static const crystalBall = 'crystal_ball';
  static const sparkles = 'sparkles', sparkles2 = 'sparkles2', sparklesFill = 'sparkles_fill';
  static const magic = 'magic', magicHat = 'magic_hat';
  static const star = 'star', starFill = 'star_fill';
  static const sun = 'sun';
  static const spade = 'spade';
  static const compass = 'compass';
  static const eye = 'eye', eyeClose = 'eye_close';
  // Topics
  static const heart = 'heart', heartFill = 'heart_fill', handHeart = 'hand_heart', userHeart = 'user_heart';
  static const briefcase = 'briefcase';
  static const lotus = 'lotus', flower = 'flower', leaf = 'leaf', mountain = 'mountain';
  static const crown = 'crown', crownFill = 'crown_fill';
  static const gift = 'gift';
  // Actions & system
  static const arrowRight = 'arrow_right', arrowLeft = 'arrow_left', right = 'right', left = 'left';
  static const close = 'close', check = 'check', checkCircle = 'check_circle', checkCircleFill = 'check_circle_fill';
  static const add = 'add', edit = 'edit', pencil = 'pencil', delete = 'delete';
  static const search = 'search', send = 'send', chat = 'chat', message = 'message', thought = 'thought';
  static const history = 'history', time = 'time', calendar = 'calendar', cake = 'cake';
  static const bookmark = 'bookmark', bookmarkFill = 'bookmark_fill', book = 'book', book2 = 'book2';
  static const lock = 'lock', lockFill = 'lock_fill', shield = 'shield';
  static const exit = 'exit', door = 'door';
  static const share = 'share', download = 'download', camera = 'camera', pic = 'pic';
  static const refresh = 'refresh', info = 'info', question = 'question', bulb = 'bulb';
  static const mail = 'mail', translate = 'translate', flash = 'flash', transfer = 'transfer';
  static const quote = 'quote', grid = 'grid', settings = 'settings';
  static const location = 'location', group = 'group';
}

/// Tintable SVG icon from assets/icons.
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.size = 22, this.color, this.semanticLabel});
  final String name;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/icons/$name.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color ?? IconTheme.of(context).color ?? Colors.white, BlendMode.srcIn),
        semanticsLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
      );
}

/// Icon on a soft tinted rounded tile — replaces emoji "bullets" in cards and lists.
class IconBadge extends StatelessWidget {
  const IconBadge(this.name, {super.key, this.color, this.size = 40, this.circle = false});
  final String name;
  final Color? color;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFFC8B8FF);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.32),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Center(child: AppIcon(name, size: size * 0.5, color: c)),
    );
  }
}
