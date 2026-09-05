"""Generate an original, non-private EPUB for documentation screenshots."""
from pathlib import Path
from html import escape
from zipfile import ZipFile, ZIP_STORED, ZIP_DEFLATED

CHAPTERS = [
    ('把一页书读深', [
        '阅读，让思考慢下来。',
        '清晨，把一本书打开，先不急着寻找结论。让目光跟着句子向前，遇见值得停留的地方，就多读一次。阅读的意义，有时不在于今天翻过了多少页，而在于哪一个问题开始有了新的模样。',
        '读到一个陌生的概念，可以先用自己的话解释它。解释得清楚，说明我们已经抓住了一部分；解释不清楚，也不必着急，那正是继续阅读的起点。带着问题回到原文，比匆忙记住一个答案更有价值。',
        '一本书不需要一次读完。目录帮助我们看见全貌，书签让我们找回停下的位置，笔记则保存那些稍纵即逝的想法。把这些线索连在一起，零散的阅读就逐渐成为自己的知识。',
        '试着给今天读过的一页写一句总结：作者在回答什么问题？他给出了哪些理由？我赞同其中的哪一部分，又有什么疑问？不必写得漂亮，只需要诚实地记录此刻的理解。',
        '合上书以后，留一点空白。让一个句子、一幅画面或者一个问题，在心里继续停留。好的阅读并不总是立刻带来答案，它也会教我们更耐心地提问。',
    ]),
    ('让 AI 成为阅读伙伴', [
        '先读原文，再展开对话。',
        'AI 可以帮助梳理章节结构、解释概念，或提供新的讨论角度。提出问题时，不妨说清楚自己的目的：是想快速回顾，还是想检查一段论证？问题越具体，越容易判断回答是否真正有帮助。',
        '面对一段总结，我们仍然需要回到书中核对。哪些信息来自原文，哪些只是推测？引用能否定位到相关段落？把 AI 的回答当作讨论的起点，而不是代替阅读的终点。',
        '阅读技能可以成为一种提问习惯。先梳理本章的核心观点，再寻找支持观点的证据，最后写下自己的疑问。不同的书适合不同的读法，也可以按自己的目的编辑提示词。',
        '如果问题涉及整本书，可以借助索引寻找相关段落。如果问题只针对当前章节，就应当保持范围清楚。检索到的信息并不天然正确，理解它仍然需要上下文。',
        '技术最好的位置，是帮助我们更专注地阅读。它可以缩短寻找资料的时间，但不必替我们决定一本书的意义。保留自己的判断，让对话回到文本，也回到真实的经验。',
    ]),
    ('留下自己的理解', [
        '笔记不是摘抄的终点，而是思考的开始。',
        '记下一个观点时，也写下它为什么引起注意。它与过去的经验有什么联系？它改变了什么，又留下了什么疑问？这样的笔记，在下一次翻看时仍然能够开启对话。',
        '不必把每个段落都标亮。选择少数真正重要的句子，为它们留下自己的解释。少一点堆积，多一点连接，阅读记录才会慢慢变成能够使用的知识。',
        '隔一段时间回顾笔记，可以发现理解的变化。曾经觉得难懂的地方，也许已经自然地融入新的认识。也有一些旧问题，会因为另一本书而得到不同的回答。',
        '这本小册子是默读项目为界面展示创作的示例内容，不包含私人资料，也不代表任何模型的实际回答。你可以用它体验阅读、目录与 AI 功能入口。',
    ]),
]

def build():
    path = Path(__file__).with_name('modu-reading-demo.epub')
    style = 'body{line-height:1.9}h1{font-size:1.55em;margin:1.8em 0 1.2em}p{margin:0 0 1em}p.lead{font-weight:bold}'
    manifest, spine, toc = [], [], []
    with ZipFile(path, 'w', compression=ZIP_DEFLATED) as z:
        z.writestr('mimetype', 'application/epub+zip', compress_type=ZIP_STORED)
        z.writestr('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        for index, (title, paragraphs) in enumerate(CHAPTERS, 1):
            filename = f'chapter{index}.xhtml'
            content = ''.join(f'<p class="{"lead" if n == 0 else "body"}">{escape(p)}</p>' for n, p in enumerate(paragraphs))
            z.writestr('OEBPS/' + filename, f'<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml" lang="zh-CN"><head><title>{title}</title><style>{style}</style></head><body><h1>第{index}章 · {title}</h1>{content}</body></html>')
            manifest.append(f'<item id="c{index}" href="{filename}" media-type="application/xhtml+xml"/>')
            spine.append(f'<itemref idref="c{index}"/>')
            toc.append(f'<li><a href="{filename}">第{index}章 · {title}</a></li>')
        z.writestr('OEBPS/nav.xhtml', '<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body><nav epub:type="toc"><ol>' + ''.join(toc) + '</ol></nav></body></html>')
        z.writestr('OEBPS/book.opf', '<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:modu:documentation:reading-demo:1</dc:identifier><dc:title>阅读，让思考慢下来</dc:title><dc:creator>默读功能演示</dc:creator><dc:language>zh-CN</dc:language><dc:rights>Original Modu documentation sample; GPL-3.0-or-later.</dc:rights><meta property="dcterms:modified">2026-09-05T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>' + ''.join(manifest) + '</manifest><spine>' + ''.join(spine) + '</spine></package>')
    print(path)

if __name__ == '__main__':
    build()
