import 'package:flutter/material.dart';

void main() {
  runApp(const ScottApp());
}

class ScottApp extends StatelessWidget {
  const ScottApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF142B45);
    const teal = Color(0xFF16A6A1);
    return MaterialApp(
      title: 'SCOTT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: teal,
          brightness: Brightness.light,
          primary: navy,
          secondary: teal,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F6F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
      ),
      home: const ScottHomePage(),
    );
  }
}

class ScottHomePage extends StatelessWidget {
  const ScottHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SCOTT', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF142B45), Color(0xFF245B7A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.style_rounded, color: Colors.white, size: 62),
                        SizedBox(height: 12),
                        Text(
                          'हर चाल में दिमाग, हर राउंड में मज़ा!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '2–5 खिलाड़ियों का रणनीति वाला कार्ड गेम',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _ModeStatusCard(
                    icon: Icons.public,
                    title: 'Online Multiplayer',
                    subtitle: 'नाम और Room Code से दोस्तों के साथ खेलें',
                    status: 'निर्माण जारी है',
                  ),
                  const SizedBox(height: 12),
                  const _ModeStatusCard(
                    icon: Icons.wifi,
                    title: 'Local Wi-Fi Multiplayer',
                    subtitle: 'एक ही Wi-Fi या Hotspot पर, बिना इंटरनेट',
                    status: 'निर्माण जारी है',
                  ),
                  const SizedBox(height: 12),
                  const _ModeStatusCard(
                    icon: Icons.smart_toy_outlined,
                    title: 'Bot Play',
                    subtitle: 'अकेले खेलने के लिए कंप्यूटर खिलाड़ी',
                    status: 'बाद के अपडेट में — वैकल्पिक',
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'SCOTT में Pass & Play शामिल नहीं है। हर खिलाड़ी के निजी कार्ड सुरक्षित रहेंगे।',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF526273), height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Developed by Shartendu',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF6B7B89), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeStatusCard extends StatelessWidget {
  const _ModeStatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE1E8ED)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFE7F5F4),
              foregroundColor: const Color(0xFF168B87),
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Color(0xFF667685), fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status,
              style: const TextStyle(color: Color(0xFF8A641D), fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
