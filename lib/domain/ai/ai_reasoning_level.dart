enum AiReasoningLevel {
  automatic('默认'),
  disabled('关闭思考'),
  enabled('开启思考'),
  low('低'),
  medium('中'),
  high('高'),
  xhigh('较高'),
  max('最高');

  const AiReasoningLevel(this.label);
  final String label;
  static AiReasoningLevel parse(String? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => automatic);
}
