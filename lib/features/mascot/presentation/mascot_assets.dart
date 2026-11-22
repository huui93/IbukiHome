import '../domain/mascot_state.dart';

class MascotAssets {
  const MascotAssets._();

  static String forState(MascotState state) {
    return switch (state) {
      MascotState.peeking => 'assets/mascot/mascot_peeking.png',
      MascotState.thinking => 'assets/mascot/mascot_thinking.png',
      MascotState.happy => 'assets/mascot/mascot_happy.png',
      MascotState.idle ||
      MascotState.sleeping ||
      MascotState.listening => 'assets/mascot/mascot_idle.png',
    };
  }
}
