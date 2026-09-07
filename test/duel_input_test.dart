import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_battle/api/duel_models.dart';
import 'package:word_battle/api/models.dart';
import 'package:word_battle/screens/duel_screen.dart';
import 'package:word_battle/screens/win_screen.dart';
import 'package:word_battle/theme.dart';
import 'package:word_battle/widgets/primary_button.dart';

/// The duel screen's input bar and its chain, on the two things that cost the
/// player seconds of a fifteen-second turn.
///
/// Both defects were the same fault seen twice. The word field carried
/// `enabled: duel.yourTurn`, so sending a word disabled it, the framework
/// unfocused a field that could no longer request focus, and Android took the
/// keyboard down with the focus. That is the first defect on its own — the
/// player had to tap the field again before every word. The second followed
/// from it: putting the keyboard back takes about 380 design-pixels out of the
/// chain's viewport, a `ListView` is not re-anchored when its viewport shrinks,
/// and the opponent's freshly-arrived word slid out of sight below the fold.
///
/// What a widget test can prove here is the wiring: which frames reach the
/// platform's text input, what is sent and when, and where the scroll offset
/// ends up. It cannot prove what Android's own keyboard animation does with
/// them, so the feel of a real turn still has to be watched on a phone.

const _me = UserDto(
  id: 1,
  nickname: 'jasur_07',
  displayName: 'jasur_07',
  initial: 'J',
  city: 'Andijon',
  rating: 1284,
  streakDays: 7,
);

const _opponent = UserDto(
  id: 2,
  nickname: 'malika_x',
  displayName: 'malika_x',
  initial: 'M',
  city: 'Toshkent',
  rating: 1301,
  streakDays: 0,
);

DuelView _duel({required bool yourTurn, int words = 1}) => DuelView(
      duelId: 'duel-1',
      opponent: _opponent,
      rated: true,
      theme: null,
      chain: [
        for (var i = 0; i < words; i++)
          ChainWord(word: 'word${i.toString().padLeft(2, '0')}', mine: i.isOdd, spentMs: 1800),
      ],
      yourTurn: yourTurn,
      needLetter: 'W',
      substitutedFrom: null,
      substitutionReason: null,
      timeLeftMs: 12000,
      turnSeconds: 15,
      yourWords: 1,
      opponentWords: 1,
      opponentThinking: !yourTurn,
    );

/// The app's canvas: a 412dp-wide design scaled to the phone's width and laid
/// out over the window minus whatever the keyboard covers — which is the part
/// that matters here, since that subtraction is what shrinks the chain.
class _Canvas extends StatefulWidget {
  const _Canvas({super.key, required this.build});

  final Widget Function() build;

  @override
  State<_Canvas> createState() => _CanvasState();
}

class _CanvasState extends State<_Canvas> {
  double inset = 0;

  void setKeyboard(double value) => setState(() => inset = value);

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 784),
        padding: const EdgeInsets.only(top: 36),
        viewPadding: const EdgeInsets.only(top: 36),
        viewInsets: EdgeInsets.only(bottom: inset),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: WBColors.bg),
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = constraints.maxWidth / 412.0;
                  final available = constraints.maxHeight - MediaQuery.viewInsetsOf(context).bottom;
                  return FittedBox(
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 412,
                      height: (available < 0 ? 0.0 : available) / scale,
                      child: widget.build(),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2352);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  group('the word field stays live for the whole duel', () {
    for (final yourTurn in [true, false]) {
      testWidgets('it is never disabled or read-only (yourTurn: $yourTurn)', (tester) async {
        phone(tester);
        await tester.pumpWidget(_Canvas(build: () => DuelScreen(
              duel: _duel(yourTurn: yourTurn),
              me: _me,
              error: '',
              scrollController: ScrollController(),
              onSubmit: (_) {},
              chatLog: const [],
              onSendChat: (_) {},
              onSendReaction: (_) {},
              reaction: null,
              powerUps: const DuelPowerUps(),
              onPowerUp: (_) {},
              onLeave: () {},
            )));
        await tester.pump();

        final field = tester.widget<TextField>(find.byType(TextField));
        // `enabled: false` unfocuses the field, and Android closes the keyboard
        // on the unfocus; `readOnly: true` closes the input connection outright.
        // Either one costs the player the rest of the turn.
        expect(field.enabled, isNot(false));
        expect(field.readOnly, isFalse);
      });
    }

    testWidgets('the keyboard survives the turn passing to the opponent', (tester) async {
      phone(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);

      Widget screen(bool yourTurn) => _Canvas(build: () => DuelScreen(
            duel: _duel(yourTurn: yourTurn),
            me: _me,
            error: '',
            scrollController: controller,
            onSubmit: (_) {},
            chatLog: const [],
            onSendChat: (_) {},
            onSendReaction: (_) {},
            reaction: null,
            powerUps: const DuelPowerUps(),
            onPowerUp: (_) {},
            onLeave: () {},
          ));

      await tester.pumpWidget(screen(true));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue, reason: 'the duel opens ready to type');

      // The word is sent and the server hands the turn over.
      await tester.pumpWidget(screen(false));
      await tester.pump();
      expect(
        tester.testTextInput.isVisible,
        isTrue,
        reason: 'the keyboard must not close while the opponent answers',
      );
      expect(tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus, isTrue);

      // And it is still there when the turn comes back, with no tap needed.
      await tester.pumpWidget(screen(true));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('the keyboard leaves with the duel screen', (tester) async {
      phone(tester);
      await tester.pumpWidget(_Canvas(build: () => DuelScreen(
            duel: _duel(yourTurn: true),
            me: _me,
            error: '',
            scrollController: ScrollController(),
            onSubmit: (_) {},
            chatLog: const [],
            onSendChat: (_) {},
            onSendReaction: (_) {},
            reaction: null,
            powerUps: const DuelPowerUps(),
            onPowerUp: (_) {},
            onLeave: () {},
          )));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // A field that holds focus all duel long must let go when the duel ends,
      // or the result opens with a keyboard across it.
      await tester.pumpWidget(_Canvas(build: () => WinScreen(
            result: const FinishedDuel(
              duelId: 'duel-1',
              won: true,
              reason: 'words_limit',
              rated: true,
              delta: 24,
              ratingBefore: 1284,
              ratingAfter: 1308,
              chainLength: 9,
              yourWords: 5,
              averageMs: 2400,
              newWords: 3,
              streakDays: 8,
              stuckLetter: null,
              hints: [],
              opponentId: 2,
              opponentIsBot: false,
            ),
            onRematch: () {},
            onHome: () {},
          )));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
    });
  });

  group('only the turn decides what is sent', () {
    Future<List<String>> pumpAndCollect(WidgetTester tester, {required bool yourTurn}) async {
      final sent = <String>[];
      await tester.pumpWidget(_Canvas(build: () => DuelScreen(
            duel: _duel(yourTurn: yourTurn),
            me: _me,
            error: '',
            scrollController: ScrollController(),
            onSubmit: sent.add,
            chatLog: const [],
            onSendChat: (_) {},
            onSendReaction: (_) {},
            reaction: null,
            powerUps: const DuelPowerUps(),
            onPowerUp: (_) {},
            onLeave: () {},
          )));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'window');
      await tester.pump();
      return sent;
    }

    testWidgets('the send button and the keyboard both send on your turn', (tester) async {
      phone(tester);
      final sent = await pumpAndCollect(tester, yourTurn: true);

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(sent, ['window']);

      await tester.enterText(find.byType(TextField), 'water');
      await tester.tap(find.byType(Pressable));
      await tester.pump();
      expect(sent, ['window', 'water']);
    });

    testWidgets('neither sends while the opponent is answering', (tester) async {
      phone(tester);
      final sent = await pumpAndCollect(tester, yourTurn: false);

      // The field is live now, so the keyboard's send key really does reach the
      // screen — refusing it is the screen's job, not the disabled state's.
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.tap(find.byType(Pressable));
      await tester.pump();

      expect(sent, isEmpty, reason: 'the server would answer not_your_turn');
      // And nothing the player typed ahead is thrown away.
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'window');
    });
  });

  group('the chain keeps its newest word in view', () {
    testWidgets('it follows the keyboard when the keyboard covers it', (tester) async {
      phone(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final canvas = GlobalKey<_CanvasState>();

      // A chain long enough to scroll, with the keyboard already down — the
      // state the player is in after deliberately dismissing it to read back.
      await tester.pumpWidget(_Canvas(
        key: canvas,
        build: () => DuelScreen(
          duel: _duel(yourTurn: true, words: 20),
          me: _me,
          error: '',
          scrollController: controller,
          onSubmit: (_) {},
          chatLog: const [],
          onSendChat: (_) {},
          onSendReaction: (_) {},
          reaction: null,
          powerUps: const DuelPowerUps(),
          onPowerUp: (_) {},
          onLeave: () {},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(controller.position.extentAfter, lessThan(1));

      final coveredViewport = controller.position.viewportDimension;

      // The player taps the field and Android slides the keyboard back up.
      for (final inset in [80.0, 160.0, 240.0, 320.0]) {
        canvas.currentState!.setKeyboard(inset);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: 400));

      // The keyboard really did take the room away...
      expect(controller.position.viewportDimension, lessThan(coveredViewport - 300));
      // ...and the newest word came with it instead of being left overhead.
      expect(
        controller.position.extentAfter,
        lessThan(1),
        reason: 'the opponent\'s answer must not be left above the keyboard',
      );
    });

    testWidgets('a player who scrolled up is left where they are', (tester) async {
      phone(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final canvas = GlobalKey<_CanvasState>();

      await tester.pumpWidget(_Canvas(
        key: canvas,
        build: () => DuelScreen(
          duel: _duel(yourTurn: true, words: 20),
          me: _me,
          error: '',
          scrollController: controller,
          onSubmit: (_) {},
          chatLog: const [],
          onSendChat: (_) {},
          onSendReaction: (_) {},
          reaction: null,
          powerUps: const DuelPowerUps(),
          onPowerUp: (_) {},
          onLeave: () {},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      controller.jumpTo(0);
      await tester.pump();

      canvas.currentState!.setKeyboard(320);
      await tester.pump(const Duration(milliseconds: 400));

      // Reading the chain back is a deliberate act; the keyboard appearing is
      // not a reason to undo it.
      expect(controller.offset, 0);
    });
  });
}
