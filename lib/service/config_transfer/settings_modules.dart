/// Each portable setting has one owner. Do not use broad prefix matching for
/// AI: skills, translation and vector models are independently transferable.
const settingsModuleKeys = <String, String>{
  'appearance': '''locale themeMode themeColor trueDarkMode eInkMode
useOriginalCoverRatio bookCoverWidth bookshelfFolderStyle showBookTitleOnDefaultCover
showAuthorOnDefaultCover openBookAnimation bottomNavigatorShowNote
bottomNavigatorShowStatistics bottomNavigatorShowAI sortField sortOrder''',
  'reading':
      '''readStyle readTheme hideStatusBar readerFullscreen autoHideBottomBar
awakeTime pageTurningType pageTurnStyle readingRules chapterSplitCustomRules
chapterSplitSelectedRuleId autoAdjustReadingTheme readingNightMode volumeKeyTurnPage
keyboardShortcutTurnPage swapPageTurnArea tapOnlyPageTurn showMenuOnHover showActionLabels
useBookStyles pageTurnMode customPageTurnConfig readingInfo showTextUnderIconButton
pageHeaderMargin pageHeaderLeftMargin pageHeaderRightMargin pageHeaderFontSize
pageFooterMargin pageFooterLeftMargin pageFooterRightMargin pageFooterFontSize
writingMode verticalRedFrame textAlignment bgimgFit bgimg''',
  'css':
      '''customCSSEnabled customCSS customCssProfiles customCssDefaultIndex customCssDefaultIndices''',
  'selection-search': 'selectionSearchSettings',
  'ai':
      '''aiProviders selectedAiService aiRpm aiMaxTokens aiContextTurns maxAiCacheCount
aiTemperature aiChatFontSize aiPanelWidth aiPanelHeight aiPanelPosition aiChatDisplayMode
codeHighlightTheme enabledAiTools''',
  'ai-skills':
      '''readAnySkillStates readAnySkillPrompts userPrompts autoSummaryPreviousContent''',
  'vector':
      '''vectorModelEnabled autoVectorizeOnImport vectorModelMode vectorLocalModelId
vectorModelDownloadSource vectorModelConfig''',
  'tts':
      '''ttsVolume ttsPitch ttsRate ttsService onlineTtsService isSystemTts allowMixWithOtherAudio''',
  'translation':
      '''translateService translateFrom translateTo fullTextTranslateService
fullTextTranslateFrom fullTextTranslateTo translationAiService translationMode autoTranslateSelection''',
  'webdav':
      '''webdavInfo syncProtocol autoSync onlySyncWhenWifi syncCompletedToast
readingTimedSync readingSyncMinutes''',
  'remote-library-webdav': 'remoteLibraryConnection remoteLibraryViewOptions',
  'notes': '''quickMarkShowMenu autoMarkSelection annotationType annotationColor
notesViewSortField notesViewSortDirection notesExportSortField notesExportSortDirection
notesExportMergeChapters excerptShareTemplate excerptShareColorIndex excerptShareBgimgIndex''',
  'statistics': 'statisticsDashboardTiles',
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
  if (key.startsWith('onlineTtsConfig_') || key.startsWith('ttsVoiceModel_')) {
    return 'tts';
  }
  if (key.startsWith('translateServiceConfig_')) return 'translation';
  return _owners[key];
}
