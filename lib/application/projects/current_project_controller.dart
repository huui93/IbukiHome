import 'package:flutter_riverpod/flutter_riverpod.dart';

final currentProjectControllerProvider =
    NotifierProvider<CurrentProjectController, String?>(
      CurrentProjectController.new,
    );

class CurrentProjectController extends Notifier<String?> {
  @override
  String? build() => null;

  void selectProject(String projectId) {
    state = projectId;
  }

  void clearProject() {
    state = null;
  }
}
