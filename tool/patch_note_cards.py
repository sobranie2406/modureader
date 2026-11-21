# -*- coding: utf-8 -*-
import io, os

REASON_SEARCH = u"\u67e5\u627e\u76f8\u5173\u6279\u6ce8\u9700\u8981\u8bfb\u53d6\u4e66\u5e93\u4e0e\u7b14\u8bb0\u3002"
BLOCK_SEARCH = u"\u9700\u8981\u4e66\u5e93\u4e0e\u7b14\u8bb0\u7684\u8bfb\u53d6\u6743\u9650\u3002"
TITLE_SEARCH = u"\u67e5\u627e\u76f8\u5173\u6279\u6ce8"

def helper(reason, indent=''):
    return (
u"// Ask for anything this package declares but the device has not granted yet.\n"
u"// Grants start denied, so without this the first run always fails with a bare\n"
u"// \"could not run\" and the reader has to find the permission page themselves.\n"
u"async function ensurePermissions(capabilities) {\n"
u"  var status = await modu.permissions.status();\n"
u"  var granted = (status && status.granted) || [];\n"
u"  var missing = [];\n"
u"  for (var i = 0; i < capabilities.length; i++) {\n"
u"    if (granted.indexOf(capabilities[i]) < 0) missing.push(capabilities[i]);\n"
u"  }\n"
u"  if (missing.length === 0) return true;\n"
u"  var answer = await modu.permissions.request({\n"
u"    capabilities: missing,\n"
u"    reason: \"" + reason + u"\"\n"
u"  });\n"
u"  return !!answer && Array.isArray(answer.granted) && answer.granted.length > 0;\n"
u"}\n\n")

def patch(path, caps, marker, gate_title, gate_text, reason):
    s = io.open(path, encoding='utf-8').read()
    if u'ensurePermissions' in s:
        print('already patched', path); return
    i = s.index(marker)
    cap_list = ', '.join('"%s"' % c for c in caps)
    gate = (u"var allowed = await ensurePermissions([" + cap_list + u"]);\n"
            u"if (!allowed) {\n"
            u"  return { title: \"" + gate_title + u"\", text: \"" + gate_text + u"\" };\n"
            u"}\n\n")
    s = helper(reason) + s[:i] + gate + s[i:]
    io.open(path, 'w', encoding='utf-8', newline='').write(s)
    print('patched', path)

patch('docs/examples/plugins/note-cards/from-selection.js',
      ['search:library'],
      u'var result = await modu.search.library(',
      TITLE_SEARCH, BLOCK_SEARCH, REASON_SEARCH)
