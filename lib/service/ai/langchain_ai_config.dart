import 'dart:convert';

import 'package:langchain_anthropic/langchain_anthropic.dart';
import 'package:langchain_google/langchain_google.dart';
import 'package:langchain_openai/langchain_openai.dart';

/// Normalized configuration for LangChain-backed chat providers.
/// 用于LangChain支持的聊天AI提供商的标准化配置类
class LangchainAiConfig {
  /// 创建LangchainAiConfig实例
  /// [identifier]：AI配置的唯一标识符
  /// [model]：AI模型名称
  /// [apiKey]：API密钥
  /// [baseUrl]：API基础URL（可选）
  /// [headers]：HTTP请求头（可选）
  /// [temperature]：生成文本的随机性（0-1之间，值越高越随机）
  /// [topP]：核采样参数，控制生成文本的多样性
  /// [maxTokens]：生成文本的最大令牌数
  /// [maxOutputTokens]：生成文本的最大输出令牌数（主要用于Google模型）
  /// [additional]：其他附加配置参数
  LangchainAiConfig({
    required this.identifier,
    required this.model,
    required this.apiKey,
    this.baseUrl,
    Map<String, String>? headers,
    this.temperature,
    this.topP,
    this.maxTokens,
    this.maxOutputTokens,
    this.additional,
  }) : headers = Map.unmodifiable(headers ?? const {});

  /// AI配置的唯一标识符
  final String identifier;

  /// AI模型名称
  final String model;

  /// API密钥
  final String apiKey;

  /// API基础URL
  final String? baseUrl;

  /// HTTP请求头（不可修改）
  final Map<String, String> headers;

  /// 生成文本的随机性（0-1之间，值越高越随机）
  final double? temperature;

  /// 核采样参数，控制生成文本的多样性（0-1之间）
  final double? topP;

  /// 生成文本的最大令牌数
  final int? maxTokens;

  /// 生成文本的最大输出令牌数（主要用于Google模型）
  final int? maxOutputTokens;

  /// 其他附加配置参数
  final Map<String, dynamic>? additional;

  /// 将配置转换为OpenAI API选项
  ChatOpenAIOptions toOpenAIOptions() {
    return ChatOpenAIOptions(
      model: model.isEmpty ? null : model,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
    );
  }

  /// 将配置转换为Anthropic API选项
  ChatAnthropicOptions toAnthropicOptions() {
    return ChatAnthropicOptions(
      model: model.isEmpty ? null : model,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
    );
  }

  /// 将配置转换为Google Generative AI API选项
  ChatGoogleGenerativeAIOptions toGoogleOptions() {
    return ChatGoogleGenerativeAIOptions(
      model: model.isEmpty ? null : model,
      temperature: temperature,
      topP: topP,
      maxOutputTokens: maxOutputTokens,
    );
  }

  /// 从偏好设置创建LangchainAiConfig实例
  /// [identifier]：AI配置的唯一标识符
  /// [raw]：原始配置映射
  factory LangchainAiConfig.fromPrefs(
    String identifier,
    Map<String, String> raw,
  ) {
    final apiKey = raw['api_key'] ?? '';
    final model = raw['model'] ?? '';
    final url = raw['url'] ?? '';
    final headers = _parseHeaders(raw['headers']);
    final additional = _parseJson(raw['extra'] ?? raw['additional']);

    // 辅助函数：将字符串转换为double（如果可能）
    double? parseDouble(String? value) =>
        value == null ? null : double.tryParse(value.trim());
    // 辅助函数：将字符串转换为int（如果可能）
    int? parseInt(String? value) =>
        value == null ? null : int.tryParse(value.trim());

    return LangchainAiConfig(
      identifier: identifier,
      apiKey: apiKey,
      model: model,
      baseUrl: _deriveBaseUrl(url),
      headers: headers,
      temperature: parseDouble(raw['temperature']),
      topP: parseDouble(raw['top_p']),
      maxTokens: parseInt(raw['max_tokens']),
      maxOutputTokens: parseInt(raw['max_output_tokens']),
      additional: additional,
    );
  }

  /// 创建当前配置的副本，可选择性地覆盖某些参数
  LangchainAiConfig copyWith({
    String? model,
    String? apiKey,
    String? baseUrl,
    Map<String, String>? headers,
    double? temperature,
    double? topP,
    int? maxTokens,
    int? maxOutputTokens,
    Map<String, dynamic>? additional,
  }) {
    return LangchainAiConfig(
      identifier: identifier,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      headers: headers ?? this.headers,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: maxTokens ?? this.maxTokens,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      additional: additional ?? this.additional,
    );
  }
}

/// 解析HTTP请求头
/// [headersRaw]：原始请求头字符串，可以是JSON格式或分号分隔的键值对
Map<String, String> _parseHeaders(String? headersRaw) {
  if (headersRaw == null || headersRaw.trim().isEmpty) {
    return const {};
  }

  try {
    // 尝试解析为JSON格式
    final decoded = jsonDecode(headersRaw);
    if (decoded is Map<String, dynamic>) {
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    }
  } catch (_) {
    // 如果JSON解析失败，尝试解析为分号分隔的键值对
    final entries = headersRaw.split(';');
    final map = <String, String>{};
    for (final entry in entries) {
      final parts = entry.split('=');
      if (parts.length == 2) {
        map[parts[0].trim()] = parts[1].trim();
      }
    }
    if (map.isNotEmpty) {
      return map;
    }
  }

  return const {};
}

/// 解析JSON字符串为Map
/// [value]：JSON字符串
Map<String, dynamic>? _parseJson(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {
    // 解析失败返回null
  }

  return null;
}

/// 从完整URL中提取基础URL
/// [url]：完整的API URL
/// 该方法会移除URL路径中常见的API端点后缀，如'/chat', '/completions'等
String? _deriveBaseUrl(String? url) {
  if (url == null || url.trim().isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(url.trim());
  if (uri == null) {
    return url.trim();
  }

  // 定义常见的API端点后缀，这些会被移除
  final removableSegments = {
    'chat',
    'messages',
    'completions',
    'responses',
    'invoke',
    'openai',
  };

  final segments = uri.pathSegments.toList(growable: true);
  // 移除路径末尾的常见API端点后缀
  while (segments.isNotEmpty &&
      removableSegments.contains(segments.last.toLowerCase())) {
    segments.removeLast();
  }

  final cleaned = uri.replace(pathSegments: segments);
  final base = cleaned.toString();
  // 移除末尾的斜杠
  if (base.endsWith('/')) {
    return base.substring(0, base.length - 1);
  }
  return base;
}

/// 合并两个配置，优先使用override中的非空值
/// [base]：基础配置
/// [override]：覆盖配置
LangchainAiConfig mergeConfigs(
  LangchainAiConfig base,
  LangchainAiConfig override,
) {
  // 合并请求头，override中的请求头会覆盖base中的同名请求头
  final mergedHeaders = <String, String>{}
    ..addAll(base.headers)
    ..addAll(override.headers);

  return base.copyWith(
    model: override.model.isNotEmpty ? override.model : base.model,
    apiKey: override.apiKey.isNotEmpty ? override.apiKey : base.apiKey,
    baseUrl: override.baseUrl ?? base.baseUrl,
    headers: mergedHeaders,
    temperature: override.temperature ?? base.temperature,
    topP: override.topP ?? base.topP,
    maxTokens: override.maxTokens ?? base.maxTokens,
    maxOutputTokens: override.maxOutputTokens ?? base.maxOutputTokens,
    additional: mergeMaps(base.additional, override.additional),
  );
}

/// 合并两个Map，override中的键值对会覆盖base中的同名键值对
/// [base]：基础Map
/// [override]：覆盖Map
Map<String, dynamic>? mergeMaps(
  Map<String, dynamic>? base,
  Map<String, dynamic>? override,
) {
  if (base == null && override == null) {
    return null;
  }

  final map = <String, dynamic>{};
  if (base != null) map.addAll(base);
  if (override != null) map.addAll(override);
  return map;
}
