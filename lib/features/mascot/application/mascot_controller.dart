import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/mascot_action.dart';
import '../domain/mascot_state.dart';

final mascotControllerProvider =
    NotifierProvider<MascotController, MascotState>(MascotController.new);

class MascotController extends Notifier<MascotState> {
  MascotState? _stateBeforePeek;

  @override
  MascotState build() => MascotState.idle;

  void perform(MascotAction action) {
    if (action != MascotAction.peek) {
      _stateBeforePeek = null;
    }

    state = switch (action) {
      MascotAction.settle => MascotState.idle,
      MascotAction.think => MascotState.thinking,
      MascotAction.celebrate => MascotState.happy,
      MascotAction.sleep => MascotState.sleeping,
      MascotAction.peek => MascotState.peeking,
      MascotAction.listen => MascotState.listening,
    };
  }

  void peekTemporarily() {
    _stateBeforePeek ??= state;
    state = MascotState.peeking;
  }

  void restoreAfterPeek() {
    final previous = _stateBeforePeek;
    _stateBeforePeek = null;
    state = previous ?? MascotState.idle;
  }
}
