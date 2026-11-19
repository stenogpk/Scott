import 'package:flutter/material.dart';
import '../game/playing_card.dart';

class ScottRulesPage extends StatefulWidget {
  const ScottRulesPage({super.key});
  @override
  State<ScottRulesPage> createState() => _ScottRulesPageState();
}

class _ScottRulesPageState extends State<ScottRulesPage> {
  bool _english = false;

  String t(String hi, String en) => _english ? en : hi;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('SCOTT के खेल के नियम', 'How to Play SCOTT')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('हिंदी')),
                ButtonSegment(value: true, label: Text('EN')),
              ],
              selected: {_english},
              onSelectionChanged: (value) => setState(() => _english = value.first),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _intro(),
            const SizedBox(height: 14),
            _section('🎯', t('खेल का उद्देश्य', 'Objective'), [
              t('अपने पाँच पत्तों का कुल जोड़ कम रखें। सही समय पर SHOW करके राउंड में शून्य अंक पाने की कोशिश करें। लक्ष्य स्कोर तक पहुँचने वाले खिलाड़ी बाहर हो जाते हैं।', 'Keep the total value of your five cards low. Call SHOW at the right time to score zero for the round. Players are eliminated when they reach the target score.')
            ]),
            _section('👥', t('खिलाड़ी और शुरुआत', 'Players and Setup'), [
              t('एक खेल में 2 से 5 खिलाड़ी खेलते हैं। 52 पत्तों की गड्डी इस्तेमाल होती है। हर सक्रिय खिलाड़ी को शुरुआत में 5 पत्ते मिलते हैं। लक्ष्य स्कोर 100, 150, 200 या कमरे में तय किया गया स्कोर हो सकता है।', 'A game has 2 to 5 players and uses a standard 52-card deck. Each active player starts with 5 cards. The target score can be 100, 150, 200, or the score selected for the room.')
            ]),
            _section('🃏', t('पत्तों की कीमत', 'Card Values'), [
              t('A का मान 1 है। 2 से 8 तक पत्ते अपने नंबर के बराबर हैं। 9 यानी नौकी का मान 0 है। 10 का मान 10, J का 11, Q का 12 और K का 13 है।', 'Ace is worth 1. Cards 2 through 8 are worth their face value. 9 is worth 0. 10 is worth 10, Jack 11, Queen 12, and King 13.')
            ], child: _cardValues()),
            _section('🔄', t('आपकी बारी कैसे चलेगी?', 'How a Turn Works'), [
              t('अपनी बारी में एक पत्ता या एक ही नंबर के कई पत्ते चुनकर फेंकें। फिर Draw Pile से 1 पत्ता लें या तुरंत पिछले सक्रिय खिलाड़ी के फेंके गए समूह से उपलब्ध 1 पत्ता लें। इसके बाद अगली बारी अगले सक्रिय खिलाड़ी की होगी।', 'On your turn, discard one card or multiple cards of the same rank. Then draw exactly one card from the Draw Pile or take one available card from the immediately previous active player’s latest discard group. The next active player then takes a turn.')
            ], child: _turnFlow()),
            _section('🚫', t('पत्ते फेंकने के नियम', 'Discard Rules'), [
              t('एक बार में केवल एक पत्ता या एक ही रैंक के पत्तों का समूह फेंक सकते हैं। अलग-अलग नंबर के पत्ते एक साथ नहीं फेंक सकते। 9 (नौकी) कभी फेंका नहीं जा सकता। फेंकने के बाद एक ही पत्ता उठाना होता है।', 'You may discard one card or a group of cards of the same rank only. Different ranks cannot be discarded together. A 9 can never be discarded. After discarding, draw exactly one card.')
            ]),
            _section('♻️', t('Draw Pile खत्म हो जाए तो?', 'When the Draw Pile Runs Out'), [
              t('जब Draw Pile खाली हो जाए, तो उपलब्ध खुले फेंके गए पत्तों को मिलाकर फिर से शफल किया जाता है और उनसे नया Draw Pile बनाया जाता है।', 'When the Draw Pile becomes empty, the available discard pile is shuffled to form a new Draw Pile.')
            ]),
            _section('📣', t('SHOW कब कर सकते हैं?', 'When Can You Call SHOW?'), [
              t('SHOW केवल अपनी बारी की शुरुआत में कर सकते हैं—पत्ता फेंकने या उठाने से पहले। आपका हाथ का कुल जोड़ बाकी सभी सक्रिय खिलाड़ियों से सख्ती से कम होना चाहिए। बराबर होने पर SHOW सफल नहीं होगा।', 'You can call SHOW only at the beginning of your turn, before discarding or drawing. Your hand total must be strictly lower than every other active player’s total. A tie is not a successful SHOW.')
            ]),
            _section('🟢', t('सफल SHOW', 'Successful SHOW'), [
              t('यदि आपका कुल जोड़ बाकी सभी सक्रिय खिलाड़ियों से कम है, तो SHOW सफल है। आपको 0 अंक मिलेंगे और बाकी हर सक्रिय खिलाड़ी को अपने हाथ के कुल जोड़ के बराबर अंक मिलेंगे।', 'If your total is lower than every other active player, SHOW succeeds. You receive 0 points, and each other active player receives points equal to their own hand total.')
            ]),
            _section('🔴', t('असफल SHOW', 'Failed SHOW'), [
              t('यदि किसी भी सक्रिय खिलाड़ी का जोड़ आपके बराबर या आपसे कम है, तो SHOW असफल है। ऐसी स्थिति में आपके खाते में सभी सक्रिय खिलाड़ियों के हाथ के कुल जोड़ का योग जुड़ता है। बाकी खिलाड़ियों को इस SHOW में 0 अंक मिलते हैं।', 'If any active player has a total equal to or lower than yours, SHOW fails. The sum of all active players’ hand totals is added to your score. The other players receive 0 points for that SHOW.')
            ]),
            _section('🧮', t('अंक और खिलाड़ी का बाहर होना', 'Scoring and Elimination'), [
              t('हर राउंड के बाद मिले अंक खिलाड़ी के कुल स्कोर में जुड़ते हैं। जो खिलाड़ी तय लक्ष्य स्कोर तक पहुँचता है या उससे ऊपर जाता है, वह खेल से बाहर हो जाता है। उसका स्टेटस “ससम्मान बाहेर 😂” दिखेगा।', 'After each round, earned points are added to each player’s total score. A player who reaches or exceeds the target score is eliminated. Their status is shown as “ससम्मान बाहेर 😂”.')
            ]),
            _section('🏆', t('जीत किसकी होगी?', 'Who Wins?'), [
              t('राउंड खत्म होने के बाद यदि केवल एक सक्रिय खिलाड़ी बचता है, वही SCOTT का विजेता होता है।', 'After a round, if only one active player remains, that player wins SCOTT.')
            ]),
            _section('⚡', t('अपने आप SHOW', 'Automatic SHOW'), [
              t('कुछ स्थितियों में गेम अपने आप SHOW का परिणाम निकाल सकता है—जैसे किसी खिलाड़ी के हाथ का कुल जोड़ 0 हो जाए। ऐसे परिणाम को गेम स्क्रीन पर Automatic SHOW के रूप में दिखाया जाता है।', 'In certain situations the game can resolve SHOW automatically—for example, when a player’s hand total becomes 0. The result is identified as an Automatic SHOW.')
            ]),
            _section('💡', t('याद रखने वाली बातें', 'Quick Reminders'), [
              t('9 शून्य अंक देता है, लेकिन फेंका नहीं जा सकता। एक साथ फेंके गए सभी पत्ते एक ही नंबर के होने चाहिए। SHOW अपनी बारी की शुरुआत में ही करें। सफल SHOW के लिए आपका जोड़ सभी सक्रिय खिलाड़ियों से कम होना जरूरी है।', 'A 9 is worth zero but cannot be discarded. All cards discarded together must have the same rank. Call SHOW only at the start of your turn. For a successful SHOW, your total must be lower than every active player.')
            ]),
            const SizedBox(height: 18),
            const Center(child: Text('Developed by Shartendu', style: TextStyle(color: Color(0xFF71808C), fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }

  Widget _intro() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF142B45), Color(0xFF247A83)]),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(children: [
      const Icon(Icons.style_rounded, color: Colors.white, size: 42),
      const SizedBox(height: 8),
      Text(t('सीखें, खेलें और जीतें!', 'Learn, Play and Win!'),
        style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      Text(t('कुछ आसान नियम और आप तैयार हैं।', 'A few simple rules are all you need.'),
        style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
    ]),
  );

  Widget _section(String icon, String title, List<String> paragraphs, {Widget? child}) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE0E7EC))),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Text(icon, style: const TextStyle(fontSize: 22)), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)))]),
        const SizedBox(height: 9),
        for (final paragraph in paragraphs) Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(paragraph, style: const TextStyle(height: 1.45))),
        if (child != null) ...[const SizedBox(height: 10), child],
      ]),
    ),
  );

  Widget _cardValues() => Wrap(
    spacing: 8, runSpacing: 8,
    children: [
      for (final rank in CardRank.values)
        Container(
          width: 58, padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFD8E0E6)), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(rank.shortLabel, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: rank == CardRank.nine ? Colors.green : const Color(0xFF18232D))),
            Text('${rank.value} अंक', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
            Text(rank == CardRank.nine ? 'फेंकना मना' : '♥ ♦ ♣ ♠', style: const TextStyle(fontSize: 8, color: Colors.blueGrey)),
          ]),
        ),
    ],
  );

  Widget _turnFlow() => Row(children: [
    Expanded(child: _step(Icons.style, t('पत्ता फेंकें', 'Discard'), '1')),
    const Icon(Icons.arrow_forward, color: Colors.blueGrey),
    Expanded(child: _step(Icons.add_box_outlined, t('एक पत्ता लें', 'Draw one'), '2')),
    const Icon(Icons.arrow_forward, color: Colors.blueGrey),
    Expanded(child: _step(Icons.skip_next, t('अगली बारी', 'Next turn'), '3')),
  ]);

  Widget _step(IconData icon, String label, String number) => Column(children: [
    CircleAvatar(backgroundColor: const Color(0xFFE5F4F2), foregroundColor: const Color(0xFF168B87), child: Icon(icon)),
    const SizedBox(height: 5),
    Text(number, style: const TextStyle(fontWeight: FontWeight.w900)),
    Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
  ]);
}
