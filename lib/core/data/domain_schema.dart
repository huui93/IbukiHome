class DomainSchema {
  const DomainSchema._();

  static const int currentVersion = 1;
  static const String dateEncoding = 'iso8601_utc';
  static const String softDeleteField = 'deleted_at';
}
