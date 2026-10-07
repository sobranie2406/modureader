"""Exact, fail-closed source transformations for CPF-Flutter 528fa913 only.

Only copied adapters are edited by patch_webview.py. Keep these anchors strict:
an upstream source change must fail, never silently leave a bridge entry open.
"""

PIN = '528fa913763148719cde7dae2dc22dc33f15da36'
PACKAGES = ('flutter_inappwebview', 'flutter_inappwebview_platform_interface',
            'flutter_inappwebview_ohos')
PI = PACKAGES[1] + '/lib/src/in_app_webview/'
OH = PACKAGES[2] + '/ohos/src/main/ets/components/plugin/'
VIEW = OH + 'webview/in_app_webview/InAppWebView.ets'
CLIENT = OH + 'webview/in_app_webview/InAppWebViewClient.ets'
CONTENT = OH + 'types/UserContentController.ets'
BRIDGE = OH + 'webview/JavaScriptBridgeInterface.ets'
CHANNEL = OH + 'webview/WebViewChannelDelegate.ets'


def replacements():
    """(file, old, new, exact occurrence count); no fuzzy patch application."""
    edits = []

    def add(path, old, new, count=1):
        edits.append((path, old, new, count))

    add(PACKAGES[0] + '/lib/src/in_app_webview/in_app_webview_controller.dart',
        '  Future<void> clearFocus() => platform.clearFocus();',
        '''  Future<void> clearFocus() => platform.clearFocus();

  /// Requests native focus. True means ArkWeb accepted the request, not that
  /// asynchronous focus acquisition has been observed.
  Future<bool?> requestFocus() => platform.requestFocus();''')
    add(PI + 'platform_inappwebview_controller.dart',
        '  Future<void> clearFocus() {',
        '''  /// OHOS cloud adapter: implemented by the native ArkWeb controller.
  Future<bool?> requestFocus() {
    throw UnsupportedError('requestFocus requires the OHOS cloud adapter');
  }

  Future<void> clearFocus() {''')
    add(PACKAGES[2] + '/lib/src/in_app_webview/in_app_webview_controller.dart',
        '  Future<void> clearFocus() async {',
        '''  Future<bool?> requestFocus() async {
    if (channel == null) throw StateError('WebView controller is disposed');
    return await channel!.invokeMethod<bool>('requestFocus', <String, dynamic>{});
  }

  @override
  Future<void> clearFocus() async {''')

    # Patch the generator input AND its checked-in output; do not run generators
    # on another platform's source tree just to add a setting.
    for name in ('in_app_webview_settings.dart', 'in_app_webview_settings.g.dart'):
        path = PI + name
        add(path, '  bool? javaScriptEnabled;', '''  bool? javaScriptEnabled;

  /// OHOS: creation-time bridge policy. False disables plugin bridge injection
  /// and native JS callbacks, NOT page JavaScript or page evaluateJavascript.
  /// Recreate the WebView to change this value. Defaults to true.
  bool? javaScriptBridgeEnabled;''')
        indent = '    ' if name.endswith('settings.dart') else '      '
        anchor = indent + 'this.javaScriptEnabled = true,\n' + indent + 'this.javaScriptCanOpenWindowsAutomatically = false,'
        add(path, anchor,
            indent + 'this.javaScriptEnabled = true,\n' +
            indent + 'this.javaScriptBridgeEnabled = true,\n' +
            indent + 'this.javaScriptCanOpenWindowsAutomatically = false,')
    path = PI + 'in_app_webview_settings.g.dart'
    add(path, "    instance.javaScriptEnabled = map['javaScriptEnabled'];",
        "    instance.javaScriptEnabled = map['javaScriptEnabled'];\n"
        "    instance.javaScriptBridgeEnabled = map['javaScriptBridgeEnabled'] ?? true;")
    add(path, '      "javaScriptEnabled": javaScriptEnabled,',
        '      "javaScriptEnabled": javaScriptEnabled,\n'
        '      "javaScriptBridgeEnabled": javaScriptBridgeEnabled,')

    settings = OH + 'webview/in_app_webview/InAppWebViewSettings.ets'
    add(settings, '  public javaScriptAccess: boolean = true;',
        '  public javaScriptAccess: boolean = true;\n'
        '  public javaScriptBridgeEnabled: boolean = true;')
    add(settings, '        case "javaScriptEnabled":',
        '''        case "javaScriptBridgeEnabled":
          this.javaScriptBridgeEnabled = value as boolean;
          break;
        case "javaScriptEnabled":''')
    add(settings, '    settings.set("javaScriptEnabled", this.javaScriptAccess);',
        '    settings.set("javaScriptEnabled", this.javaScriptAccess);\n'
        '    settings.set("javaScriptBridgeEnabled", this.javaScriptBridgeEnabled);')

    add(VIEW, '  private javaScriptBridgeInterface: JavaScriptBridgeInterface | null = null;',
        '''  private javaScriptBridgeInterface: JavaScriptBridgeInterface | null = null;
  // Immutable for this instance, including navigations and setSettings calls.
  private bridgeEnabled: boolean = true;

  public isJavaScriptBridgeEnabled(): boolean {
    return this.bridgeEnabled;
  }

  public requestFocus(): boolean {
    this.requireController().requestFocus();
    return true;
  }''')
    add(VIEW, '    this.customSettings = customSettings;',
        '    this.customSettings = customSettings;\n'
        '    this.bridgeEnabled = customSettings.javaScriptBridgeEnabled;')
    add(VIEW, '    this.requireController().registerJavaScriptProxy(this.javaScriptBridgeInterface, \n'
        '    JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME, this.javaScriptBridgeInterface.getMethodList());',
        '''    if (this.isJavaScriptBridgeEnabled()) {
      this.requireController().registerJavaScriptProxy(this.javaScriptBridgeInterface,
        JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME, this.javaScriptBridgeInterface.getMethodList());
    } else {
      // Also revoke any proxy on an adopted popup controller.
      this.requireController().deleteJavaScriptRegister(JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME);
    }''')
    add(VIEW, '    this.customSettings = newCustomSettings;',
        '    newCustomSettings.javaScriptBridgeEnabled = this.bridgeEnabled;\n'
        '    this.customSettings = newCustomSettings;')
    add(VIEW, '  public enablePluginScriptAtRuntime(flagVariable: string, enable: boolean, pluginScript: PluginScript) {',
        '''  public enablePluginScriptAtRuntime(flagVariable: string, enable: boolean, pluginScript: PluginScript) {
    if (!this.isJavaScriptBridgeEnabled()) return;''')
    add(VIEW, "      JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_JS_SOURCE + ';' +",
        "      (this.isJavaScriptBridgeEnabled() ? JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_JS_SOURCE + ';' : '') +")
    add(VIEW, '    if (this.customSettings.multiWindowAccess && this.customSettings.allowWindowOpenMethod) {',
        '    if (this.isJavaScriptBridgeEnabled() && this.customSettings.multiWindowAccess && this.customSettings.allowWindowOpenMethod) {', 3)
    add(VIEW, '  private installPopupWindowCloseBridge(): void {',
        '  private installPopupWindowCloseBridge(): void {\n'
        '    if (!this.isJavaScriptBridgeEnabled()) return;')

    add(OH + 'webview/WebViewChannelDelegateMethods.ets', '  clearFocus,',
        '  requestFocus,\n  clearFocus,')
    add(CHANNEL, '      case WebViewChannelDelegateMethods.clearFocus:',
        '''      case WebViewChannelDelegateMethods.requestFocus:
        try {
          result.success(this.webView != null ? this.webView.requestFocus() : false);
        } catch (error) {
          const e = error as BusinessError;
          result.error('requestFocusError', e.message, null);
        }
        break;
      case WebViewChannelDelegateMethods.clearFocus:''')
    add(CHANNEL, '      case WebViewChannelDelegateMethods.setSettings:',
        '''      case WebViewChannelDelegateMethods.setSettings:
        const bridgeSettings = call.argument('settings') as Map<string, Any>;
        const bridgeEnabled = bridgeSettings.get('javaScriptBridgeEnabled');
        if (this.webView != null && bridgeEnabled != null &&
            bridgeEnabled !== this.webView.isJavaScriptBridgeEnabled()) {
          result.error('bridgePolicyImmutable', 'Recreate the WebView to change javaScriptBridgeEnabled', null);
          break;
        }''')
    # These APIs use bridge callbacks / iframe worlds upstream; reject explicitly
    # instead of injecting a bridge or leaving an unresolved Dart Future.
    for method in ('callAsyncJavaScript', 'createWebMessageChannel', 'addWebMessageListener'):
        marker = '      case WebViewChannelDelegateMethods.' + method + ':'
        add(CHANNEL, marker, marker + '''
        if (this.webView != null && !this.webView.isJavaScriptBridgeEnabled()) {
          result.error('javaScriptBridgeDisabled', 'This API requires the JavaScript bridge', null);
          break;
        }''')
    marker = '      case WebViewChannelDelegateMethods.evaluateJavascript:'
    add(CHANNEL, marker, marker + '''
        const evaluationWorld = call.argument('contentWorld') as Map<string, Any> | null;
        if (this.webView != null && !this.webView.isJavaScriptBridgeEnabled() &&
            evaluationWorld != null && evaluationWorld.get('name') !== 'page') {
          result.error('javaScriptBridgeDisabled', 'Only page-world evaluation is available without the bridge', null);
          break;
        }''')

    # Guard both exported native proxy methods BEFORE built-in or user handlers.
    for signature in ('  _hideContextMenu(): void {',
                      '  _callHandler(handlerName: string, callHandlerID: string, args: string): void {'):
        add(BRIDGE, signature, signature + '''
    if (this.inAppWebView == null || !this.inAppWebView.isJavaScriptBridgeEnabled()) return;''')

    # This gate covers all plugin scripts, including future addPluginScript calls
    # from web-message listeners. User-only page scripts (zoom/layout) are kept.
    add(CONTENT, '  public addPluginScript(pluginScript: PluginScript): boolean {',
        '''  public addPluginScript(pluginScript: PluginScript): boolean {
    if (this.inAppWebView == null || !this.inAppWebView.isJavaScriptBridgeEnabled()) return false;''')
    add(CONTENT, '  generatePluginScriptsCodeAt(injectionTime: UserScriptInjectionTime) {',
        '''  generatePluginScriptsCodeAt(injectionTime: UserScriptInjectionTime) {
    if (this.inAppWebView == null || !this.inAppWebView.isJavaScriptBridgeEnabled()) return '';''')
    add(CONTENT, '  public generateContentWorldsCreatorCode(): string {',
        '''  public generateContentWorldsCreatorCode(): string {
    if (this.inAppWebView == null || !this.inAppWebView.isJavaScriptBridgeEnabled()) return '';''')
    add(CONTENT, '  generateCodeForDocumentStart(): string {',
        '''  generateCodeForDocumentStart(): string {
    if (this.inAppWebView != null && !this.inAppWebView.isJavaScriptBridgeEnabled()) {
      return this.generateUserOnlyScriptsCodeAt(UserScriptInjectionTime.AT_DOCUMENT_START);
    }''')
    add(CONTENT, '  generateWrappedCodeForDocumentEnd(): string {',
        '''  generateWrappedCodeForDocumentEnd(): string {
    if (this.inAppWebView != null && !this.inAppWebView.isJavaScriptBridgeEnabled()) {
      return this.generateUserOnlyScriptsCodeAt(UserScriptInjectionTime.AT_DOCUMENT_END);
    }''')
    add(CONTENT, '  wrapSourceCodeInContentWorld(contentWorld: ContentWorld, source: string): string {',
        '''  wrapSourceCodeInContentWorld(contentWorld: ContentWorld, source: string): string {
    if (this.inAppWebView != null && !this.inAppWebView.isJavaScriptBridgeEnabled() &&
        contentWorld != null && !contentWorld.equals(ContentWorld.PAGE)) {
      throw new Error('Non-page user scripts require the JavaScript bridge');
    }''')
    add(CLIENT, '      if (this.inAppWebView!.inAppBrowserDelegate != null) {',
        '      if (this.inAppWebView!.isJavaScriptBridgeEnabled() && this.inAppWebView!.inAppBrowserDelegate != null) {')
    add(CLIENT, '      } else if (this.inAppWebView!.controller != null) {',
        '      } else if (this.inAppWebView!.isJavaScriptBridgeEnabled() && this.inAppWebView!.controller != null) {')
    add(CLIENT, '        this.inAppWebView!.customSettings.multiWindowAccess &&',
        '        this.inAppWebView!.isJavaScriptBridgeEnabled() &&\n'
        '        this.inAppWebView!.customSettings.multiWindowAccess &&')
    add(CLIENT, '    if (!this.inAppWebView!.customSettings.multiWindowAccess ||',
        '    if (!this.inAppWebView!.isJavaScriptBridgeEnabled() ||\n'
        '      !this.inAppWebView!.customSettings.multiWindowAccess ||')
    return edits


def transform(sources):
    """Preflight every anchor in memory before the installer writes anything."""
    output = dict(sources)
    for path, old, new, count in replacements():
        actual = output[path].count(old)
        if actual != count:
            raise ValueError(f'{path}: patch anchor count {actual}, expected {count}: {old[:80]!r}')
        output[path] = output[path].replace(old, new)
    return output
