import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// Escudo AV con alas.
class Emblem extends StatelessWidget {
  const Emblem({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/emblema.png',
    width: size,
    height: size,
    errorBuilder: (_, _, _) => Icon(Icons.shield, size: size),
  );
}

/// Mascota Aguilucho.
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.height = 150});
  final double height;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/brand/aguilucho.svg',
    height: height,
    placeholderBuilder: (_) => SizedBox(height: height),
  );
}

/// "AGUILERA / VALENCIA" con degradado, junto al escudo.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.emblem = 44, this.subtitle});
  final double emblem;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Emblem(size: emblem),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF5D0FE), Brand.violet],
            ).createShader(r),
            child: Text(
              'AGUILERA',
              style: TextStyle(
                fontSize: emblem * .42,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Colors.white,
                height: 1,
              ),
            ),
          ),
          Text(
            'VALENCIA',
            style: TextStyle(
              fontSize: emblem * .24,
              fontWeight: FontWeight.w300,
              letterSpacing: 4,
              color: const Color(0xFFE9D5FF),
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 10, color: Brand.dim),
            ),
        ],
      ),
    ],
  );
}

/// Tarjeta con borde y brillo morado.
class NeonCard extends StatelessWidget {
  const NeonCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.glow = false,
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool glow;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Brand.panel2, Brand.panel],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: glow ? Brand.violet : Brand.line),
      boxShadow: glow ? Brand.glow() : null,
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

/// Número en círculo con degradado neón.
class NeonNumber extends StatelessWidget {
  const NeonNumber(this.n, {super.key});
  final int n;

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: Brand.neon,
      boxShadow: Brand.glow(Brand.magenta, .6),
    ),
    child: Text(
      '$n',
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );
}
