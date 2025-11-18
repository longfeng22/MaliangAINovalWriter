/// 智能体管理页面
/// Agent manager page

import 'package:flutter/material.dart';
import '../models/agent.dart';
import '../config/theme_config.dart';
import '../utils/responsive_utils.dart';
import '../i18n/translations.dart';
import 'agent_card.dart';
import 'create_agent_dialog.dart';

/// 智能体管理Widget
/// Agent manager widget
class AgentManager extends StatefulWidget {
  final List<Agent> agents;
  final String activeAgentId;
  final Function(String agentId) onAgentSelect;
  final Function(Agent agent) onAgentCreate;
  final Function(String agentId, Agent agent) onAgentUpdate;
  final Function(String agentId) onAgentDelete;
  final VoidCallback onClose;
  final bool isDark;
  final Translations translations;
  
  const AgentManager({
    super.key,
    required this.agents,
    required this.activeAgentId,
    required this.onAgentSelect,
    required this.onAgentCreate,
    required this.onAgentUpdate,
    required this.onAgentDelete,
    required this.onClose,
    this.isDark = false,
    required this.translations,
  });
  
  @override
  State<AgentManager> createState() => _AgentManagerState();
}

class _AgentManagerState extends State<AgentManager> {
  String _searchQuery = '';
  
  // Mock数据
  final List<BuiltInTool> _builtInTools = const [
    BuiltInTool(id: 'character-query', name: '角色查询', description: '查询角色信息', type: 'view'),
    BuiltInTool(id: 'setting-management', name: '设定管理', description: '创建/更新/删除设定', type: 'crud'),
    BuiltInTool(id: 'chapter-management', name: '章节管理', description: '创建/更新/删除章节', type: 'crud'),
    BuiltInTool(id: 'outline-management', name: '大纲管理', description: '创建/更新/删除大纲', type: 'crud'),
  ];
  
  final List<MCPTool> _mcpTools = const [
    MCPTool(id: 'web-search', name: 'MCP-网络搜索', server: 'search-server', description: '使用网络搜索获取信息'),
    MCPTool(id: 'file-system', name: 'MCP-文件操作', server: 'fs-server', description: '读写文件系统'),
  ];
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    final filteredAgents = widget.agents.where((agent) {
      if (_searchQuery.isEmpty) return true;
      return agent.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (agent.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
    }).toList();
    
    return Scaffold(
      backgroundColor: AgentChatThemeConfig.getColor(
        AgentChatThemeConfig.lightBackground,
        AgentChatThemeConfig.darkBackground,
        widget.isDark,
      ),
      appBar: AppBar(
        title: Text(widget.translations.agentManagement),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: widget.onClose,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () => _showCreateDialog(context),
            tooltip: widget.translations.createAgent,
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          _buildSearchBar(isCompact),
          
          // 智能体网格
          Expanded(
            child: filteredAgents.isEmpty
                ? _buildEmptyState(isCompact)
                : GridView.builder(
                    padding: EdgeInsets.all(
                      ResponsiveUtils.getSpacing(context),
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: ResponsiveUtils.getGridColumnCount(context),
                      crossAxisSpacing: AgentChatThemeConfig.spacing3,
                      mainAxisSpacing: AgentChatThemeConfig.spacing3,
                      childAspectRatio: isCompact ? 1.2 : 1.4,
                    ),
                    itemCount: filteredAgents.length,
                    itemBuilder: (context, index) {
                      final agent = filteredAgents[index];
                      return AgentCard(
                        agent: agent,
                        isActive: agent.id == widget.activeAgentId,
                        onSelect: () => widget.onAgentSelect(agent.id),
                        onEdit: () => _showEditDialog(context, agent),
                        onDelete: () => _confirmDelete(context, agent),
                        isDark: widget.isDark,
                        translations: widget.translations,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSearchBar(bool isCompact) {
    return Container(
      padding: EdgeInsets.all(
        ResponsiveUtils.getSpacing(context),
      ),
      decoration: BoxDecoration(
        color: AgentChatThemeConfig.getColor(
          AgentChatThemeConfig.lightCard,
          AgentChatThemeConfig.darkCard,
          widget.isDark,
        ),
        border: Border(
          bottom: BorderSide(
            color: AgentChatThemeConfig.getColor(
              AgentChatThemeConfig.lightBorder,
              AgentChatThemeConfig.darkBorder,
              widget.isDark,
            ),
          ),
        ),
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: widget.translations.search,
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
              ResponsiveUtils.getBorderRadius(context) * 0.5,
            ),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: AgentChatThemeConfig.spacing3,
            vertical: isCompact ? AgentChatThemeConfig.spacing2 : AgentChatThemeConfig.spacing3,
          ),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }
  
  Widget _buildEmptyState(bool isCompact) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.smart_toy_outlined,
            size: isCompact ? 64 : 80,
            color: AgentChatThemeConfig.getColor(
              AgentChatThemeConfig.lightMutedForeground,
              AgentChatThemeConfig.darkMutedForeground,
              widget.isDark,
            ).withOpacity(0.3),
          ),
          SizedBox(height: AgentChatThemeConfig.spacing4),
          Text(
            widget.translations.noToolsSelected,
            style: TextStyle(
              fontSize: isCompact ? 16 : 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  
  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => CreateAgentDialog(
        builtInTools: _builtInTools,
        mcpTools: _mcpTools,
        onSave: widget.onAgentCreate,
        isDark: widget.isDark,
        translations: widget.translations,
      ),
    );
  }
  
  void _showEditDialog(BuildContext context, Agent agent) {
    showDialog(
      context: context,
      builder: (context) => CreateAgentDialog(
        editAgent: agent,
        builtInTools: _builtInTools,
        mcpTools: _mcpTools,
        onSave: (updatedAgent) => widget.onAgentUpdate(agent.id, updatedAgent),
        isDark: widget.isDark,
        translations: widget.translations,
      ),
    );
  }
  
  void _confirmDelete(BuildContext context, Agent agent) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.translations.deleteAgent),
        content: Text(widget.translations.deleteAgentConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.translations.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              widget.onAgentDelete(agent.id);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AgentChatThemeConfig.toolDeleteColor.toColor(),
            ),
            child: Text(widget.translations.delete),
          ),
        ],
      ),
    );
  }
}




