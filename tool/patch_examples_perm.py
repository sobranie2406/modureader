# -*- coding: utf-8 -*-
import io, re

HELPER = (
u"// Ask for anything this package declares but the device has not granted yet.\n"
u"// Grants start denied, so without this the first run always fails with a bare\n"
u"// \"could not run\" and the reader has to find the permission page themselves.\n"
u"async function ensurePermissions(capabilities, reason) {\n"
u"  var status = await modu.permissions.status();\n"
u"  var granted = (status && status.granted) || [];\n"
u"  var missing = [];\n"
u"  for (var i = 0; i < capabilities.length; i++) {\n"
u"    if (granted.indexOf(capabilities[i]) < 0) missing.push(capabilities[i]);\n"
u"  }\n"
u"  if (missing.length === 0) return true;\n"
u"  var answer = await modu.permissions.request({\n"
u"    capabilities: missing,\n"
u"    reason: reason\n"
u"  });\n"
u"  return !!answer && Array.isArray(answer.granted) && answer.granted.length > 0;\n"
u"}\n\n")

# file -> (capabilities, reason, first-statement marker, fallback title, fallback text)
JOBS = {
 'docs/examples/plugins/ai-annotator/main.js': (
   ['ai:invoke', 'note:write'],
   u"\u7528\u4f60\u7684\u6a21\u578b\u751f\u6210\u8bb2\u89e3\u5e76\u4fdd\u5b58\u4e3a\u6279\u6ce8\u3002",
   u'var ',
   u"AI \u6279\u6ce8",
   u"\u9700\u8981\u6a21\u578b\u4e0e\u4fdd\u5b58\u7b14\u8bb0\u7684\u6743\u9650\u3002"),
 'docs/examples/plugins/chapter-digest/main.js': (
   ['book:content', 'ai:invoke', 'note:write'],
   u"\u8981\u603b\u7ed3\u672c\u7ae0\uff0c\u9700\u8981\u6b63\u6587\u3001\u6a21\u578b\u4e0e\u4fdd\u5b58\u7b14\u8bb0\u3002",
   u'var ',
   u"\u672c\u7ae0\u901f\u89c8",
   u"\u9700\u8981\u6b63\u6587\u3001\u6a21\u578b\u4e0e\u7b14\u8bb0\u6743\u9650\u3002"),
 'docs/examples/plugins/note-cards/main.js': (
   ['note:read'],
   u"\u6c47\u603b\u6279\u6ce8\u9700\u8981\u8bfb\u53d6\u4f60\u7684\u7b14\u8bb0\u3002",
   u'var ',
   u"\u6279\u6ce8\u6c47\u603b",
   u"\u9700\u8981\u8bfb\u53d6\u7b14\u8bb0\u7684\u6743\u9650\u3002"),
 'docs/examples/plugins/reading-stats/main.js': (
   ['reading:read'],
   u"\u751f\u6210\u9605\u8bfb\u62a5\u544a\u9700\u8981\u8bfb\u53d6\u9605\u8bfb\u65f6\u957f\u3002",
   u'var ',
   u"\u9605\u8bfb\u62a5\u544a",
   u"\u9700\u8981\u8bfb\u53d6\u9605\u8bfb\u65f6\u957f\u7684\u6743\u9650\u3002"),
}

for path, (caps, reason, _marker, title, text) in JOBS.items():
    s = io.open(path, encoding='utf-8').read()
    if u'ensurePermissions' in s:
        print('already patched', path); continue
    # Insert the gate after the leading comment block and any leading blank line.
    lines = s.split(u'\n')
    insert_at = 0
    while insert_at < len(lines) and (lines[insert_at].startswith(u'//') or lines[insert_at].strip() == u''):
        insert_at += 1
    cap_list = u', '.join(u'"%s"' % c for c in caps)
    gate = (u"var allowed = await ensurePermissions([" + cap_list + u"],\n"
            u"    \"" + reason + u"\");\n"
            u"if (!allowed) {\n"
            u"  return { title: \"" + title + u"\", text: \"" + text + u"\" };\n"
            u"}\n\n")
    out = HELPER + u'\n'.join(lines[:insert_at]) + u'\n' + gate + u'\n'.join(lines[insert_at:])
    io.open(path, 'w', encoding='utf-8', newline='').write(out)
    print('patched', path)
