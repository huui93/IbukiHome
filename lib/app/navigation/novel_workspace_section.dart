enum NovelWorkspaceSection {
  bookshelf('书架'),
  creation('创作'),
  settings('设置');

  const NovelWorkspaceSection(this.label);
  final String label;

  static NovelWorkspaceSection fromQuery(String? value) => values.firstWhere(
    (section) => section.name == value,
    orElse: () => bookshelf,
  );
}
