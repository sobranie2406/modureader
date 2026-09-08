"""Loopback-only, read-only WebDAV fixture. Contains only an original demo EPUB.
Run for manual preview testing; never point it at personal files.
"""
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import BytesIO
from threading import Timer
from urllib.parse import quote, unquote
from zipfile import ZipFile, ZIP_DEFLATED, ZIP_STORED

book = BytesIO()
with ZipFile(book, 'w') as archive:
    archive.writestr('mimetype', 'application/epub+zip', compress_type=ZIP_STORED)
    archive.writestr('META-INF/container.xml', '''<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''')
    archive.writestr('EPUB/book.opf', '''<?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:modu:webdav-preview:1</dc:identifier><dc:title>远程书库演示</dc:title><dc:creator>默读测试</dc:creator><dc:language>zh-CN</dc:language><meta property="dcterms:modified">2026-09-07T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>''')
    archive.writestr('EPUB/nav.xhtml', '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">第一章：远程书库</a></li></ol></nav></body></html>''')
    archive.writestr('EPUB/chapter.xhtml', '''<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章：远程书库</title></head><body><h1>第一章：远程书库</h1><p>这是默读远程书库功能的原创测试书籍，不包含用户的私人内容。</p><p>书籍通过本机 WebDAV 测试服务器下载，导入后保存在本地书架。即使服务器关闭，也应能够继续阅读。</p><p>这一页用于验证中文文件名、目录浏览、下载、导入和本地阅读的完整流程。</p></body></html>''', compress_type=ZIP_DEFLATED)
payload = book.getvalue()
folder = '/dav/中文目录/'
filename = folder + '远程书库演示.epub'


def response_item(path, directory=False):
    return ('<d:response><d:href>' + quote(path) + '</d:href><d:propstat><d:prop>'
            '<d:resourcetype>' + ('<d:collection/>' if directory else '') +
            '</d:resourcetype><d:getcontentlength>' + str(0 if directory else len(payload)) +
            '</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>')


class Handler(BaseHTTPRequestHandler):
    def authorized(self):
        if self.headers.get('Authorization') == 'Basic ' + base64.b64encode(b'demo:demo').decode():
            return True
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="Modu local test"')
        self.end_headers()
        return False

    def do_PROPFIND(self):
        if not self.authorized(): return
        self.rfile.read(int(self.headers.get('Content-Length', '0')))
        path = unquote(self.path)
        if path not in ('/dav/', folder): self.send_error(404); return
        listing = response_item(path, True) + (response_item(folder, True) if path == '/dav/' else response_item(filename))
        data = ('<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">' + listing + '</d:multistatus>').encode()
        self.send_response(207)
        self.send_header('Content-Type', 'application/xml; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not self.authorized(): return
        if unquote(self.path) != filename: self.send_error(404); return
        self.send_response(200)
        self.send_header('Content-Type', 'application/epub+zip')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        print(self.command, 'fixture request completed', flush=True)


if __name__ == '__main__':
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    print(f'Local fixture: http://127.0.0.1:{server.server_port}/dav/ (demo/demo)', flush=True)
    timer = Timer(1200, server.shutdown)
    timer.daemon = True
    timer.start()
    try: server.serve_forever()
    finally: server.server_close(); timer.cancel()
