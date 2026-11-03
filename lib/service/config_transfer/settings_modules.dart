/// Each portable setting has one owner. Do not use broad prefix matching for
/// AI: skills, translation and vector models are independently transferable.
const settingsModuleKeys = <String, String>{
  'appearance':
      '''wereadApiKey locale themeMode appLayoutMode themeColor themePresetId customThemePresets themePresetOverrides themeAppliesToReader trueDarkMode eInkMode eInkDisableAnimations
useOriginalCoverRatio bookCoverWidth bookshelfFolderStyle bookshelfListMode showBookFormatBadge showBookIndexBadge showBookTitleOnDefaultCover
showAuthorOnDefaultCover openBookAnimation bottomNavigatorShowNote
bottomNavigatorShowRemote bottomNavigatorShowStatistics bottomNavigatorShowAI sortField sortOrder''',
  'reading':
      '''readStyle readTheme hideStatusBar readerFullscreen autoHideBottomBar
awakeTime dailyCheckInMinutes pageTurningType pageTurnStyle readingRules chapterSplitCustomRules
chapterSplitSelectedRuleId autoAdjustReadingTheme readingNightMode volumeKeyTurnPage
keyboardShortcutTurnPage readerShortcuts swapPageTurnArea tapOnlyPageTurn continuousScroll scrollAutoAlign longPressSelectParagraph scrollPagePercent showMenuOnHover showActionLabels eInkRefreshPages
useBookStyles pageTurnMode customPageTurnConfig readingInfo showTextUnderIconButton
pageHeaderMargin pageHeaderLeftMargin pageHeaderRightMargin pageHeaderFontSize
pageFooterMargin pageFooterLeftMargin pageFooterRightMargin pageFooterFontSize
writingMode verticalRedFrame textAlignment bgimgFit bgimg selectionToolbar readerToolbar''',
  'css':
      '''customCSSEnabled customCSS customCssProfiles customCssDefaultIndex customCssDefaultIndices''',
  'selection-search': 'selectionSearchSettings selectionSearchZoomPercent',
  'ai':
      '''aiProviders selectedAiService aiRpm aiMaxTokens aiContextTurns maxAiCacheCount
aiTemperature aiChatFontSize aiPanelWidth aiPanelHeight aiPanelPosition aiChatDisplayMode adjustableReaderPopups
codeHighlightTheme enabledAiTools''',
  'ai-skills':
      '''readAnySkillStates readAnySkillPrompts userPrompts autoSummaryPreviousContent aiReadingSkillsVisible readAnySkillOrder''',
  'plugins': 'pluginState',
  'vector':
      '''vectorModelEnabled autoVectorizeOnImport vectorModelMode vectorLocalModelId
vectorModelDownloadSource vectorModelConfig''',
  'ocr':
      'ocrModelId ocrModelDownloadSource ocrPrecacheEnabled ocrPrecachePages',
  'tts':
      '''ttsVolume ttsPitch ttsRate ttsService onlineTtsService isSystemTts allowMixWithOtherAudio ttsBufferSettings ttsRoleConfig''',
  'translation':
      '''translateService translateFrom translateTo fullTextTranslateService
fullTextTranslateFrom fullTextTranslateTo translationAiService translationMode autoTranslateSelection webTranslationZoomPercent
classicalTranslationEngine classicalTranslationDirection classicalTranslationAiService classicalTranslationTextStyle languageTranslationTextStyle''',
  'webdav':
      '''webdavInfo s3Info syncProtocol autoSync onlySyncWhenWifi syncCompletedToast
readingTimedSync readingSyncMinutes''',
  'remote-library-webdav': 'remoteLibraryConnection remoteLibraryViewOptions',
  'notes': '''quickMarkShowMenu autoMarkSelection annotationType annotationColor
notesViewSortField notesViewSortDirection notesExportSortField notesExportSortDirection
notesExportMergeChapters excerptShareTemplate excerptShareColorIndex excerptShareBgimgIndex''',
  'statistics': 'statisticsDashboardTiles historyOpenBookDirectly',
  'network': 'httpProxyEnabled httpProxyHost httpProxyPort httpProxyTestUrl',
  'advanced': 'clearLogWhenStart enableJsForEpub',
};

final _owners = <String, String>{
  for (final module in settingsModuleKeys.entries)
    for (final key in module.value.split(RegExp(r'\s+'))) key: module.key,
};

String? settingsModuleForKey(String key) {
  if (key.startsWith('aiConfig_')) return 'ai';
  if (key.startsWith('aiPrompt_')) return 'ai-skills';
  if (key.startsWith('pluginConfig_')) return 'plugins';
  if (key.startsWith('onlineTtsConfig_') || key.startsWith('ttsVoiceModel_')) {
    return 'tts';
  }
  if (key.startsWith('translateServiceConfig_')) return 'translation';
  return _owners[key];
}
