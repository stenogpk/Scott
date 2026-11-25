// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../screens/call_break_page.dart';

class NewGamesCard extends StatelessWidget {
  const NewGamesCard({super.key});
  @override Widget build(BuildContext context)=>Card(
    clipBehavior:Clip.antiAlias,
    child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('NEW GAMES',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1.5)),
      const SizedBox(height:10),
      FilledButton.tonalIcon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CallBreakPage())),icon:const Icon(Icons.style),label:const Text('लकड़ी • CALL BREAK')),
      const SizedBox(height:8),
      Row(children:[for(int i=0;i<3;i++)Expanded(child:Container(height:42,margin:EdgeInsets.only(right:i==2?0:6),decoration:BoxDecoration(color:Theme.of(context).colorScheme.surfaceContainerHighest,borderRadius:BorderRadius.circular(9))))]),
    ])));
}
