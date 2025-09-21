import 'package:ainoval/models/model_info.dart'; // Import ModelInfo
import 'package:meta/meta.dart';

/// AI模型分组模型，用于UI显示
@immutable
class AIModelGroup {
  const AIModelGroup({
    required this.provider,
    required this.groups,
  });

  final String provider;
  final List<ModelPrefixGroup> groups;

  /// 从 ModelInfo 列表创建分组
  factory AIModelGroup.fromModelInfoList(String provider, List<ModelInfo> models) {
    final Map<String, List<ModelInfo>> groupedModels = {};

    for (final modelInfo in models) {
      final groupName = _defaultGroupName(modelInfo.id, provider);
      if (!groupedModels.containsKey(groupName)) {
        groupedModels[groupName] = [];
      }
      groupedModels[groupName]!.add(modelInfo);
    }

    final groups = groupedModels.entries
        .map((entry) => ModelPrefixGroup(
              prefix: entry.key,
              modelsInfo: entry.value,
            ))
        .toList();

    groups.sort((a, b) => a.prefix.compareTo(b.prefix));

    return AIModelGroup(provider: provider, groups: groups);
  }

  /// 参考 Cherry Studio 的分组规则，结合常见模型前缀进行归类
  static String _defaultGroupName(String modelId, String provider) {
    final id = modelId.toLowerCase();
    final p = provider.toLowerCase();

    // 1) 明确族群归类
    if (id.startsWith('gpt') || id.startsWith('o1') || id.startsWith('o3')) return 'openai';
    if (id.startsWith('claude')) return 'claude';
    if (id.startsWith('gemini') || id.startsWith('imagen')) return 'gemini';
    if (id.startsWith('mistral')) return 'mistral';
    if (id.startsWith('llama') || id.startsWith('meta-llama') || id.startsWith('llama-')) return 'llama';
    if (id.startsWith('qwen') || id.startsWith('qvq') || id.startsWith('qwq')) return 'qwen';
    if (id.startsWith('glm') || id.startsWith('chatglm') || id.contains('zhipu')) return 'glm';
    if (id.startsWith('deepseek')) return 'deepseek';
    if (id.startsWith('grok') || id.contains('xai')) return 'grok';
    if (id.startsWith('sonar') || id.contains('perplexity')) return 'perplexity';

    // 2) openrouter 风格：vendor/model
    if (id.contains('/')) {
      final vendor = id.split('/').first;
      if (vendor.isNotEmpty) return vendor;
    }

    // 3) 某些平台使用冒号
    if (id.contains(':')) {
      return id.split(':').first;
    }

    // 4) 使用第一个短横线段
    if (id.contains('-')) {
      return id.split('-').first;
    }

    // 5) 回退到 provider
    if (p.isNotEmpty) return p;

    // 6) 最后回退到完整 id
    return id;
  }

  /// 获取所有模型的平铺列表
  List<ModelInfo> get allModelsInfo {
    final List<ModelInfo> result = [];
    for (final group in groups) {
      result.addAll(group.modelsInfo);
    }
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AIModelGroup &&
        other.provider == provider &&
        _listEquals(other.groups, groups);
  }

  @override
  int get hashCode => provider.hashCode ^ Object.hashAll(groups);

  // 辅助方法：比较两个列表是否相等
  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 按前缀分组的模型
@immutable
class ModelPrefixGroup {
  const ModelPrefixGroup({
    required this.prefix,
    required this.modelsInfo, // Change from models (List<String>)
  });

  final String prefix;
  final List<ModelInfo> modelsInfo; // Store ModelInfo

  // Keep models getter for backward compatibility or UI that needs strings?
  List<String> get models => modelsInfo.map((info) => info.id).toList();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ModelPrefixGroup &&
        other.prefix == prefix &&
        _listEquals(other.modelsInfo, modelsInfo); // Compare ModelInfo lists
  }

  @override
  int get hashCode => prefix.hashCode ^ Object.hashAll(modelsInfo);

  // 辅助方法：比较两个列表是否相等
  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
