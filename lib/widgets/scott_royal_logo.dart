import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reuses the exact SCOTT Royal logo already used by the Android launcher.
class ScottRoyalLogo extends StatefulWidget {
  const ScottRoyalLogo({super.key, this.size = 112});
  final double size;

  @override
  State<ScottRoyalLogo> createState() => _ScottRoyalLogoState();
}

class _ScottRoyalLogoState extends State<ScottRoyalLogo> {
  late final Future<Uint8List> _bytes = rootBundle
      .loadString('assets/scott_launcher.png')
      .then((encoded) => Uint8List.fromList(base64Decode(encoded.trim())));

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            return Image.memory(snapshot.data!, width: widget.size,
                height: widget.size, fit: BoxFit.contain,
                filterQuality: FilterQuality.high, gaplessPlayback: true);
          },
        ),
      );
}
