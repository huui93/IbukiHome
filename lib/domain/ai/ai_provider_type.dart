enum AiProviderType {
  openai,
  gemini,
  deepseek,
  kimi,
  qwen,
  grok,
  glm,
  claude,
  custom,
}

extension AiProviderTypeValues on AiProviderType {
  String get displayName => switch (this) {
    AiProviderType.openai => 'OpenAI',
    AiProviderType.gemini => 'Gemini',
    AiProviderType.deepseek => 'DeepSeek',
    AiProviderType.kimi => 'Kimi',
    AiProviderType.qwen => '千问',
    AiProviderType.grok => 'Grok',
    AiProviderType.glm => 'GLM',
    AiProviderType.claude => 'Claude',
    AiProviderType.custom => '自定义',
  };

  String get shortLabel => switch (this) {
    AiProviderType.openai => 'O',
    AiProviderType.gemini => 'G',
    AiProviderType.deepseek => 'D',
    AiProviderType.kimi => 'K',
    AiProviderType.qwen => 'Q',
    AiProviderType.grok => 'X',
    AiProviderType.glm => 'Z',
    AiProviderType.claude => 'C',
    AiProviderType.custom => '+',
  };

  String get defaultBaseUrl => switch (this) {
    AiProviderType.openai => 'https://api.openai.com/v1',
    AiProviderType.gemini => 'https://generativelanguage.googleapis.com/v1beta',
    AiProviderType.deepseek => 'https://api.deepseek.com',
    AiProviderType.kimi => 'https://api.moonshot.cn/v1',
    AiProviderType.qwen => 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    AiProviderType.grok => 'https://api.x.ai/v1',
    AiProviderType.glm => 'https://open.bigmodel.cn/api/paas/v4',
    AiProviderType.claude => 'https://api.anthropic.com/v1',
    AiProviderType.custom => '',
  };

  bool get isBuiltIn => this != AiProviderType.custom;
  bool get requiresApiKey => this != AiProviderType.custom;

  static AiProviderType parse(String value) {
    return AiProviderType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw FormatException('Unknown AI provider type.'),
    );
  }
}
