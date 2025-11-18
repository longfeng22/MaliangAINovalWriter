/// 智能体模型
/// Agent model

import 'package:equatable/equatable.dart';

/// 内置工具
/// Built-in tool
class BuiltInTool extends Equatable {
  final String id;
  final String name;
  final String description;
  final String type;  // 'view' | 'crud'
  
  const BuiltInTool({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
  });
  
  @override
  List<Object?> get props => [id, name, description, type];
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type,
  };
  
  factory BuiltInTool.fromJson(Map<String, dynamic> json) => BuiltInTool(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    type: json['type'] as String,
  );
}

/// MCP工具
/// MCP tool
class MCPTool extends Equatable {
  final String id;
  final String name;
  final String server;
  final String description;
  
  const MCPTool({
    required this.id,
    required this.name,
    required this.server,
    required this.description,
  });
  
  @override
  List<Object?> get props => [id, name, server, description];
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'server': server,
    'description': description,
  };
  
  factory MCPTool.fromJson(Map<String, dynamic> json) => MCPTool(
    id: json['id'] as String,
    name: json['name'] as String,
    server: json['server'] as String,
    description: json['description'] as String,
  );
}

/// 智能体配置
/// Agent configuration
class Agent extends Equatable {
  final String id;
  final String name;
  final String? description;
  final String systemPrompt;
  final List<String> toolCategories;  // ['built-in', 'mcp']
  final List<String> builtInTools;    // 启用的内置工具ID列表
  final List<String> mcpTools;        // 启用的MCP工具ID列表
  final int createdAt;
  final int updatedAt;
  
  const Agent({
    required this.id,
    required this.name,
    this.description,
    required this.systemPrompt,
    required this.toolCategories,
    required this.builtInTools,
    required this.mcpTools,
    required this.createdAt,
    required this.updatedAt,
  });
  
  @override
  List<Object?> get props => [
    id,
    name,
    description,
    systemPrompt,
    toolCategories,
    builtInTools,
    mcpTools,
    createdAt,
    updatedAt,
  ];
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'systemPrompt': systemPrompt,
    'toolCategories': toolCategories,
    'builtInTools': builtInTools,
    'mcpTools': mcpTools,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
  
  factory Agent.fromJson(Map<String, dynamic> json) => Agent(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    systemPrompt: json['systemPrompt'] as String,
    toolCategories: (json['toolCategories'] as List).cast<String>(),
    builtInTools: (json['builtInTools'] as List).cast<String>(),
    mcpTools: (json['mcpTools'] as List).cast<String>(),
    createdAt: json['createdAt'] as int,
    updatedAt: json['updatedAt'] as int,
  );
  
  Agent copyWith({
    String? id,
    String? name,
    String? description,
    String? systemPrompt,
    List<String>? toolCategories,
    List<String>? builtInTools,
    List<String>? mcpTools,
    int? createdAt,
    int? updatedAt,
  }) => Agent(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    toolCategories: toolCategories ?? this.toolCategories,
    builtInTools: builtInTools ?? this.builtInTools,
    mcpTools: mcpTools ?? this.mcpTools,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  
  /// 是否启用了内置工具
  bool get hasBuiltInTools => toolCategories.contains('built-in') && builtInTools.isNotEmpty;
  
  /// 是否启用了MCP工具
  bool get hasMCPTools => toolCategories.contains('mcp') && mcpTools.isNotEmpty;
  
  /// 工具总数
  int get totalTools => builtInTools.length + mcpTools.length;
  
  /// 是否是纯对话智能体
  bool get isChatOnly => totalTools == 0;
}





