# SCOTT

SCOTT is a 2–5 player Android card game with custom rules and two multiplayer transports.

## Play modes
- **Online Multiplayer:** guest name + 6-character room code, using Firebase Anonymous Authentication and Realtime Database.
- **Local Wi-Fi Multiplayer:** one phone hosts a room; friends join by host IP and room code over the same Wi-Fi or hotspot. Internet is not required.
- Pass & Play is intentionally not included.

## Game rules implemented
- Standard 52-card deck, no jokers; suits do not affect score.
- A=1, 2–8 face value, 9=0, 10=10, J=11, Q=12, K=13.
- A 9 can never be discarded.
- Single card or same-rank pair/triple/quad can be discarded; exactly one card is drawn afterward.
- Draw from the face-down pile or take one card from the immediately previous active player's latest discard group.
- If the draw pile is empty, the face-up discard pile is shuffled into a new draw pile.
- SHOW is selected at the start of a turn, before changing cards. A zero-total hand triggers Automatic SHOW.
- Successful SHOW requires the caller's hand total to be strictly lower than every other active player's total. Caller gets 0; others add their own hand totals.
- Failed SHOW adds the sum of all active hand totals to the caller only.
- Every hand is revealed after SHOW. Players are eliminated at score >= target. Permanent label: **ससम्मान बाहेर 😂**.
- Last active player wins. Cumulative scoreboard and round history are retained for the game.

## Multiplayer security
- The room host is authoritative for game actions and scoring.
- During a live round, only each player can read their own private hand. The host publishes public scores/turn/discard state separately.
- All hands become public only after a SHOW.
- Firebase Realtime Database rules are provided in firebase/database.rules.json.

## Firebase setup for Online Multiplayer
Create a dedicated Firebase project for SCOTT, enable **Authentication → Anonymous** and **Realtime Database**, then publish the rules from firebase/database.rules.json.

Add these GitHub repository Actions secrets:
- FIREBASE_API_KEY — Firebase Web API key.
- FIREBASE_DATABASE_URL — Realtime Database URL shown in Firebase Console.

The release workflow reads these secrets at build time. They are not committed to this repository. Local Wi-Fi play does not require Firebase.

## Build
The GitHub Actions workflow generates original sound effects, runs flutter analyze and flutter test, then builds a release APK. APKs are uploaded as workflow artifacts, never committed to Git.

## Developer
Developed by Shartendu.
