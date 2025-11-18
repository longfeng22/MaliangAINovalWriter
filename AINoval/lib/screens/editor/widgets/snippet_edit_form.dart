import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:ainoval/models/novel_snippet.dart';
import 'package:ainoval/services/api_service/repositories/novel_snippet_repository.dart';
import 'package:ainoval/utils/web_theme.dart';
import 'package:ainoval/utils/logger.dart';
import 'package:ainoval/screens/editor/managers/editor_layout_manager.dart';
import 'package:ainoval/widgets/common/floating_card.dart';
import 'package:ainoval/utils/event_bus.dart';

/// 浮动片段编辑卡片管理器
class FloatingSnippetEditor {
  static bool _isShowing = false;

  /// 显示浮动编辑卡片
  static void show({
    required BuildContext context,
    required NovelSnippet snippet,
    Function(NovelSnippet)? onSaved,
    Function(String)? onDeleted,
  }) {
    if (_isShowing) {
      hide();
    }

    // 在创建 Overlay 前获取布局信息
    final layoutManager = Provider.of<EditorLayoutManager>(context, listen: false);
    final sidebarWidth = layoutManager.isEditorSidebarVisible ? layoutManager.editorSidebarWidth : 0.0;

    AppLogger.d('FloatingSnippetEditor', '显示浮动卡片，侧边栏宽度: $sidebarWidth, 是否可见: ${layoutManager.isEditorSidebarVisible}');

    // 计算卡片大小（保持原有逻辑）
    final screenSize = MediaQuery.of(context).size;
    final cardWidth = (screenSize.width * 0.2).clamp(500.0, 800.0);
    final cardHeight = (screenSize.height * 0.2).clamp(300.0, 500.0);

    FloatingCard.show(
      context: context,
      position: FloatingCardPosition(
        left: sidebarWidth + 16.0, // 与侧边栏保持16px间隙
        top: 80.0, // 距离顶部适当距离
      ),
      config: FloatingCardConfig(
        width: cardWidth,
        height: cardHeight,
        showCloseButton: false, // 我们使用自定义头部
        enableBackgroundTap: false, // 让点击穿透到底层编辑区
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.easeOutCubic,
        borderRadius: BorderRadius.circular(12),
        padding: EdgeInsets.zero, // 自定义内容的padding
      ),
      child: _SnippetEditContent(
        snippet: snippet,
        onSaved: (updatedSnippet) {
          onSaved?.call(updatedSnippet);
          hide();
        },
        onDeleted: (snippetId) {
          onDeleted?.call(snippetId);
          hide();
        },
        onClose: hide,
      ),
      onClose: hide,
    );

    _isShowing = true;
  }

  /// 隐藏浮动编辑卡片
  static void hide() {
    if (_isShowing) {
      FloatingCard.hide();
      _isShowing = false;
    }
  }

  /// 检查是否正在显示
  static bool get isShowing => _isShowing;
}

/// 片段编辑内容组件
class _SnippetEditContent extends StatefulWidget {
  final NovelSnippet snippet;
  final Function(NovelSnippet)? onSaved;
  final Function(String)? onDeleted;
  final VoidCallback? onClose;

  const _SnippetEditContent({
    required this.snippet,
    this.onSaved,
    this.onDeleted,
    this.onClose,
  });

  @override
  State<_SnippetEditContent> createState() => _SnippetEditContentState();
}

class _SnippetEditContentState extends State<_SnippetEditContent> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  
  bool _isLoading = false;
  bool _isFavorite = false;
  bool _titleError = false;  // 标题错误状态
  String? _titleErrorText;    // 标题错误提示文本
  
  late NovelSnippetRepository _snippetRepository;

  @override
  void initState() {
    super.initState();
    
    // 初始化数据
    _snippetRepository = context.read<NovelSnippetRepository>();
    _titleController = TextEditingController(text: widget.snippet.title);
    _contentController = TextEditingController(text: widget.snippet.content);
    _isFavorite = widget.snippet.isFavorite;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveSnippet() async {
    if (_isLoading) return;
    
    // 清除之前的错误状态
    setState(() {
      _titleError = false;
      _titleErrorText = null;
      _isLoading = true;
    });

    // 前端验证：检查标题是否为空
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _titleError = true;
        _titleErrorText = '片段标题不能为空';
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('请输入片段标题', style: WebTheme.bodyMedium.copyWith(color: WebTheme.white)),
            backgroundColor: WebTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
      return;
    }

    try {
      // 检查是否为创建模式（ID为空）
      if (widget.snippet.id.isEmpty) {
        // 创建新片段
        final createRequest = CreateSnippetRequest(
          novelId: widget.snippet.novelId,
          title: _titleController.text,
          content: _contentController.text,
          notes: null,
        );
        
        final newSnippet = await _snippetRepository.createSnippet(createRequest);
        
        // 如果需要更新收藏状态，创建包含收藏状态的最终片段
        NovelSnippet finalSnippet = newSnippet;
        if (_isFavorite) {
          final favoriteRequest = UpdateSnippetFavoriteRequest(
            snippetId: newSnippet.id,
            isFavorite: _isFavorite,
          );
          await _snippetRepository.updateSnippetFavorite(favoriteRequest);
          
          // 更新本地片段数据的收藏状态
          finalSnippet = newSnippet.copyWith(isFavorite: _isFavorite);
        }
        
        // 在widget可能被移除前，先更新状态并显示消息
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('片段创建成功', style: WebTheme.bodyMedium.copyWith(color: WebTheme.white)),
              backgroundColor: WebTheme.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
        
        // 触发事件总线，通知片段列表刷新
        EventBus.instance.fire(SnippetCreatedEvent(snippet: finalSnippet));
        
        // 最后调用回调，因为这可能会关闭widget
        widget.onSaved?.call(finalSnippet);
      } else {
        // 更新现有片段
        // 更新标题
        if (_titleController.text != widget.snippet.title) {
          final titleRequest = UpdateSnippetTitleRequest(
            snippetId: widget.snippet.id,
            title: _titleController.text,
            changeDescription: '更新标题',
          );
          await _snippetRepository.updateSnippetTitle(titleRequest);
        }

        // 更新内容
        if (_contentController.text != widget.snippet.content) {
          final contentRequest = UpdateSnippetContentRequest(
            snippetId: widget.snippet.id,
            content: _contentController.text,
            changeDescription: '更新内容',
          );
          await _snippetRepository.updateSnippetContent(contentRequest);
        }

        // 更新收藏状态
        if (_isFavorite != widget.snippet.isFavorite) {
          final favoriteRequest = UpdateSnippetFavoriteRequest(
            snippetId: widget.snippet.id,
            isFavorite: _isFavorite,
          );
          await _snippetRepository.updateSnippetFavorite(favoriteRequest);
        }

        // 获取最新的片段数据
        final updatedSnippet = await _snippetRepository.getSnippetDetail(widget.snippet.id);
        
        // 在widget可能被移除前，先更新状态并显示消息
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('片段保存成功', style: WebTheme.bodyMedium.copyWith(color: WebTheme.white)),
              backgroundColor: WebTheme.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
        
        // 最后调用回调，因为这可能会关闭widget
        widget.onSaved?.call(updatedSnippet);
      }
    } catch (e) {
      AppLogger.e('FloatingSnippetEditor', '保存片段失败', e);
      
      // 检查widget是否仍然mounted，再进行UI更新
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
      
      // 处理具体错误类型
      String errorMessage = _formatUserFriendlyError(e);
      
      // 如果是标题验证错误，更新UI状态
      if (e.toString().contains('片段标题不能为空') || e.toString().contains('标题不能为空')) {
        setState(() {
          _titleError = true;
          _titleErrorText = '片段标题不能为空';
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage, style: WebTheme.bodyMedium.copyWith(color: WebTheme.white)),
            backgroundColor: WebTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  Future<void> _deleteSnippet() async {
    final confirmed = await _showDeleteConfirmDialog();
    if (!confirmed) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      await _snippetRepository.deleteSnippet(widget.snippet.id);
      
      // 在widget可能被移除前，先更新状态并显示消息
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('片段删除成功', style: WebTheme.bodyMedium.copyWith(color: WebTheme.white)),
            backgroundColor: WebTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
      
      // 最后调用回调，因为这可能会关闭widget
      widget.onDeleted?.call(widget.snippet.id);
    } catch (e) {
      AppLogger.e('FloatingSnippetEditor', '删除片段失败', e);
      
      // 检查widget是否仍然mounted，再进行UI更新
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败: $e', style: WebTheme.bodyMedium.copyWith(color: WebTheme.white)),
            backgroundColor: WebTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  Future<bool> _showDeleteConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WebTheme.isDarkMode(context) ? WebTheme.darkCard : WebTheme.lightCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '确认删除',
          style: WebTheme.titleMedium.copyWith(
            color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey900 : WebTheme.grey900,
          ),
        ),
        content: Text(
          '确定要删除片段"${widget.snippet.title}"吗？此操作无法撤销。',
          style: WebTheme.bodyMedium.copyWith(
            color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey700 : WebTheme.grey700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '取消',
              style: WebTheme.labelMedium.copyWith(
                color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey600 : WebTheme.grey600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: WebTheme.error),
            child: Text(
              '删除',
              style: WebTheme.labelMedium.copyWith(color: WebTheme.error),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 将技术性错误转换为用户友好的错误消息
  String _formatUserFriendlyError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    // 验证相关错误
    if (errorString.contains('片段标题不能为空') || errorString.contains('标题不能为空')) {
      return '请输入片段标题';
    }
    
    // 网络相关错误
    if (errorString.contains('connection') || errorString.contains('network') || errorString.contains('timeout')) {
      return '网络连接失败，请检查网络后重试';
    }
    
    // 认证相关错误
    if (errorString.contains('unauthorized') || errorString.contains('401') || errorString.contains('authentication')) {
      return '登录状态已过期，请重新登录';
    }
    
    // 服务器错误
    if (errorString.contains('500') || errorString.contains('server') || errorString.contains('internal')) {
      return '服务器暂时无法访问，请稍后重试';
    }
    
    // 权限相关错误
    if (errorString.contains('forbidden') || errorString.contains('403')) {
      return '没有权限执行此操作';
    }
    
    // 验证错误
    if (errorString.contains('validation') || errorString.contains('invalid')) {
      // 尝试提取具体的验证错误信息
      if (error.toString().contains('ApiException:')) {
        final message = error.toString().split('ApiException:').last.trim();
        if (message.isNotEmpty) {
          return message;
        }
      }
      return '输入信息有误，请检查后重新提交';
    }
    
    // 默认友好错误消息
    return '操作失败，请稍后重试';
  }

  @override
  Widget build(BuildContext context) {

    return Container(
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context), // 🚀 修复：使用动态表面色
        borderRadius: BorderRadius.circular(12),
        border: WebTheme.isDarkMode(context)
          ? Border.all(color: WebTheme.darkGrey300, width: 1)
          : Border.all(color: WebTheme.grey300, width: 1),
        boxShadow: [
          BoxShadow(
            color: WebTheme.getShadowColor(context, opacity: 0.2),
            offset: const Offset(0, 8),
            blurRadius: 32,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          // 头部：标题输入框和操作按钮
          _buildHeader(),
          
          // 内容区域
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: WebTheme.getSurfaceColor(context), // 🚀 修复：使用动态表面色
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(
            color: WebTheme.getShadowColor(context, opacity: 0.05),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          // 标题输入框
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: _titleError 
                      ? Border.all(color: WebTheme.error, width: 1.5)
                      : null,
                  ),
                  child: TextField(
                    controller: _titleController,
                    onChanged: (value) {
                      // 用户开始输入时清除错误状态
                      if (_titleError && value.trim().isNotEmpty) {
                        setState(() {
                          _titleError = false;
                          _titleErrorText = null;
                        });
                      }
                    },
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: WebTheme.getTextColor(context),
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Name your snippet...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: _titleError 
                          ? WebTheme.error.withOpacity(0.7)
                          : WebTheme.getSecondaryTextColor(context),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                // 错误提示文本
                if (_titleError && _titleErrorText != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 2),
                    child: Text(
                      _titleErrorText!,
                      style: TextStyle(
                        fontSize: 12,
                        color: WebTheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // 收藏按钮
          _buildIconButton(
            icon: _isFavorite ? Icons.star : Icons.star_border,
            onPressed: () => setState(() => _isFavorite = !_isFavorite),
            color: _isFavorite ? Theme.of(context).colorScheme.tertiary : WebTheme.getSecondaryTextColor(context),
          ),
          
          // 更多操作按钮
          _buildIconButton(
            icon: Icons.more_vert,
            onPressed: _showMoreOptions,
            color: WebTheme.getSecondaryTextColor(context),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    
    return Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.only(left: 6),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 20,
          color: color ?? WebTheme.getSecondaryTextColor(context),
        ),
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  void _showMoreOptions() {
    // 显示更多选项菜单
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: WebTheme.getSurfaceColor(context), // 🚀 修复：使用动态表面色
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.snippet.id.isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: const Text('删除片段'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteSnippet();
                },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('关闭'),
              onTap: () {
                Navigator.pop(context);
                widget.onClose?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    
    return Column(
      children: [
        // 内容编辑区域
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border.all(
                color: WebTheme.isDarkMode(context) ? WebTheme.darkGrey300 : WebTheme.grey300,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: TextField(
              controller: _contentController,
              maxLines: null,
              expands: true,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: WebTheme.getTextColor(context),
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '请输入内容...',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: WebTheme.getSecondaryTextColor(context),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        
        // 底部状态栏
        _buildFooter(),
      ],
    );
  }

  Widget _buildFooter() {
    final wordCount = _contentController.text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 字数统计
          Text(
            '$wordCount Words',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: WebTheme.getSecondaryTextColor(context),
            ),
          ),
          
          const Spacer(),
          
          // 功能按钮
          _buildFooterButton(
            icon: Icons.history,
            label: 'History',
            onPressed: () {
              // TODO: 实现历史记录功能
            },
          ),
          
          const SizedBox(width: 8),
          
          _buildFooterButton(
            icon: Icons.content_copy,
            label: 'Copy',
            onPressed: () {
              // TODO: 实现复制功能
            },
          ),
          
          const SizedBox(width: 8),
          
          // 保存按钮
          _buildSaveButton(),
        ],
      ),
    );
  }

  Widget _buildFooterButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: WebTheme.getSecondaryTextColor(context),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: WebTheme.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return InkWell(
      onTap: _saveSnippet,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
              Icon(
              widget.snippet.id.isEmpty ? Icons.add : Icons.save,
              size: 14,
                color: WebTheme.getPrimaryColor(context),
            ),
            const SizedBox(width: 4),
            Text(
              widget.snippet.id.isEmpty ? 'Create' : 'Save',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: WebTheme.getPrimaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 兼容性：保留原有的 SnippetEditForm 类，避免破坏现有代码
@Deprecated('请使用 FloatingSnippetEditor.show() 代替')
class SnippetEditForm extends StatelessWidget {
  final NovelSnippet snippet;
  final VoidCallback? onClose;
  final Function(NovelSnippet)? onSaved;
  final Function(String)? onDeleted;

  const SnippetEditForm({
    super.key,
    required this.snippet,
    this.onClose,
    this.onSaved,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    // 直接返回一个空容器，因为现在使用 FloatingSnippetEditor
    return const SizedBox.shrink();
  }
} 