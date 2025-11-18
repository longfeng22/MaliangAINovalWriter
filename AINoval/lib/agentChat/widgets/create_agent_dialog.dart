/// 创建/编辑智能体对话框
/// Create/Edit agent dialog

import 'package:flutter/material.dart';
import '../models/agent.dart';
import '../config/theme_config.dart';
import '../config/constants.dart';
import '../utils/responsive_utils.dart';
import '../i18n/translations.dart';

/// 创建智能体对话框Widget
/// Create agent dialog widget
class CreateAgentDialog extends StatefulWidget {
  final Agent? editAgent;
  final List<BuiltInTool> builtInTools;
  final List<MCPTool> mcpTools;
  final Function(Agent agent) onSave;
  final bool isDark;
  final Translations translations;
  
  const CreateAgentDialog({
    super.key,
    this.editAgent,
    required this.builtInTools,
    required this.mcpTools,
    required this.onSave,
    this.isDark = false,
    required this.translations,
  });
  
  @override
  State<CreateAgentDialog> createState() => _CreateAgentDialogState();
}

class _CreateAgentDialogState extends State<CreateAgentDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _systemPromptController;
  
  List<String> _selectedToolCategories = [];
  List<String> _selectedBuiltInTools = [];
  List<String> _selectedMCPTools = [];
  
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.editAgent?.name ?? '');
    _descriptionController = TextEditingController(text: widget.editAgent?.description ?? '');
    _systemPromptController = TextEditingController(text: widget.editAgent?.systemPrompt ?? '');
    
    if (widget.editAgent != null) {
      _selectedToolCategories = List.from(widget.editAgent!.toolCategories);
      _selectedBuiltInTools = List.from(widget.editAgent!.builtInTools);
      _selectedMCPTools = List.from(widget.editAgent!.mcpTools);
    }
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }
  
  void _handleSave() {
    if (_formKey.currentState!.validate()) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final agent = Agent(
        id: widget.editAgent?.id ?? 'agent-$now',
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        systemPrompt: _systemPromptController.text.trim(),
        toolCategories: _selectedToolCategories,
        builtInTools: _selectedBuiltInTools,
        mcpTools: _selectedMCPTools,
        createdAt: widget.editAgent?.createdAt ?? now,
        updatedAt: now,
      );
      widget.onSave(agent);
      Navigator.of(context).pop();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveUtils.getScreenType(context);
    final isCompact = screenType == ScreenType.mobile;
    
    return Dialog(
      backgroundColor: AgentChatThemeConfig.getColor(
        AgentChatThemeConfig.lightCard,
        AgentChatThemeConfig.darkCard,
        widget.isDark,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ResponsiveUtils.getBorderRadius(context)),
      ),
      child: Container(
        width: isCompact ? double.infinity : 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, isCompact),
            Flexible(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.all(
                    isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
                  ),
                  children: [
                    _buildNameField(isCompact),
                    SizedBox(height: AgentChatThemeConfig.spacing3),
                    _buildDescriptionField(isCompact),
                    SizedBox(height: AgentChatThemeConfig.spacing3),
                    _buildSystemPromptField(isCompact),
                    SizedBox(height: AgentChatThemeConfig.spacing4),
                    _buildToolCategories(isCompact),
                    if (_selectedToolCategories.contains(ToolCategory.builtIn)) ...[
                      SizedBox(height: AgentChatThemeConfig.spacing3),
                      _buildBuiltInTools(isCompact),
                    ],
                    if (_selectedToolCategories.contains(ToolCategory.mcp)) ...[
                      SizedBox(height: AgentChatThemeConfig.spacing3),
                      _buildMCPTools(isCompact),
                    ],
                  ],
                ),
              ),
            ),
            _buildFooter(context, isCompact),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeader(BuildContext context, bool isCompact) {
    return Container(
      padding: EdgeInsets.all(
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
      ),
      decoration: BoxDecoration(
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
      child: Row(
        children: [
          Icon(
            Icons.smart_toy,
            color: AgentChatThemeConfig.getColor(
              AgentChatThemeConfig.lightPrimary,
              AgentChatThemeConfig.darkPrimary,
              widget.isDark,
            ),
          ),
          SizedBox(width: AgentChatThemeConfig.spacing2),
          Expanded(
            child: Text(
              widget.editAgent != null 
                  ? widget.translations.editAgent 
                  : widget.translations.createAgent,
              style: TextStyle(
                fontSize: isCompact ? 16 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNameField(bool isCompact) {
    return TextFormField(
      controller: _nameController,
      decoration: InputDecoration(
        labelText: widget.translations.agentName,
        hintText: '${widget.translations.defaultAgent}, ${widget.translations.chatAgent}...',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return widget.translations.required;
        }
        return null;
      },
    );
  }
  
  Widget _buildDescriptionField(bool isCompact) {
    return TextFormField(
      controller: _descriptionController,
      decoration: InputDecoration(
        labelText: widget.translations.agentDescription,
        border: OutlineInputBorder(),
      ),
      maxLines: 2,
    );
  }
  
  Widget _buildSystemPromptField(bool isCompact) {
    return TextFormField(
      controller: _systemPromptController,
      decoration: InputDecoration(
        labelText: widget.translations.systemPrompt,
        border: OutlineInputBorder(),
      ),
      maxLines: 4,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return widget.translations.required;
        }
        return null;
      },
    );
  }
  
  Widget _buildToolCategories(bool isCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.translations.toolCategories,
          style: TextStyle(
            fontSize: isCompact ? 13 : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: AgentChatThemeConfig.spacing),
        CheckboxListTile(
          title: Text(widget.translations.enableBuiltInTools),
          value: _selectedToolCategories.contains(ToolCategory.builtIn),
          onChanged: (value) {
            setState(() {
              if (value == true) {
                _selectedToolCategories.add(ToolCategory.builtIn);
              } else {
                _selectedToolCategories.remove(ToolCategory.builtIn);
                _selectedBuiltInTools.clear();
              }
            });
          },
        ),
        CheckboxListTile(
          title: Text(widget.translations.enableMCPTools),
          value: _selectedToolCategories.contains(ToolCategory.mcp),
          onChanged: (value) {
            setState(() {
              if (value == true) {
                _selectedToolCategories.add(ToolCategory.mcp);
              } else {
                _selectedToolCategories.remove(ToolCategory.mcp);
                _selectedMCPTools.clear();
              }
            });
          },
        ),
      ],
    );
  }
  
  Widget _buildBuiltInTools(bool isCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.translations.builtInTools,
          style: TextStyle(
            fontSize: isCompact ? 13 : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: AgentChatThemeConfig.spacing),
        ...widget.builtInTools.map((tool) => CheckboxListTile(
          title: Text(tool.name),
          subtitle: Text(tool.description, style: TextStyle(fontSize: 12)),
          value: _selectedBuiltInTools.contains(tool.id),
          onChanged: (value) {
            setState(() {
              if (value == true) {
                _selectedBuiltInTools.add(tool.id);
              } else {
                _selectedBuiltInTools.remove(tool.id);
              }
            });
          },
        )),
      ],
    );
  }
  
  Widget _buildMCPTools(bool isCompact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.translations.mcpTools,
          style: TextStyle(
            fontSize: isCompact ? 13 : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: AgentChatThemeConfig.spacing),
        ...widget.mcpTools.map((tool) => CheckboxListTile(
          title: Text(tool.name),
          subtitle: Text('${tool.server} - ${tool.description}', style: TextStyle(fontSize: 12)),
          value: _selectedMCPTools.contains(tool.id),
          onChanged: (value) {
            setState(() {
              if (value == true) {
                _selectedMCPTools.add(tool.id);
              } else {
                _selectedMCPTools.remove(tool.id);
              }
            });
          },
        )),
      ],
    );
  }
  
  Widget _buildFooter(BuildContext context, bool isCompact) {
    return Container(
      padding: EdgeInsets.all(
        isCompact ? AgentChatThemeConfig.spacing3 : AgentChatThemeConfig.spacing4,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AgentChatThemeConfig.getColor(
              AgentChatThemeConfig.lightBorder,
              AgentChatThemeConfig.darkBorder,
              widget.isDark,
            ),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.translations.cancel),
          ),
          SizedBox(width: AgentChatThemeConfig.spacing2),
          ElevatedButton(
            onPressed: _handleSave,
            child: Text(widget.translations.save),
          ),
        ],
      ),
    );
  }
}




