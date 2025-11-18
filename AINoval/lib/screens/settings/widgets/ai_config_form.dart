import 'package:ainoval/blocs/ai_config/ai_config_bloc.dart';
// import 'package:ainoval/models/ai_model_group.dart';
import 'package:ainoval/models/user_ai_model_config_model.dart';
import 'package:ainoval/models/ai_model_group.dart';
import 'package:ainoval/screens/settings/widgets/model_group_list.dart';
import 'package:ainoval/screens/settings/widgets/provider_list.dart';
import 'package:ainoval/screens/settings/widgets/searchable_model_dropdown.dart';
import 'package:ainoval/widgets/common/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
// Removed import causing linter error
// Placeholder for localization, replace with your actual import
// import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class AiConfigForm extends StatefulWidget {
  // Callback when cancel is pressed
  // Optional: Callback on successful save if specific action needed besides hiding form
  // final VoidCallback? onSaveSuccess;

  const AiConfigForm({
    super.key,
    required this.userId,
    required this.onCancel,
    this.configToEdit,
    // this.onSaveSuccess,
  });
  final UserAIModelConfigModel? configToEdit;
  final String userId;
  final VoidCallback onCancel;

  @override
  State<AiConfigForm> createState() => _AiConfigFormState();
}

class _AiConfigFormState extends State<AiConfigForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _aliasController;
  late TextEditingController _apiKeyController;
  late TextEditingController _apiEndpointController;

  String? _selectedProvider;
  String? _selectedModel;
  ModelListingCapability? _providerCapability; // New: Store capability
  bool _isLoadingProviders = false;
  bool _isLoadingModels = false;
  bool _isTestingApiKey = false; // New: Track API key testing
  bool _apiKeyTestSuccess = false; // New: Track API key test success for current provider
  bool _isSaving = false; // Track internal saving state
  bool _showApiKey = false; // 控制API Key是否显示

  List<String> _providers = [];
  List<String> _models = [];
  String _modelSearch = '';

  // 校验错误状态
  bool _providerError = false;
  bool _modelError = false;
  bool _apiKeyError = false;
  String? _providerErrorText;
  String? _modelErrorText;
  String? _apiKeyErrorText;

  bool get _isEditMode => widget.configToEdit != null;

  @override
  void initState() {
    super.initState();
    // Initialize controllers
    _aliasController =
        TextEditingController(text: widget.configToEdit?.alias ?? '');
    // 编辑模式下回显API Key，新增模式下保持空白
    _apiKeyController = TextEditingController(
      text: _isEditMode ? (widget.configToEdit?.apiKey ?? '') : ''
    );
    _apiEndpointController =
        TextEditingController(text: widget.configToEdit?.apiEndpoint ?? '');

    // Initialize state based on edit mode
    if (_isEditMode) {
      _selectedProvider = widget.configToEdit?.provider;
      _selectedModel = widget.configToEdit?.modelName;
      // Don't prefill API Key from edit mode
      _apiEndpointController.text = widget.configToEdit?.apiEndpoint ?? '';
      _aliasController.text = widget.configToEdit?.alias ?? '';
    } else {
      _selectedProvider = null;
      _selectedModel = null;
      _providers = [];
      _models = [];
       _apiEndpointController.text = '';
       _apiKeyController.text = '';
       _aliasController.text = '';
    }

    // Use context safely after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return; // Check mount status
      final bloc = context.read<AiConfigBloc>();

      // Pre-populate provider list from bloc state if available
      if (_providers.isEmpty) {
        _providers = bloc.state.availableProviders;
      }

      // Always load providers on init
      _loadProviders();

      // If a provider is selected (edit mode or restored state), load its capability
      // 在编辑模式下跳过能力加载和自动填充，避免不必要的API Key验证
      if (_selectedProvider != null && !_isEditMode) {
         print("InitState: Provider '$_selectedProvider' selected, loading capability.");
         bloc.add(LoadProviderCapability(providerName: _selectedProvider!));
         // Model loading will now be handled by the BlocListener based on capability
         // Also try to load default config info
         _autoFillApiInfo(_selectedProvider!);
      }

      // --- Trigger loading ---
      // Always try to load providers when the form inits,
      // as the list might be stale or empty (especially in add mode).
      // The BlocListener will handle the loading indicator state.
      //_loadProviders(); // Moved up

      // Model loading logic is now primarily driven by provider capability
      // and API key testing results handled in the BlocListener.
    });
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _apiKeyController.dispose();
    _apiEndpointController.dispose();
    // Don't clear models here as the Bloc state might be needed elsewhere
    // context.read<AiConfigBloc>().add(ClearProviderModels());
    super.dispose();
  }

  void _loadProviders() {
    if (!mounted) return; // Check if widget is still in the tree
    setState(() {
      _isLoadingProviders = true;
    });
    context.read<AiConfigBloc>().add(const LoadAvailableProviders()); // Corrected call
  }

  // 已由 Bloc 驱动加载模型，保留旧方法注释避免误用
  // void _loadModels(String provider) {}

  void _submitForm() {
    // 清除之前的错误状态
    setState(() {
      _providerError = false;
      _modelError = false;
      _apiKeyError = false;
      _providerErrorText = null;
      _modelErrorText = null;
      _apiKeyErrorText = null;
    });

    // 执行校验
    bool hasError = false;

    // 在添加模式下校验提供商选择
    if (!_isEditMode && _selectedProvider == null) {
      setState(() {
        _providerError = true;
        _providerErrorText = '请选择一个提供商';
      });
      hasError = true;
    }

    // 在添加模式下校验模型选择（允许直接使用输入框文本）
    String? modelCandidate = _selectedModel;
    if (modelCandidate == null || modelCandidate.trim().isEmpty) {
      if (_modelSearch.trim().isNotEmpty) {
        modelCandidate = _modelSearch.trim();
        // 同步为选中模型，避免后续被清空
        _selectedModel = modelCandidate;
      }
    }
    if (!_isEditMode && (modelCandidate == null || modelCandidate.trim().isEmpty)) {
      setState(() {
        _modelError = true;
        _modelErrorText = '请选择一个模型';
      });
      hasError = true;
    }

    // 校验API Key（在添加模式下，如果提供商需要API Key）
    if (!_isEditMode && 
        _providerCapability == ModelListingCapability.listingWithKey && 
        _apiKeyController.text.trim().isEmpty) {
      setState(() {
        _apiKeyError = true;
        _apiKeyErrorText = '该提供商需要 API 密钥';
      });
      hasError = true;
    }

    // 检查重复的已验证配置（仅在添加模式）
    if (!_isEditMode && _selectedProvider != null && modelCandidate != null && modelCandidate.trim().isNotEmpty) {
      final existingConfigs = context.read<AiConfigBloc>().state.configs;
      final isDuplicateValidated = existingConfigs.any((config) =>
          config.provider == _selectedProvider &&
          config.modelName == modelCandidate &&
          config.isValidated);

      if (isDuplicateValidated) {
        setState(() {
          _modelError = true;
          _modelErrorText = '已存在该模型的已验证配置，无法重复添加';
        });
        hasError = true;
      }
    }

    // 如果有错误，不执行提交
    if (hasError) {
      return;
    }

    // 执行表单验证
    if (_formKey.currentState!.validate()) {
       setState(() {
         _isSaving = true;
       });
      final bloc = context.read<AiConfigBloc>();

      // 处理API密钥
      String? apiKey = _apiKeyController.text.trim();
      if (apiKey.isEmpty) {
        apiKey = null;
      }

      if (_isEditMode) {
        bloc.add(UpdateAiConfig(
          userId: widget.userId,
          configId: widget.configToEdit!.id,
          alias: _aliasController.text.trim().isEmpty
              ? null
              : _aliasController.text.trim(),
          apiKey: apiKey, // Pass null if empty to potentially clear/not update
          apiEndpoint:
              _apiEndpointController.text.trim(), // Send empty string to clear
        ));
      } else {
        bloc.add(AddAiConfig(
          userId: widget.userId,
          provider: _selectedProvider!,
          modelName: modelCandidate!,
          apiKey: apiKey ?? "", // Backend likely expects non-null, pass empty string
          alias: _aliasController.text.trim().isEmpty
              ? modelCandidate // Default alias to model name if empty
              : _aliasController.text.trim(),
          apiEndpoint: _apiEndpointController.text.trim(),
        ));
      }
      // The BlocListener in SettingsPanel will handle hiding the form on success/error
    }
  }

  // 处理模型选择
  void _handleModelSelected(String model) {
    setState(() {
      _selectedModel = model;
      // 回填到搜索输入由受控 value 完成
      _modelError = false;
      _modelErrorText = null;
      if (_aliasController.text.isEmpty) {
        _aliasController.text = model;
      }
      // 同步搜索关键字，确保下方列表过滤一致
      _modelSearch = model;
    });
  }

  // 旧的“添加自定义模型”对话框流程已取消，改为在上方搜索框直接输入并选择

  // 检查是否存在已验证的相同模型
  // 重复校验逻辑由提交阶段处理
  // bool _isDuplicateValidatedModel() { return false; }

  // 获取已验证模型列表
  List<String> _getVerifiedModels(String provider) {
    final existingConfigs = context.read<AiConfigBloc>().state.configs;
    return existingConfigs
        .where((config) => config.provider == provider && config.isValidated)
        .map((config) => config.modelName)
        .toList();
  }

  // Modify provider selection handler
  void _handleProviderSelected(String provider) {
    print('️Provider selected: $provider');
    if (provider != _selectedProvider) {
      setState(() {
        _selectedProvider = provider;
        _selectedModel = null; // Reset model selection
        _providerCapability = null; // Reset capability
        _apiKeyTestSuccess = false; // Reset API key test status
        _isTestingApiKey = false; // Reset testing flag
        _models = []; // Clear model list
        _isLoadingModels = false; // Reset loading models flag
        // 清除错误状态
        _providerError = false;
        _modelError = false;
        _apiKeyError = false;
        _providerErrorText = null;
        _modelErrorText = null;
        _apiKeyErrorText = null;
        // Clear previous provider's info only in Add mode
        if (!_isEditMode) {
           _apiEndpointController.text = '';
           _apiKeyController.text = '';
           _aliasController.text = ''; // Clear alias too
        }
         _showApiKey = false; // Hide API key on provider change
      });

      // Trigger loading capability for the new provider
      context.read<AiConfigBloc>().add(LoadProviderCapability(providerName: provider));

      // Trigger auto-fill for the new provider
      // 编辑模式下不触发自动填充
      if (!_isEditMode) {
        _autoFillApiInfo(provider);
      }
    }
  }

  // 切换API Key的显示/隐藏
  void _toggleApiKeyVisibility() {
    setState(() {
      _showApiKey = !_showApiKey;
    });
  }

  // 自动填充API信息
  void _autoFillApiInfo(String provider) {
    // 编辑模式下不需要自动填充，避免触发不必要的API Key验证
    if (_isEditMode) return;
    
    // 发送获取该提供商默认配置的事件
    // 实际的填充操作会在BlocListener中根据状态变化处理
    print('⚠️ 调用_autoFillApiInfo，provider=$provider');
    context.read<AiConfigBloc>().add(GetProviderDefaultConfig(provider: provider));
  }

  // New method to handle API Key test button press
  void _testApiKey() {
    final apiKey = _apiKeyController.text.trim();
    final apiEndpoint = _apiEndpointController.text.trim().isEmpty
        ? null
        : _apiEndpointController.text.trim();

    if (_selectedProvider != null && apiKey.isNotEmpty) {
       // Set testing state in UI immediately
       // No need to call setState here as BlocListener will handle it
       context.read<AiConfigBloc>().add(TestApiKey(
          providerName: _selectedProvider!,
          apiKey: apiKey,
          apiEndpoint: apiEndpoint,
          modelName: _selectedModel, // 传递当前选择的模型
       ));
    } else {
      // Show feedback if provider or key is missing
       TopToast.warning(context, '请先选择提供商并输入 API 密钥');
    }
  }

  // 直连获取模型（无需后端）
  void _directFetchModels() {
    final provider = _selectedProvider;
    if (provider == null) {
      TopToast.warning(context, '请先选择提供商');
      return;
    }
    final apiKey = _apiKeyController.text.trim();
    final apiEndpoint = _apiEndpointController.text.trim().isEmpty
        ? null
        : _apiEndpointController.text.trim();

    // 前置校验：对于大多数提供商，直连需要 API 接口地址
    if (_needsEndpointForDirectFetch(provider) && (apiEndpoint == null || apiEndpoint.isEmpty)) {
      TopToast.warning(context, '请先填写 API 接口地址，再进行直连获取模型');
      return;
    }
    // 特例：Gemini 强制需要 API Key
    if (provider.toLowerCase() == 'gemini' && apiKey.isEmpty) {
      TopToast.warning(context, 'Gemini 直连需要 API 密钥，请先填写');
      return;
    }

    setState(() {
      _isLoadingModels = true;
      _models = [];
    });

    context.read<AiConfigBloc>().add(LoadModelsDirect(
      providerName: provider,
      apiKey: apiKey.isEmpty ? null : apiKey,
      apiEndpoint: apiEndpoint,
    ));
  }

  bool _needsEndpointForDirectFetch(String provider) {
    final p = provider.toLowerCase();
    // 本地/自托管默认端口可不填
    if (p == 'lmstudio' || p == 'ollama') return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AiConfigBloc, AiConfigState>(
      listener: (context, state) {
        if (!mounted) return;

        bool needsSetState = false;

        // --- Provider Loading & List Update ---
        if (_isLoadingProviders &&
            (state.availableProviders.isNotEmpty ||
                state.errorMessage != null && state.status != AiConfigStatus.loading)) {
          _isLoadingProviders = false;
          needsSetState = true;
        }
        if (!listEquals(_providers, state.availableProviders)) {
          _providers = state.availableProviders;
          needsSetState = true;
        }

        // --- Provider Capability Update ---
        if (state.providerCapability != _providerCapability && state.selectedProviderForModels == _selectedProvider) {
           _providerCapability = state.providerCapability;
           print("Listener: Capability updated for $_selectedProvider: $_providerCapability");
           needsSetState = true;
           // Note: Model loading based on capability is handled in the BLoC event handler itself now.
        }

        // --- Model Loading & List Update ---
        if (state.selectedProviderForModels == _selectedProvider) {
           if (_isLoadingModels &&
               (state.modelsForProviderInfo.isNotEmpty ||
                   state.errorMessage != null)) {
             _isLoadingModels = false;
             needsSetState = true;
           }
           final List<String> nextModels = state.modelsForProviderInfo.map((m) => m.id).toList();
           if (!listEquals(_models, nextModels)) {
             _models = nextModels;
             // 保留用户输入的自定义模型选择，即使不在列表中
             needsSetState = true;
           }
         } else if (_isLoadingModels) {
           // If the selected provider changed while models were loading, stop loading indicator
           _isLoadingModels = false;
           needsSetState = true;
         }

        // --- API 密钥测试状态更新 ---
         if (state.isTestingApiKey != _isTestingApiKey) {
            _isTestingApiKey = state.isTestingApiKey;
            // If we *start* testing (used for loading models with key), set loading state
            if (_isTestingApiKey) {
               _isLoadingModels = true;
            }
            needsSetState = true;
         }
         // Check if success is for the *currently selected* provider and non-null
        final testSuccessForCurrentProvider = state.apiKeyTestSuccessProvider != null && state.apiKeyTestSuccessProvider == _selectedProvider;
        if (testSuccessForCurrentProvider != _apiKeyTestSuccess) {
           _apiKeyTestSuccess = testSuccessForCurrentProvider;
           if (_apiKeyTestSuccess) {
              _isLoadingModels = false; // <-- Reset loading state on success
           }
           needsSetState = true;
        }
        // 处理 API 密钥测试错误
        if (state.apiKeyTestError != null) {
           print("Listener: API Key test FAILED for $_selectedProvider: ${state.apiKeyTestError}");
           _isLoadingModels = false; // <-- Reset loading state on error
           TopToast.error(context, 'API 密钥测试失败: ${state.apiKeyTestError}');
           // Clear the error in the bloc state? This should maybe be done in the bloc itself after emitting.
           // context.read<AiConfigBloc>().add(ClearApiKeyTestError()); // Need this event/logic in BLoC
           needsSetState = true; // Need to rebuild to potentially remove loading indicator
        }

        // --- Default Config Auto-fill Update ---
         if (_selectedProvider != null) {
           final defaultConfig = state.providerDefaultConfigs[_selectedProvider!];
           if (defaultConfig != null && defaultConfig.id.isNotEmpty) {
             if (!_isEditMode) {
               bool filledSomething = false;
               if (_apiEndpointController.text.isEmpty && defaultConfig.apiEndpoint.isNotEmpty) {
                 _apiEndpointController.text = defaultConfig.apiEndpoint;
                 filledSomething = true;
               }
               if (_apiKeyController.text.isEmpty && (defaultConfig.apiKey?.isNotEmpty ?? false)) {
                 _apiKeyController.text = defaultConfig.apiKey!;
                 _showApiKey = true;
                 filledSomething = true;
                 // If auto-filled API key, consider it "tested" for UI purposes,
                 // but a real test might still be needed depending on workflow.
                 // _apiKeyTestSuccess = true; // Maybe set this? Or require manual test? Let's require manual test for now.
               }
               if(filledSomething) needsSetState = true;
             }
           }
         }

        // --- Saving State Update ---
        if (_isSaving && state.actionStatus != AiConfigActionStatus.loading) {
          if (state.actionStatus == AiConfigActionStatus.success) {
            widget.onCancel();
          }
          // Error toast is handled by the listener in SettingsPanel
          _isSaving = false;
          needsSetState = true;
        }

        if (needsSetState) {
          setState(() {});
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Form(
          key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // 标题
                Text(
                  _isEditMode ? '编辑模型服务' : '添加新模型服务',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),

                // 主要内容区域 - 左右布局
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左侧提供商列表
                      if (!_isEditMode) // 在编辑模式下不显示左侧列表
                        SizedBox(
                          width: 180,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ProviderList(
                                  providers: _providers,
                                  selectedProvider: _selectedProvider,
                                  onProviderSelected: _handleProviderSelected,
                                ),
                              ),
                              // 提供商选择错误提示
                              if (_providerError && _providerErrorText != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4, left: 8),
                                  child: Text(
                                    _providerErrorText!,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.error,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      
                      if (!_isEditMode)
                        const SizedBox(width: 16),
                      
                      // 右侧配置区域
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Provider显示（仅编辑模式）
                            if (_isEditMode && _selectedProvider != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  '提供商: $_selectedProvider',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                            // 模型搜索框（仅添加模式）
                            if (!_isEditMode && _selectedProvider != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '选择模型',
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: _modelError 
                                            ? Theme.of(context).colorScheme.error
                                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: 36,
                                      decoration: _modelError ? BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Theme.of(context).colorScheme.error,
                                          width: 1.5,
                                        ),
                                      ) : null,
                                      child: SearchableModelDropdown(
                                        models: _models,
                                        onModelSelected: _handleModelSelected,
                                        hintText: '输入模型ID或搜索模型',
                                        value: _selectedModel,
                                        onCreateCustom: (customName) async {
                                          // 仅设置为已选模型，走统一的“添加”提交流程，避免双重提交
                                          setState(() {
                                            _selectedModel = customName;
                                            _modelError = false;
                                            _modelErrorText = null;
                                            if (_aliasController.text.isEmpty) {
                                              _aliasController.text = customName;
                                            }
                                          });
                                          TopToast.info(context, '已选择模型: $customName');
                                        },
                                        onSearchChanged: (kw) {
                                          setState(() { _modelSearch = kw.trim(); });
                                        },
                                      ),
                                    ),
                                    // 模型选择错误提示
                                    if (_modelError && _modelErrorText != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          _modelErrorText!,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.error,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                            // 取消“已选模型: xxx”的提示展示，改为直接回填输入框
                            
                            // 模型显示（仅编辑模式）
                            if (_isEditMode && _selectedModel != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  '模型: $_selectedModel',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                            // 别名输入框
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '别名 (可选)',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: 36,
                child: TextFormField(
                  controller: _aliasController,
                                      style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                                        hintText: '例如：我的 ${_selectedModel ?? '模型'}',
                                        hintStyle: TextStyle(
                                          fontSize: 13,
                                          color: Theme.of(context).hintColor.withOpacity(0.7),
                                        ),
                    border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                                            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                        width: 1.0,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                                            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                        width: 1.0,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12, 
                                          vertical: 0
                                        ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                                          ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3)
                                          : Theme.of(context).colorScheme.surfaceContainerLowest.withOpacity(0.7),
                                      ),
                                    ),
                    ),
                  ],
                ),
                            ),

                            // API Key输入框
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'API 密钥',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: _apiKeyError
                                          ? Theme.of(context).colorScheme.error
                                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center, // Align items vertically
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: 36, // Keep height consistent
                                          child: TextFormField(
                                            controller: _apiKeyController,
                                            obscureText: !_showApiKey,
                                            style: Theme.of(context).textTheme.bodyMedium,
                                            decoration: InputDecoration(
                                              hintText: _isEditMode ? '当前API密钥 (可修改)' : '输入您的API密钥',
                                              hintStyle: TextStyle(
                                                fontSize: 13,
                                                color: Theme.of(context).hintColor.withOpacity(0.7),
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: BorderSide(
                                                  color: _apiKeyError 
                                                      ? Theme.of(context).colorScheme.error
                                                      : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                                                  width: _apiKeyError ? 1.5 : 1.0,
                                                ),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: BorderSide(
                                                  color: _apiKeyError 
                                                      ? Theme.of(context).colorScheme.error
                                                      : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                                                  width: _apiKeyError ? 1.5 : 1.0,
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: BorderSide(
                                                  color: _apiKeyError 
                                                      ? Theme.of(context).colorScheme.error
                                                      : Theme.of(context).colorScheme.primary,
                                                  width: 1.5,
                                                ),
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 0, // Adjust vertical padding if needed
                                              ),
                                              filled: true,
                                              fillColor: Theme.of(context).brightness == Brightness.dark
                                                  ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3)
                                                  : Theme.of(context).colorScheme.surfaceContainerLowest.withOpacity(0.7),
                                              suffixIcon: IconButton(
                                                icon: Icon(
                                                  _showApiKey ? Icons.visibility_off : Icons.visibility,
                                                  size: 18,
                                                ),
                                                onPressed: _toggleApiKeyVisibility,
                                              ),
                                            ),
                                            validator: (value) {
                                              // Require API key in add mode only if provider capability mandates it
                                              if (!_isEditMode &&
                                                  _providerCapability == ModelListingCapability.listingWithKey &&
                                                  (value == null || value.trim().isEmpty)) {
                                                return '需要 API 密钥';
                                              }
                                              return null;
                                            },
                                            onChanged: (_) {
                                              // Reset test success status if key changes
                                              if (_apiKeyTestSuccess) {
                                                setState(() { _apiKeyTestSuccess = false; });
                                              }
                                              // 清除API Key错误状态
                                              if (_apiKeyError) {
                                                setState(() {
                                                  _apiKeyError = false;
                                                  _apiKeyErrorText = null;
                                                });
                                              }
                                               // Trigger rebuild to potentially enable/disable test button
                                              setState(() {});
                                            },
                                          ),
                                        ),
                                      ),

                                      // API 密钥测试按钮与状态
                                      if (_selectedProvider != null && _providerCapability == ModelListingCapability.listingWithKey)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 8.0),
                                          child: SizedBox(
                                            height: 36, // Match TextFormField height
                                            child: _isTestingApiKey
                                              ? const SizedBox( // Show loading indicator, but don't rebuild on test success, to avoid flicker
                                                  width: 36, height: 36,
                                                  child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                                                )
                                              : (_apiKeyTestSuccess
                                                  ? const Tooltip(
                                                      message: 'API 密钥已验证',
                                                      child: Icon( // Show success icon
                                                          Icons.check_circle, color: Colors.green, size: 24),
                                                    )
                                                  : TextButton( // Show test button
                                                      // Disable button if API key field is empty
                                                      onPressed: _apiKeyController.text.trim().isEmpty ? null : _testApiKey,
                                                      style: TextButton.styleFrom(
                                                         padding: const EdgeInsets.symmetric(horizontal: 12),
                                                         minimumSize: Size(0, 36), // Ensure height matches
                                                         // Dim text color if disabled
                                                         foregroundColor: _apiKeyController.text.trim().isEmpty ? Theme.of(context).disabledColor : null,
                                                      ),
                                                      child: const Text('测试', style: TextStyle(fontSize: 13)),
                                                    )
                                              ),
                                          ),
                                        ),
                                    ],
                                  ),

                                  // API 密钥错误提示
                                  if (_apiKeyError && _apiKeyErrorText != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        _apiKeyErrorText!,
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.error,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),

                                  // Auto-fill prompt adjusted
                                  if (!_isEditMode && _selectedProvider != null && _providerCapability == ModelListingCapability.listingWithKey && !_apiKeyError)
                                    BlocBuilder<AiConfigBloc, AiConfigState>(
                                      builder: (context, state) {
                                        final defaultConfig = state.getProviderDefaultConfig(_selectedProvider!);
                                        final hasFilledApiKey = _apiKeyController.text.isNotEmpty;
                                        // Show prompt only if key was auto-filled AND not yet tested successfully
                                        if (defaultConfig != null && defaultConfig.id.isNotEmpty && (defaultConfig.apiKey?.isNotEmpty ?? false) && hasFilledApiKey && !_apiKeyTestSuccess) {
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Row(
                                              children: [
                                                Icon(Icons.info_outline, size: 14, color: Colors.blue),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text('已自动填充API密钥，请测试连接', style: TextStyle(fontSize: 12, color: Colors.blue)),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                ],
                              ),
                            ),

                            // API Endpoint输入框
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'API 接口地址（可选）',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: 36,
                child: TextFormField(
                  controller: _apiEndpointController,
                                            style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                                              hintText: '例如：https://api.openai.com/v1',
                                              hintStyle: TextStyle(
                                                fontSize: 13,
                                                color: Theme.of(context).hintColor.withOpacity(0.7),
                                              ),
                    border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                                                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                        width: 1.0,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                                                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                        width: 1.0,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                                                horizontal: 12, 
                                                vertical: 0
                                              ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                                                ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3)
                                                : Theme.of(context).colorScheme.surfaceContainerLowest.withOpacity(0.7),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  
                                  // 如果有该提供商的已配置API地址，显示提示
                                  if (!_isEditMode && _selectedProvider != null)
                                    BlocBuilder<AiConfigBloc, AiConfigState>(
                                      builder: (context, state) {
                                        final defaultConfig = state.getProviderDefaultConfig(_selectedProvider!);
                                        if (defaultConfig != null && defaultConfig.id.isNotEmpty && defaultConfig.apiEndpoint.isNotEmpty) {
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.info_outline,
                                                  size: 14,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    '已使用该提供商的API地址: ${defaultConfig.apiEndpoint}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Theme.of(context).colorScheme.primary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                ],
                              ),
                            ),

                            // 模型分组列表（仅在选择了提供商时显示）
                            if (!_isEditMode && _selectedProvider != null && !_isLoadingModels)
                              Expanded(  // 将原来的Column改为Expanded
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10.0, bottom: 4.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('可用模型', style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w500,
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                                            fontSize: 13,
                                          )),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // 刷新按钮
                                              IconButton(
                                                icon: const Icon(Icons.refresh, size: 16),
                                                onPressed: () {
                                                  if (_selectedProvider != null) {
                                                    // 清除该提供商的缓存并重新加载
                                                    context.read<AiConfigBloc>().add(ClearModelsCache(provider: _selectedProvider));
                                                    context.read<AiConfigBloc>().add(LoadModelsForProvider(provider: _selectedProvider!));
                                                  }
                                                },
                                                tooltip: '刷新模型列表',
                                                style: IconButton.styleFrom(
                                                  padding: const EdgeInsets.all(4),
                                                  minimumSize: const Size(24, 24),
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              // 直连获取模型
                                              TextButton.icon(
                                                icon: const Icon(Icons.cloud_download, size: 14),
                                                label: const Text('直连获取模型', style: TextStyle(fontSize: 12)),
                                                style: TextButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  minimumSize: const Size(0, 30),
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                                onPressed: _directFetchModels,
                                              ),
                                              const SizedBox(width: 4),
                                              // 移除单独“添加自定义模型”按钮，改为在搜索框中直接添加
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Container to provide background and border for the list area
                                    Expanded(  // 将Container包装在Expanded中，使其填充剩余空间
                                      child: Container(
                                         width: double.infinity,
                                         decoration: BoxDecoration(
                                           color: Theme.of(context).brightness == Brightness.dark
                                                 ? Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.5)
                                                 : Theme.of(context).colorScheme.surfaceContainerLow.withOpacity(0.7),
                                           borderRadius: BorderRadius.circular(8),
                                           border: Border.all(
                                             color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                                             width: 0.5,
                                           ),
                                         ),
                                         child: BlocBuilder<AiConfigBloc, AiConfigState>(
                                          builder: (context, state) {
                                            // Safely access model group using the selected provider key
                                            // NOTE: Assuming AIModelGroup and ModelListingCapability are correctly defined/imported elsewhere
                                            //       after resolving the 'ai_config_repository' dependency.
                                            final modelGroup = _selectedProvider != null ? state.modelGroups[_selectedProvider!] : null;
                                            // final currentCapability = _providerCapability; // local capability (unused)
                                            // 获取该提供商下已经验证的模型列表
                                            final verifiedModels = _selectedProvider != null ? _getVerifiedModels(_selectedProvider!) : <String>[];

                                            if (_isLoadingModels) {
                                              return const Center(
                                                child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()),
                                              );
                                            }

                                            // Check if model groups are available
                                            if (modelGroup != null && modelGroup.groups.isNotEmpty) {
                                                // 按搜索关键字对分组内模型进行过滤（前端过滤）
                                                final List<ModelPrefixGroup> filteredGroups = modelGroup.groups.map((g) {
                                                  final filteredInfos = _modelSearch.isEmpty
                                                    ? g.modelsInfo
                                                    : g.modelsInfo.where((info) {
                                                        final id = info.id.toLowerCase();
                                                        final name = info.name.toLowerCase();
                                                        final kw = _modelSearch.toLowerCase();
                                                        return id.contains(kw) || name.contains(kw);
                                                      }).toList();
                                                  return ModelPrefixGroup(prefix: g.prefix, modelsInfo: filteredInfos);
                                                }).where((gg) => gg.modelsInfo.isNotEmpty).toList();

                                                final filteredGroup = AIModelGroup(provider: modelGroup.provider, groups: filteredGroups);

                                                return SingleChildScrollView(
                                                   child: Padding(
                                                     padding: const EdgeInsets.symmetric(vertical: 8.0),
                                                     child: ModelGroupList(
                                                       modelGroup: filteredGroup,
                                                       onModelSelected: _handleModelSelected,
                                                       selectedModel: _selectedModel,
                                                       verifiedModels: verifiedModels,
                                                     ),
                                                   ),
                                                 );
                                            } else {
                                                // Show message if no models are available or conditions not met
                                                String message = '该提供商没有可用的模型。';
                                                // Check if capability requires API key and if it has been tested successfully
                                                // if (currentCapability == ModelListingCapability.listingWithKey && !_apiKeyTestSuccess) {
                                                //    message = '请先成功测试 API Key 以加载模型列表。';
                                                // } else if (currentCapability == ModelListingCapability.noListing) {
                                                //     message = '该提供商不支持自动获取模型列表。';
                                                // }
                                                // ^^^ Commented out capability check as ModelListingCapability might be undefined now

                                                // Fallback message if capability check is removed/unavailable
                                                if (modelGroup == null || modelGroup.groups.isEmpty) {
                                                   if (_selectedProvider != null) {
                                                      // More specific message if provider selected but no models
                                                      message = '未能加载模型列表。如果需要 API Key，请确保已成功测试。';
                                                   } else {
                                                      message = '请先选择一个提供商。';
                                                   }
                                                }


                                                return Center(
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          message, 
                                                          textAlign: TextAlign.center, 
                                                          style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)
                                                        ),
                                                        const SizedBox(height: 8),
                                                        Text(
                                                          '提示：可在上方搜索框直接输入模型名称并添加',
                                                          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor.withOpacity(0.8)),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                            }
                                          },
                                         ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // 加载指示器
                            if (!_isEditMode && _selectedProvider != null && _isLoadingModels)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10.0, bottom: 4.0),
                                      child: Text('可用模型', style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                                        fontSize: 13,
                                      )),
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const CircularProgressIndicator(),
                                            const SizedBox(height: 16),
                                            Text(
                                              '正在加载 $_selectedProvider 的模型列表...',
                                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            ], // End of right column children
                          ),
                        ), // End of Expanded (Right Side)
                    ], // End of Row children
                  ), // End of Row
                ), // End of Expanded (Main Content Area)

                // 底部按钮区域
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _isSaving ? null : widget.onCancel,
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                          ),
                          side: BorderSide(
                              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                              width: 1.0,
                            ),
                          ),
                          child: const Text('取消', style: TextStyle(fontSize: 13)),
                        ),
                        const SizedBox(width: 12),
                      ElevatedButton(
                          onPressed: _isSaving ? null : _submitForm,
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(_isEditMode ? '保存更改' : '添加', style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
              ], // End of Form children
            ), // End of Form
          ), // End of Container
        ), // End of Body
      ), // End of Scaffold
    );
  }
}

// Helper function to get model initial (potentially update logic if needed)
// String _getModelInitial(String modelName) => modelName.isEmpty ? '?' : modelName[0].toUpperCase();

// Helper function to get model color (can stay based on id or name)
// Color _getModelColor(String modelId) { final hash = modelId.hashCode; return HSLColor.fromAHSL(1.0, (hash % 360).toDouble(), 0.6, 0.5).toColor(); }
