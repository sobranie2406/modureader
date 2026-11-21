# -*- coding: utf-8 -*-
import io

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

JOBS = [
 ('docs/examples/plugins/vocab-notebook/add.js',
  ['dictionary:lookup', 'translate:invoke'],
  u"\u67e5\u8bcd\u5e76\u8bb0\u5165\u751f\u8bcd\u672c\u3002",
  u"\u751f\u8bcd\u672c",
  u"\u9700\u8981\u8bcd\u5178\u4e0e\u7ffb\u8bd1\u6743\u9650\u3002"),
 ('docs/examples/plugins/vocab-notebook/review.js',
  ['clipboard:write', 'ui:dialog'],
  u"\u590d\u4e60\u751f\u8bcd\u672c\u65f6\u9700\u8981\u786e\u8ba4\u4e0e\u590d\u5236\u3002",
  u"\u751f\u8bcd\u672c",
  u"\u9700\u8981\u5bf9\u8bdd\u6846\u4e0e\u526a\u8d34\u677f\u6743\u9650\u3002"),
]

for path, caps, reason, title, text in JOBS:
    s = io.open(path, encoding='utf-8').read()
    if u'ensurePermissions' in s:
        print('already patched', path); continue
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

# chapter-digest/ask.js
path = 'docs/examples/plugins/chapter-digest/ask.js'
s = io.open(path, encoding='utf-8').read()
if u'ensurePermissions' not in s:
    lines = s.split(u'\n')
    insert_at = 0
    while insert_at < len(lines) and (lines[insert_at].startswith(u'//') or lines[insert_at].strip() == u''):
        insert_at += 1
    gate = (u"var allowed = await ensurePermissions([\"ai:invoke\", \"knowledge:query\"],\n"
            u"    \"\u5c31\u672c\u4e66\u5185\u5bb9\u63d0\u95ee\u9700\u8981\u6a21\u578b\u4e0e\u672c\u5730\u7d22\u5f15\u3002\");\n"
            u"if (!allowed) {\n"
            u"  return { title: \"\u95ee\u672c\u4e66\", text: \"\u9700\u8981\u6a21\u578b\u4e0e\u672c\u5730\u7d22\u5f15\u6743\u9650\u3002\" };\n"
            u"}\n\n")
    out = HELPER + u'\n'.join(lines[:insert_at]) + u'\n' + gate + u'\n'.join(lines[insert_at:])
    io.open(path, 'w', encoding='utf-8', newline='').write(out)
    print('patched', path)
