import '../../core/errors/data_exceptions.dart';

class NovelOutputLimits {
  const NovelOutputLimits({
    required this.projectId,
    this.minimum,
    this.maximum,
    this.revision = 0,
  });
  final String projectId;
  final int? minimum, maximum;
  final int revision;
  bool get isDefault => minimum == null && maximum == null;
  String get label => isDefault
      ? '默认'
      : minimum != null && maximum != null
      ? '$minimum–$maximum 字'
      : minimum != null
      ? '至少 $minimum 字'
      : '最多 $maximum 字';
  void validate() {
    if ((minimum != null && minimum! <= 0) ||
        (maximum != null && maximum! <= 0)) {
      throw const DataFormatException('字数请输入大于 0 的整数；留空使用默认。');
    }
    if (minimum != null && maximum != null && minimum! > maximum!) {
      throw const DataFormatException('最少字数不能大于最多字数。');
    }
  }

  String get promptSuffix => isDefault
      ? ''
      : '\n\n【本作品输出字数】\n本次生成正文的目标：$label。按非空白字符估算字数。尽量在此范围内完成一段连贯正文，不重复凑字数。模型与服务实际允许的输出上限始终优先；达到上限时允许少于最少字数。';
}
