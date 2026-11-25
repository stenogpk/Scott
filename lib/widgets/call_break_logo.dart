import 'package:flutter/material.dart';

/// Compact gold-and-maroon Call Break emblem, matching the approved game identity.
class CallBreakLogo extends StatelessWidget {
  const CallBreakLogo({super.key, this.size = 150, this.compact = false});
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return SizedBox(
        width: size, height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF32101F),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFD7A83D), width: 1.4),
          ),
          child: const Center(child: Icon(Icons.style_rounded, color: Color(0xFFE8C05D), size: 19)),
        ),
      );
    }
    return SizedBox(
      width: size, height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const RadialGradient(colors: [Color(0xFF65152B), Color(0xFF210D20)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE7B94C), width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 5))],
        ),
        child: Stack(alignment: Alignment.center, children: [
          Positioned(top: 8, left: 0, right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
              _MiniCard('A', Colors.black), _MiniCard('K', Color(0xFFB51F32)),
              _MiniCard('Q', Colors.black), _MiniCard('J', Color(0xFFB51F32)),
            ])),
          Positioned(top: size * .31, left: 7, right: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFFE18A), Color(0xFFB87916), Color(0xFFFFE18A)]),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFFFF0B0), width: 1),
              ),
              child: const Text('लकड़ी', textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF40121A), fontSize: 30, fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 2))])),
            )),
          Positioned(bottom: size * .19, left: 8, right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFFFFE9A5), Color(0xFFD49A2E), Color(0xFFFFE9A5)]),
              ),
              child: const Text('CALL BREAK', textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF3A101A), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: .6)),
            )),
          Positioned(bottom: 4, child: Icon(Icons.spa_rounded, size: size * .16, color: const Color(0xFFE4B64B)),
          ),
        ]),
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: label == 'A' ? -.22 : label == 'J' ? .22 : label == 'K' ? -.08 : .08,
    child: Container(
      width: 23, height: 33, margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: const Color(0xFFFFF5DB), borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFD8B86A))),
      child: Center(child: Text(label, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w900))),
    ),
  );
}
