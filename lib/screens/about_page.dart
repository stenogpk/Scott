import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const email = 'theshartendu@gmail.com';

  Future<void> _contact(BuildContext context) async {
    final uri = Uri(scheme: 'mailto', path: email, queryParameters: {
      'subject': 'SCOTT - Feedback',
    });
    if (!await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ईमेल ऐप नहीं खुल सका। आप ईमेल पता कॉपी कर सकते हैं।')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About SCOTT')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFD6A83D), width: 2),
              ),
              child: const Column(children: [
                Icon(Icons.style_rounded, size: 64, color: Color(0xFFFFD56A)),
                SizedBox(height: 10),
                Text('SCOTT', style: TextStyle(color: Color(0xFFFFD56A), fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4)),
                Text('A MULTI-GAME PLATFORM', style: TextStyle(color: Colors.white70, letterSpacing: 1.5)),
              ]),
            ),
            const SizedBox(height: 22),
            const Text('SCOTT is an independent personal gaming project created to bring people together through fun, friendly and engaging games.', style: TextStyle(fontSize: 16, height: 1.5)),
            const SizedBox(height: 18),
            const Text('Developed by Shartendu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('SCOTT is not owned or operated by any company or organization. It is independently developed and maintained by Shartendu.', style: TextStyle(height: 1.5)),
            const SizedBox(height: 24),
            const Text('Contact & Feedback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('For suggestions, feedback, bug reports or any queries, feel free to contact:'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _contact(context),
              icon: const Icon(Icons.email_outlined),
              label: const Text(email),
            ),
          ],
        ),
      ),
    ),
  );
}
