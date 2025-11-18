/// 设定卡片组件
library;

import 'package:flutter/material.dart';
import 'package:ainoval/models/novel_setting_item.dart';
import 'package:ainoval/utils/web_theme.dart';

/// 设定卡片组件
/// 
/// 用于展示知识库中的设定条目
class SettingCardWidget extends StatefulWidget {
  final NovelSettingItem setting;
  final VoidCallback? onCopy;

  const SettingCardWidget({
    Key? key,
    required this.setting,
    this.onCopy,
  }) : super(key: key);

  @override
  State<SettingCardWidget> createState() => _SettingCardWidgetState();
}

class _SettingCardWidgetState extends State<SettingCardWidget> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: WebTheme.getSurfaceColor(context),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: WebTheme.getBorderColor(context),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头部：名称 + 展开/收起按钮
          _buildHeader(),
          
          // 内容：描述 + 属性
          if (_isExpanded) _buildContent(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return InkWell(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WebTheme.getPrimaryColor(context).withOpacity(0.05),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
        child: Row(
          children: [
            // 类型图标
            _buildTypeIcon(),
            
            const SizedBox(width: 12),
            
            // 设定名称
            Expanded(
              child: Text(
                widget.setting.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: WebTheme.getTextColor(context),
                ),
              ),
            ),
            
            // 复制按钮
            if (widget.onCopy != null)
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: widget.onCopy,
                tooltip: '复制到我的小说',
                color: WebTheme.getSecondaryTextColor(context),
              ),
            
            // 展开/收起图标
            Icon(
              _isExpanded ? Icons.expand_less : Icons.expand_more,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeIcon() {
    final iconData = _getIconForType(widget.setting.type ?? '');
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        iconData,
        size: 20,
        color: WebTheme.getPrimaryColor(context),
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type.toUpperCase()) {
      case 'CHARACTER':
        return Icons.person;
      case 'LOCATION':
        return Icons.place;
      case 'ITEM':
        return Icons.inventory_2;
      case 'LORE':
      case 'WORLDVIEW':
        return Icons.public;
      case 'FACTION':
      case 'ORGANIZATION':
        return Icons.groups;
      case 'EVENT':
        return Icons.event;
      case 'CONCEPT':
        return Icons.lightbulb;
      case 'CREATURE':
        return Icons.pets;
      case 'MAGIC_SYSTEM':
      case 'POWER_SYSTEM':
        return Icons.auto_awesome;
      case 'TECHNOLOGY':
        return Icons.science;
      case 'CULTURE':
        return Icons.museum;
      case 'HISTORY':
      case 'TIMELINE':
        return Icons.history;
      case 'PLEASURE_POINT':
        return Icons.favorite;
      case 'ANTICIPATION_HOOK':
        return Icons.bookmark;
      case 'THEME':
        return Icons.color_lens;
      case 'TONE':
      case 'STYLE':
        return Icons.brush;
      case 'TROPE':
        return Icons.star;
      case 'PLOT_DEVICE':
        return Icons.devices;
      case 'GOLDEN_FINGER':
        return Icons.touch_app;
      case 'RELIGION':
        return Icons.account_balance;
      case 'POLITICS':
        return Icons.policy;
      case 'ECONOMY':
        return Icons.attach_money;
      case 'GEOGRAPHY':
        return Icons.terrain;
      default:
        return Icons.description;
    }
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 描述
          if (widget.setting.description != null && widget.setting.description!.isNotEmpty) ...[
            _buildSectionTitle('描述'),
            const SizedBox(height: 8),
            Text(
              widget.setting.description!,
              style: TextStyle(
                fontSize: 14,
                color: WebTheme.getSecondaryTextColor(context),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // 属性
          if (widget.setting.attributes != null && widget.setting.attributes!.isNotEmpty) ...[
            _buildSectionTitle('属性'),
            const SizedBox(height: 8),
            _buildAttributesTable(),
            const SizedBox(height: 16),
          ],
          
          // 标签
          if (widget.setting.tags != null && widget.setting.tags!.isNotEmpty) ...[
            _buildSectionTitle('标签'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.setting.tags!.map((tag) => _buildTag(tag)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: WebTheme.getTextColor(context),
      ),
    );
  }

  Widget _buildAttributesTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: WebTheme.getBorderColor(context),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: widget.setting.attributes!.entries.map((entry) {
          return _buildAttributeRow(entry.key, entry.value);
        }).toList(),
      ),
    );
  }

  Widget _buildAttributeRow(String key, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: WebTheme.getBorderColor(context),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              key,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: WebTheme.getTextColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: WebTheme.getPrimaryColor(context).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: WebTheme.getPrimaryColor(context).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 12,
          color: WebTheme.getPrimaryColor(context),
        ),
      ),
    );
  }
}

