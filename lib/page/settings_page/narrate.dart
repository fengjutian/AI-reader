import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/edge_tts_api.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/utils/tts_model_list.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 文本转语音（TTS）设置页面
/// 用于配置TTS类型、语音模型等参数
class NarrateSettings extends ConsumerStatefulWidget {
  /// 创建NarrateSettings实例
  const NarrateSettings({super.key});

  @override
  ConsumerState<NarrateSettings> createState() => _NarrateSettingsState();
}

/// NarrateSettings的状态类
class _NarrateSettingsState extends ConsumerState<NarrateSettings>
    with SingleTickerProviderStateMixin {
  /// TTS语音模型列表数据源
  List<Map<String, dynamic>> data = ttsModelList;

  /// 当前选中的语音模型
  String? selectedVoiceModel;

  /// 按语言分组的语音模型映射
  Map<String, List<Map<String, dynamic>>> groupedVoices = {};

  /// 当前展开的语言分组集合
  Set<String> expandedGroups = {};

  /// 滚动控制器，用于滚动到选中的语音模型
  final ScrollController _scrollController = ScrollController();

  /// 当前高亮显示的模型
  String? _highlightedModel;

  /// 高亮动画控制器
  late AnimationController _highlightAnimationController;

  /// 高亮动画
  late Animation<Color?> _highlightAnimation;

  /// 当前选中模型的详细信息
  Map<String, dynamic>? _currentModelDetails;

  /// 当前选中模型所属的语言分组
  String? _currentModelLanguageGroup;

  @override
  void initState() {
    super.initState();

    // 初始化高亮动画控制器，用于选中模型时的视觉反馈
    _highlightAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // 从偏好设置中获取当前选中的语音模型
    selectedVoiceModel = Prefs().ttsVoiceModel;

    // 按语言分组语音模型
    _groupVoicesByLanguage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 初始化高亮动画，从主题的primaryContainer颜色渐变到透明
    _highlightAnimation = ColorTween(
      begin: Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
      end: Colors.transparent,
    ).animate(_highlightAnimationController)
      ..addStatusListener((status) {
        // 当动画完成时，清除高亮显示
        if (status == AnimationStatus.completed) {
          setState(() {
            _highlightedModel = null;
          });
        }
      });

    // 更新当前选中模型的详细信息
    _updateCurrentModelDetails();
  }

  @override
  void dispose() {
    // 释放滚动控制器资源
    _scrollController.dispose();
    // 释放高亮动画控制器资源
    _highlightAnimationController.dispose();
    super.dispose();
  }

  /// 更新当前选中模型的详细信息和所属语言分组
  void _updateCurrentModelDetails() {
    if (selectedVoiceModel != null) {
      // 查找当前选中模型的详细信息
      for (var voice in data) {
        if (voice['ShortName'] == selectedVoiceModel) {
          _currentModelDetails = voice;
          break;
        }
      }

      // 查找当前选中模型所属的语言分组
      for (var entry in groupedVoices.entries) {
        for (var voice in entry.value) {
          if (voice['ShortName'] == selectedVoiceModel) {
            _currentModelLanguageGroup = entry.key;
            break;
          }
        }
        if (_currentModelLanguageGroup != null) break;
      }
    }
  }

  /// 滚动到当前选中的语音模型位置并高亮显示
  void _scrollToSelectedModel() {
    if (selectedVoiceModel == null || _currentModelLanguageGroup == null) {
      return;
    }

    // 如果当前模型所在的语言分组未展开，则自动展开
    if (!expandedGroups.contains(_currentModelLanguageGroup)) {
      setState(() {
        expandedGroups.add(_currentModelLanguageGroup!);
      });
    }

    // 延迟执行滚动操作，确保展开动画完成
    Future.delayed(const Duration(milliseconds: 300), () {
      List<String> languageGroups = groupedVoices.keys.toList();
      int groupIndex = languageGroups.indexOf(_currentModelLanguageGroup!);

      if (groupIndex == -1) return;

      double scrollPosition = 0;

      // 计算滚动位置：遍历到当前语言分组前的所有分组
      for (int i = 0; i < groupIndex; i++) {
        String lang = languageGroups[i];
        scrollPosition += 50; // 语言分组标题高度

        if (expandedGroups.contains(lang)) {
          scrollPosition += groupedVoices[lang]!.length * 80; // 每个语音模型项高度
        }
      }

      // 计算当前语言分组内当前模型的位置
      List<Map<String, dynamic>> voicesInGroup =
          groupedVoices[_currentModelLanguageGroup]!;
      int modelIndex = voicesInGroup
          .indexWhere((voice) => voice['ShortName'] == selectedVoiceModel);

      if (modelIndex != -1) {
        scrollPosition += modelIndex * 80;
      }

      // 执行滚动动画
      _scrollController.animateTo(
        scrollPosition,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );

      // 高亮显示当前选中的模型
      setState(() {
        _highlightedModel = selectedVoiceModel;
      });
      _highlightAnimationController.reset();
      _highlightAnimationController.forward();
    });
  }

  /// 按语言分组语音模型
  void _groupVoicesByLanguage() {
    groupedVoices.clear();

    // 遍历所有语音模型，按语言分组
    for (var voice in data) {
      String locale = voice['Locale'] as String;
      // 根据地区代码获取语言名称
      String languageName = _getLanguageNameFromLocale(locale);

      // 如果该语言分组不存在，则创建
      if (!groupedVoices.containsKey(languageName)) {
        groupedVoices[languageName] = [];
      }

      // 将语音模型添加到对应的语言分组中
      groupedVoices[languageName]!.add(voice);
    }
  }

  /// 根据语言代码获取语言名称
  /// [locale]：语言代码（如 'en-US'）
  /// 返回：完整的语言名称（如 'English (English)'）
  String _getLanguageNameFromLocale(String locale) {
    // 语言代码到语言名称的映射表
    Map<String, String> languageMap = {
      'af': 'Afrikaans (Afrikaans)',
      'am': 'አማርኛ (Amharic)',
      'ar': 'العربية (Arabic)',
      'az': 'Azərbaycan (Azerbaijani)',
      'bg': 'Български (Bulgarian)',
      'bs': 'Bosanski (Bosnian)',
      'iu': 'ᐃᓄᒃᑎᑐᑦ (Inuktitut)',
      'zu': 'IsiZulu (Zulu)',
      'bn': 'বাংলা (Bengali)',
      'ca': 'Català (Catalan)',
      'cs': 'Čeština (Czech)',
      'cy': 'Cymraeg (Welsh)',
      'da': 'Dansk (Danish)',
      'de': 'Deutsch (German)',
      'el': 'Ελληνικά (Greek)',
      'en': 'English (English)',
      'es': 'Español (Spanish)',
      'et': 'Eesti (Estonian)',
      'eu': 'Euskara (Basque)',
      'fa': 'فارسی (Persian)',
      'fi': 'Suomi (Finnish)',
      'fil': 'Filipino (Filipino)',
      'fr': 'Français (French)',
      'ga': 'Gaeilge (Irish)',
      'gl': 'Galego (Galician)',
      'gu': 'ગુજરાતી (Gujarati)',
      'he': 'עברית (Hebrew)',
      'hi': 'हिन्दी (Hindi)',
      'hr': 'Hrvatski (Croatian)',
      'hu': 'Magyar (Hungarian)',
      'hy': 'Հայերեն (Armenian)',
      'id': 'Indonesia (Indonesian)',
      'is': 'Íslenska (Icelandic)',
      'it': 'Italiano (Italian)',
      'ja': '日本語 (Japanese)',
      'jv': 'Basa Jawa (Javanese)',
      'ka': 'ქართული (Georgian)',
      'kk': 'Қазақ (Kazakh)',
      'km': 'ខ្មែរ (Khmer)',
      'kn': 'ಕನ್ನಡ (Kannada)',
      'ko': '한국어 (Korean)',
      'lo': 'ລາວ (Lao)',
      'lt': 'Lietuvių (Lithuanian)',
      'lv': 'Latviešu (Latvian)',
      'mk': 'Македонски (Macedonian)',
      'ml': 'മലയാളം (Malayalam)',
      'mn': 'Монгол (Mongolian)',
      'mr': 'मराठी (Marathi)',
      'ms': 'Melayu (Malay)',
      'mt': 'Malti (Maltese)',
      'my': 'မြန်မာ (Burmese)',
      'nb': 'Norsk Bokmål (Norwegian Bokmål)',
      'ne': 'नेपाली (Nepali)',
      'nl': 'Nederlands (Dutch)',
      'nn': 'Nynorsk (Norwegian Nynorsk)',
      'or': 'ଓଡ଼ିଆ (Odia)',
      'pa': 'ਪੰਜਾਬੀ (Punjabi)',
      'pl': 'Polski (Polish)',
      'ps': 'پښتو (Pashto)',
      'pt': 'Português (Portuguese)',
      'ro': 'Română (Romanian)',
      'ru': 'Русский (Russian)',
      'si': 'සිංහල (Sinhala)',
      'sk': 'Slovenčina (Slovak)',
      'sl': 'Slovenščina (Slovenian)',
      'so': 'Soomaali (Somali)',
      'sq': 'Shqip (Albanian)',
      'sr': 'Српски (Serbian)',
      'su': 'Basa Sunda (Sundanese)',
      'sv': 'Svenska (Swedish)',
      'sw': 'Kiswahili (Swahili)',
      'ta': 'தமிழ் (Tamil)',
      'te': 'తెలుగు (Telugu)',
      'th': 'ไทย (Thai)',
      'tr': 'Türkçe (Turkish)',
      'uk': 'Українська (Ukrainian)',
      'ur': 'اردو (Urdu)',
      'uz': "O'zbek (Uzbek)",
      'vi': 'Tiếng Việt (Vietnamese)',
      'yue': '粵語 (Cantonese)',
      'zh': '中文 (Chinese)',
    };

    // 从完整的语言代码中提取语言部分（如从 'en-US' 提取 'en'）
    String langCode = locale.split('-')[0];
    // 返回对应的语言名称，如果没有找到则返回原始的语言代码
    return languageMap[langCode] ?? locale;
  }

  /// 切换语言分组的展开/折叠状态
  /// [languageName]：要切换的语言分组名称
  void _toggleGroup(String languageName) {
    setState(() {
      if (expandedGroups.contains(languageName)) {
        // 如果分组已展开，则折叠
        expandedGroups.remove(languageName);
      } else {
        // 如果分组已折叠，则展开
        expandedGroups.add(languageName);
      }
    });
  }

  /// 选择语音模型
  /// [shortName]：语音模型的短名称
  void _selectVoiceModel(String shortName) {
    setState(() {
      // 更新当前选中的语音模型
      selectedVoiceModel = shortName;
      // 保存到偏好设置
      Prefs().ttsVoiceModel = shortName;
      // 更新EdgeTTS API的语音模型
      EdgeTTSApi.voice = shortName;
      // 更新当前模型的详细信息
      _updateCurrentModelDetails();
    });
  }

  /// 根据性别获取对应的图标
  /// [gender]：性别（'Female' 或 'Male'）
  /// 返回：对应的性别图标
  IconData _getGenderIcon(String gender) {
    switch (gender) {
      case 'Female':
        return Icons.female;
      case 'Male':
        return Icons.male;
      default:
        return Icons.person;
    }
  }

  /// 获取当前选中模型的显示名称
  /// 返回：当前模型的显示名称
  String _getCurrentModelDisplayName() {
    if (_currentModelDetails == null) {
      return L10n.of(context).settingsNarrateVoiceModelNotSelected;
    }

    String shortName = _currentModelDetails!['ShortName'] as String;
    String personName = shortName.split('-').last;
    // 移除'Neural'后缀（如果存在）
    if (personName.endsWith('Neural')) {
      personName = personName.substring(0, personName.length - 6);
    }

    return personName;
  }

  /// 获取当前选中模型的语言名称
  /// 返回：当前模型的语言名称
  String _getCurrentModelLanguageName() {
    if (_currentModelDetails == null) return '';

    String locale = _currentModelDetails!['Locale'] as String;
    return _getLanguageNameFromLocale(locale);
  }

  /// 获取当前选中模型的性别
  /// 返回：当前模型的性别
  String _getCurrentModelGender() {
    if (_currentModelDetails == null) return '';

    return _currentModelDetails!['Gender'] as String;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // TTS类型设置部分
        SettingsSection(title: Text(L10n.of(context).ttsType), tiles: [
          // 系统TTS开关
          SettingsTile.switchTile(
              title: Text(L10n.of(context).ttsTypeSystem),
              initialValue: Prefs().isSystemTts,
              onToggle: (value) async {
                // 切换TTS类型
                await TtsHandler().switchTtsType(value);
                setState(() {});
              }),
          // 允许与其他音频混合开关
          SettingsTile.switchTile(
              title: Text(L10n.of(context).allowMixing),
              description: Text(L10n.of(context).enableMixTip),
              initialValue: Prefs().allowMixWithOtherAudio,
              onToggle: (value) {
                Prefs().allowMixWithOtherAudio = value;
                setState(() {});
              }),
        ]),
        // 语音模型选择器（仅当使用非系统TTS时显示）
        Visibility(
          visible: !Prefs().isSystemTts,
          child: Expanded(
            child: _buildVoiceModelSelector(),
          ),
        ),
      ],
    );
  }

  /// 构建语音模型选择器界面
  /// 返回：语音模型选择器组件
  Widget _buildVoiceModelSelector() {
    return ListView(
      controller: _scrollController,
      children: [
        // 当前选中模型的展示区域
        _buildCurrentModelSection(),
        const Divider(),
        // 语音模型列表
        ..._buildVoiceModelList(),
      ],
    );
  }

  /// 构建当前选中模型的展示区域
  /// 返回：当前模型展示组件
  Widget _buildCurrentModelSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // 点击时滚动到当前模型在列表中的位置
          onTap: _scrollToSelectedModel,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      L10n.of(context).settingsNarrateVoiceModelCurrentModel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    Icon(
                      _getGenderIcon(_getCurrentModelGender()),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 模型信息行
                Row(
                  children: [
                    // 性别图标
                    CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      radius: 24,
                      child: Icon(
                        _getGenderIcon(_getCurrentModelGender()),
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 模型名称
                          Text(
                            _getCurrentModelDisplayName(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // 模型语言
                          Text(
                            _getCurrentModelLanguageName(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 提示行
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      L10n.of(context).settingsNarrateVoiceModelClickToView,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Icon(
                      Icons.arrow_downward,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建按语言分组的语音模型列表
  /// 返回：语音模型列表组件
  List<Widget> _buildVoiceModelList() {
    List<Widget> voiceModelList = [];

    // 遍历所有语言分组
    for (var language in groupedVoices.entries) {
      String languageName = language.key;
      List<Map<String, dynamic>> voicesInLanguage = language.value;

      voiceModelList.add(
        Column(
          children: [
            // 语言分组标题
            Container(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withAlpha(100),
              child: ListTile(
                title: Text(
                  languageName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(
                  // 根据分组是否展开显示不同的箭头图标
                  expandedGroups.contains(languageName)
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onTap: () => _toggleGroup(languageName), // 点击切换分组展开/折叠状态
              ),
            ),
            // 如果分组展开，则显示该语言下的所有语音模型
            if (expandedGroups.contains(languageName))
              ...voicesInLanguage.map((voice) {
                String shortName = voice['ShortName'] as String;
                String friendlyName = voice['FriendlyName'] as String;
                String gender = voice['Gender'] as String;

                // 提取显示名称
                String displayName = friendlyName.split(' - ').last;
                if (displayName.contains('(')) {
                  displayName = displayName.split('(')[0].trim();
                }

                // 提取人物名称并移除'Neural'后缀
                String personName = shortName.split('-').last;
                if (personName.endsWith('Neural')) {
                  personName = personName.substring(0, personName.length - 6);
                }

                // 检查当前模型是否需要高亮显示
                bool isHighlighted = _highlightedModel == shortName;

                return AnimatedBuilder(
                  animation: _highlightAnimation,
                  builder: (context, child) {
                    // 应用高亮动画效果
                    return Container(
                      color: isHighlighted
                          ? _highlightAnimation.value
                          : Colors.transparent,
                      child: child,
                    );
                  },
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        _getGenderIcon(gender), // 根据性别显示图标
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      personName,
                      style: TextStyle(
                        // 当前选中的模型名称显示为粗体
                        fontWeight: selectedVoiceModel == shortName
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(gender == 'Male'
                        ? L10n.of(context).settingsNarrateVoiceModelMale
                        : L10n.of(context).settingsNarrateVoiceModelFemale),
                    trailing: Radio<String>(
                      value: shortName,
                      groupValue: selectedVoiceModel,
                      activeColor: Theme.of(context).colorScheme.primary,
                      onChanged: (value) {
                        if (value != null) {
                          _selectVoiceModel(value);
                        }
                      },
                    ),
                    onTap: () => _selectVoiceModel(shortName), // 点击选择语音模型
                  ),
                );
              }),
            const Divider(height: 1),
          ],
        ),
      );
    }

    return voiceModelList;
  }
}
