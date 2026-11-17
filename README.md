# SCOTT

SCOTT is a 2–5 player playing-card game with custom rules.

## Planned play modes
- Online multiplayer: guest name + room code; no account creation in the UI.
- Local Wi-Fi multiplayer: works without internet, using one phone as the room host.
- Bot Play: optional later feature. It must not delay the two multiplayer modes.
- Pass & Play is not part of the app.

## Current development status
This repository is being built from a clean Flutter foundation. The first implementation stage contains the deterministic rules engine, automated tests, and Android CI build. Online and Local Wi-Fi transports are separate follow-up stages.

## Fixed rules
- 2–5 players; 52 cards; no jokers; suits do not affect card value.
- A=1, 2–8 face value, 9=0, 10=10, J=11, Q=12, K=13.
- A 9 can never be discarded.
- A turn begins with SHOW or change cards. Changing cards means discard first, then draw exactly one card.
- A single card or a same-rank group can be discarded. A group still draws only one card.
- The draw can come from the face-down pile or one card from the immediately previous player's latest discard group.
- A hand total of zero triggers Automatic SHOW.
- SHOW succeeds only when the caller's total is strictly lower than every other active player's total.
- Successful SHOW: caller gets 0; each other active player gets their own hand total.
- Failed SHOW: caller receives the sum of all active players' hand totals; others receive 0.
- A player is eliminated at score >= target. Permanent label: ससम्मान बाहेर 😂.
- Last remaining active player wins.

## Build
GitHub Actions runs flutter analyze, flutter test, and creates a debug APK artifact on pushes and pull requests.

## Developer note
Some discard-pile reshuffle and round-start details remain unresolved in the Master Blueprint. Do not silently invent those rules while implementing them.
