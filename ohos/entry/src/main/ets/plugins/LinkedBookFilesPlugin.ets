import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler,
  MethodChannel, MethodResult, AbilityPluginBinding } from '@ohos/flutter_ohos';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { common } from '@kit.AbilityKit';
import { picker, fileIo as fs, fileUri, fileShare } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';

interface SelectedBook { uri: string; root: string; name: string; }
interface LinkedBook { uri: string; root: string; }
interface PickerEntry { id: string; name: string; label: string; }

export default class LinkedBookFilesPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;
  private appContext: common.Context | null = null;
  private selected: Map<string, SelectedBook> = new Map();
  private handles: Map<string, fs.File> = new Map();
  private busy: boolean = false;
  private selectedRoots: Set<string> = new Set();
  getUniqueClassName(): string { return 'ModuLinkedBookFilesPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.appContext = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'com.modu.reader/book_folder');
    this.channel.setMethodCallHandler(this);
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.handles.forEach((handle: fs.File) => { fs.closeSync(handle); });
    this.handles.clear();
  }
  onAttachedToAbility(binding: AbilityPluginBinding): void { this.context = binding.getAbility().context; }
  onDetachedFromAbility(): void { this.context = null; }
  onMethodCall(call: MethodCall, result: MethodResult): void { this.handle(call, result); }
  private async open(key: string, record: LinkedBook): Promise<string> {
    if (!/^file\/linked-[a-zA-Z0-9-]+\.(epub|pdf|mobi|azw3|fb2)$/.test(key)) throw new Error('Invalid key');
    let handle: fs.File;
    try {
      await fileShare.activatePermission([{ uri: record.root, operationMode: fileShare.OperationMode.READ_MODE }]);
      handle = await fs.open(record.uri, fs.OpenMode.READ_ONLY);
    } catch (_) { throw new Error('Original permission unavailable'); }
    try {
      if (!(await fs.stat(handle.fd)).isFile()) throw new Error('Not a file');
      const folder = this.appContext!.cacheDir + '/linked-book-access';
      try { await fs.mkdir(folder); } catch (_) { }
      const path = folder + '/' + key.substring(5);
      try { await fs.unlink(path); } catch (_) { }
      await fs.symlink('/proc/self/fd/' + handle.fd, path);
      if (!(await fs.stat(path)).isFile()) throw new Error('Original unavailable');
      const old = this.handles.get(key);
      this.handles.set(key, handle);
      if (old) await fs.close(old);
      return path;
    } catch (_) { try { await fs.close(handle); } catch (_) { } throw new Error('Original access failed'); }
  }
  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    if (this.busy || this.appContext === null) { result.error('UNAVAILABLE', 'Book access is busy', null); return; }
    this.busy = true;
    try {
      const args: Map<string, Object> = call.args;
      const prefs = await preferences.getPreferences(this.appContext, { name: 'moduLinkedBooksV1' });
      let records = JSON.parse(await prefs.get('records', '{}') as string) as Record<string, LinkedBook>;
      if (call.method === 'pick') {
        if (!this.context) throw new Error('No foreground window');
        this.selected.clear();
        const files = args.get('files') === true;
        const extensions = args.get('extensions') as string[];
        const uris = await new picker.DocumentViewPicker(this.context).select({
          selectMode: files ? picker.DocumentSelectMode.FILE : picker.DocumentSelectMode.FOLDER,
          maxSelectNumber: files ? 500 : 1,
        });
        const output: PickerEntry[] = [];
        for (const root of uris) {
          await fileShare.persistPermission([{ uri: root, operationMode: fileShare.OperationMode.READ_MODE }]);
          this.selectedRoots.add(root);
          await fileShare.activatePermission([{ uri: root, operationMode: fileShare.OperationMode.READ_MODE }]);
          const children = files ? [''] : await fs.listFile(new fileUri.FileUri(root).path, { recursion: true });
          for (const relative of children) {
            if (relative.split('/').some((part: string) => part === '..' || part.startsWith('.'))) continue;
            const uri = relative === '' ? root : root + '/' + relative.split('/').map((part: string) => encodeURIComponent(part)).join('/');
            const name = new fileUri.FileUri(uri).name;
            if (!extensions.includes(name.substring(name.lastIndexOf('.') + 1).toLowerCase())) continue;
            const candidate = await fs.open(uri, fs.OpenMode.READ_ONLY);
            let regular = false;
            try { regular = (await fs.stat(candidate.fd)).isFile(); }
            finally { await fs.close(candidate); }
            if (!regular) continue;
            const id = util.generateRandomUUID();
            this.selected.set(id, { uri: uri, root: root, name: name });
            output.push({ id: id, name: name, label: relative || name });
          }
        }
        result.success(output);
      } else if (call.method === 'link') {
        const source = this.selected.get(args.get('id') as string);
        if (!source) throw new Error('Unknown selection');
        const key = 'file/linked-' + util.generateRandomUUID() + '.' + source.name.split('.').pop()!.toLowerCase();
        const record: LinkedBook = { uri: source.uri, root: source.root };
        const path = await this.open(key, record);
        records[key] = record;
        await prefs.put('records', JSON.stringify(records)); await prefs.flush();
        result.success({ key: key, path: path });
      } else if (call.method === 'restoreLinks') {
        const paths: Record<string, string> = {};
        for (const key of Object.keys(records)) {
          try { paths[key] = await this.open(key, records[key]); } catch (_) { }
        }
        result.success(paths);
      } else if (call.method === 'forgetLink') {
        const key = args.get('key') as string;
        const handle = this.handles.get(key);
        if (handle) { await fs.close(handle); this.handles.delete(key); }
        const previous = records[key];
        const retained: Record<string, LinkedBook> = {};
        for (const other of Object.keys(records)) { if (other !== key) retained[other] = records[other]; }
        records = retained;
        await prefs.put('records', JSON.stringify(records)); await prefs.flush();
        if (previous && !Object.keys(records).some((other: string) => records[other].root === previous.root)) {
          try { await fileShare.revokePermission([{ uri: previous.root, operationMode: fileShare.OperationMode.READ_MODE }]); } catch (_) { }
        }
        result.success(null);
      } else if (call.method === 'release') {
        for (const root of this.selectedRoots) {
          if (!Object.keys(records).some((key: string) => records[key].root === root)) {
            try { await fileShare.revokePermission([{ uri: root, operationMode: fileShare.OperationMode.READ_MODE }]); } catch (_) { }
          }
        }
        this.selectedRoots.clear();
        this.selected.clear(); result.success(null);
      } else { result.notImplemented(); }
    } catch (_) { result.error('LINK_FAILED', 'Unable to access the original. Check file permission or import a copy.', null); }
    finally { this.busy = false; }
  }
}
