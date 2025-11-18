/// 语言切换Provider
/// Locale Provider for i18n

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'translations.dart';
import '../config/constants.dart';

/// 语言Provider
/// Locale Provider
class LocaleProvider with ChangeNotifier {
  AgentChatLocale _locale = defaultLocale;
  late Translations _translations;
  
  LocaleProvider() {
    _translations = Translations(_locale);
    _loadLocale();
  }
  
  /// 当前语言
  /// Current locale
  AgentChatLocale get locale => _locale;
  
  /// 当前语言字符串
  String get currentLocale => _locale == AgentChatLocale.zh ? 'zh' : 'en';
  
  /// 翻译实例
  /// Translations instance
  Translations get t => _translations;
  
  /// 是否是中文
  bool get isZh => _locale == AgentChatLocale.zh;
  
  /// 是否是英文
  bool get isEn => _locale == AgentChatLocale.zh;
  
  /// 从本地存储加载语言设置
  /// Load locale from local storage
  Future<void> _loadLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(StorageKeys.locale);
      
      if (saved != null) {
        _locale = saved == 'zh' ? AgentChatLocale.zh : AgentChatLocale.en;
        _translations = Translations(_locale);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load locale: $e');
    }
  }
  
  /// 切换语言
  /// Switch locale
  Future<void> setLocale(AgentChatLocale newLocale) async {
    if (_locale == newLocale) return;
    
    _locale = newLocale;
    _translations = Translations(_locale);
    notifyListeners();
    
    // 保存到本地存储
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        StorageKeys.locale,
        newLocale == AgentChatLocale.zh ? 'zh' : 'en',
      );
    } catch (e) {
      debugPrint('Failed to save locale: $e');
    }
  }
  
  /// 切换到中文
  /// Switch to Chinese
  Future<void> switchToZh() async {
    await setLocale(AgentChatLocale.zh);
  }
  
  /// 切换到英文
  /// Switch to English
  Future<void> switchToEn() async {
    await setLocale(AgentChatLocale.en);
  }
  
  /// 切换语言（中<->英）
  /// Toggle locale (ZH <-> EN)
  Future<void> toggleLocale() async {
    await setLocale(_locale == AgentChatLocale.zh 
        ? AgentChatLocale.en 
        : AgentChatLocale.zh);
  }
}

/// 语言选择Widget
/// Locale toggle widget
class LocaleToggle extends StatelessWidget {
  final LocaleProvider provider;
  final bool showText;
  
  const LocaleToggle({
    super.key,
    required this.provider,
    this.showText = true,
  });
  
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: provider.toggleLocale,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            if (showText) ...[
              const SizedBox(width: 6),
              Text(
                provider.isZh ? '中文' : 'EN',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}




