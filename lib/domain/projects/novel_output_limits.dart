import '../../core/errors/data_exceptions.dart';

class NovelOutputLimits {
  const NovelOutputLimits({
    required this.projectId,
    this.minimum,
    this.maximum,
    this.temperature,
    this.revision = 0,
  });
  final String projectId;
  final int? minimum, maximum;
  final double? temperature;
  final int revision;

  bool get hasLengthLimits => minimum != null || maximum != null;
  bool get isDefault => !hasLengthLimits && temperature == null;
  String get label => !hasLengthLimits
      ? '默认'
      : minimum != null && maximum != null
      ? '$minimum–$maximum 字'
      : minimum != null
      ? '至少 $minimum 字'
      : '最多 $maximum 字';
  void validate() {
    final value = temperature;
    if (value != null && (!value.isFinite || value < 0 || value > 2)) {
      throw const DataFormatException('温度须在 0 到 2 之间；留空使用默认。');
    }
    if ((minimum != null && minimum! <= 0) ||
        (maximum != null && maximum! <= 0)) {
      throw const DataFormatException('字数请输入大于 0 的整数；留空使用默认。');
    }
    if (minimum != null && maximum != null && minimum! > maximum!) {
      throw const DataFormatException('最少字数不能大于最多字数。');
    }
  }

  String get promptSuffix => !hasLengthLimits
      ? ''
      : '\n\n【本作品输出字数】\n本次生成正文的目标：$label。按非空白字符计数。请预留收尾空间，在允许的范围内完成连贯正文，不重复凑字数，不输出段号、字数统计或创作说明。模型与服务实际允许的输出上限始终优先；达到上限时允许少于最少字数。';
}
