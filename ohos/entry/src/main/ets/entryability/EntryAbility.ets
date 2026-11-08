import LinkedBookFilesPlugin from '../plugins/LinkedBookFilesPlugin';
import { Want, AbilityConstant } from '@kit.AbilityKit';
import ExternalBookFilesPlugin from '../plugins/ExternalBookFilesPlugin';

import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import FileExportPlugin from '../plugins/FileExportPlugin';
import ReaderWakelockPlugin from '../plugins/ReaderWakelockPlugin';
import ReaderCutoutPlugin from '../plugins/ReaderCutoutPlugin';

export default class EntryAbility extends FlutterAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onCreate(want, launchParam);
    ExternalBookFilesPlugin.shared.receive(want, this.context.cacheDir);
  }
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam);
    ExternalBookFilesPlugin.shared.receive(want, this.context.cacheDir);
  }
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(ExternalBookFilesPlugin.shared)
    flutterEngine.getPlugins()?.add(new FileExportPlugin())
    flutterEngine.getPlugins()?.add(new LinkedBookFilesPlugin())
    flutterEngine.getPlugins()?.add(new ReaderWakelockPlugin())
    flutterEngine.getPlugins()?.add(new ReaderCutoutPlugin())
  }
}
