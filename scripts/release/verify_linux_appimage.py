"""Open synthetic EPUB and PDF books in the AppImage and check the visible page."""
from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import signal
import sqlite3
import struct
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlencode
from zipfile import ZipFile


def write_epub(path):
    with ZipFile(path, 'w') as book:
        book.writestr('mimetype', 'application/epub+zip')
        book.writestr('META-INF/container.xml', '''<container version="1.0"
xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>
<rootfile full-path="book.opf" media-type="application/oebps-package+xml"/>
</rootfiles></container>''')
        book.writestr('book.opf', '''<package xmlns="http://www.idpf.org/2007/opf"
version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">modu-appimage-smoke</dc:identifier><dc:title>Modu EPUB Smoke</dc:title>
<dc:language>en</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
</metadata><manifest>
<item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml" properties="svg"/>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
</manifest><spine><itemref idref="chapter"/></spine></package>''')
        book.writestr('nav.xhtml', '''<html xmlns="http://www.w3.org/1999/xhtml"
xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head>
<body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">Smoke test</a></li></ol></nav></body></html>''')
        book.writestr('chapter.xhtml', '''<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Modu EPUB Smoke</title></head><body><h1>Modu EPUB Smoke</h1>
<svg xmlns="http://www.w3.org/2000/svg" width="440" height="300" viewBox="0 0 440 300">
<rect width="440" height="300" fill="#e145cf"/></svg></body></html>''')


def write_pdf(path):
    stream = b'0.243137 0.721569 0.298039 rg 35 35 530 530 re f\n'
    objects = [
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 600] /Contents 4 0 R >>',
        f'<< /Length {len(stream)} >>\nstream\n'.encode() + stream + b'endstream',
    ]
    pdf = b'%PDF-1.4\n'
    offsets = []
    for index, obj in enumerate(objects, 1):
        offsets.append(len(pdf))
        pdf += f'{index} 0 obj\n'.encode() + obj + b'\nendobj\n'
    xref = len(pdf)
    pdf += b'xref\n0 5\n0000000000 65535 f \n'
    pdf += b''.join(f'{offset:010d} 00000 n \n'.encode() for offset in offsets)
    pdf += f'trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
    path.write_bytes(pdf)


def all_imported(data, hashes):
    for database in data.rglob('app_database.db'):
        try:
            with sqlite3.connect(f'{database.as_uri()}?mode=ro', uri=True) as db:
                imported = {row[0] for row in db.execute('SELECT file_md5 FROM tb_books')}
                return hashes <= imported
        except sqlite3.OperationalError:
            continue
    return False


XWD_HEADER = struct.Struct('>25I')


def framebuffer_details(framebuffer):
    if not framebuffer.exists():
        return 'framebuffer file is missing'
    with framebuffer.open('rb') as source:
        header = source.read(XWD_HEADER.size)
    if len(header) < XWD_HEADER.size:
        return f'framebuffer header is {len(header)} bytes'
    fields = XWD_HEADER.unpack(header)
    return (f'framebuffer {fields[4]}x{fields[5]}, depth {fields[3]}, '
            f'{fields[11]} bpp, stride {fields[12]}, RGB masks '
            f'{fields[14]:#x}/{fields[15]:#x}/{fields[16]:#x}')


def visible_marker(framebuffer, color):
    if not framebuffer.exists():
        return False
    frame = framebuffer.read_bytes()
    if len(frame) < XWD_HEADER.size:
        return False
    header = XWD_HEADER.unpack_from(frame)
    size, version, pixmap_format, _, width, height, _, order = header[:8]
    bits, stride, _, red, green, blue = header[11:17]
    if (version, pixmap_format) != (7, 2) or bits not in (24, 32) or order not in (0, 1):
        return False
    rgb_mask = red | green | blue
    if not all((red, green, blue)) or rgb_mask >= 1 << bits:
        return False
    pixel_size = bits // 8
    # XWD stores 12 bytes per colormap entry before the pixel data.
    start = size + 12 * header[19]
    if (size < XWD_HEADER.size or stride < width * pixel_size or
            start + height * stride > len(frame)):
        return False

    marker = 0
    for channel, mask in zip(bytes.fromhex(color), (red, green, blue)):
        shift = (mask & -mask).bit_length() - 1
        marker |= ((channel * (mask >> shift) + 127) // 255) << shift

    byte_order = 'little' if order == 0 else 'big'
    left = width // 5 * pixel_size
    right = width * 4 // 5 * pixel_size
    pixels = 0
    for y in range(height // 6, height * 5 // 6):
        offset = start + y * stride
        pixels += sum(
            int.from_bytes(frame[i:i + pixel_size], byte_order) & rgb_mask == marker
            for i in range(offset + left, offset + right, pixel_size)
        )
        # Import thumbnails are smaller than the rendered marker on the page.
        if pixels > 20_000:
            return True
    return False


def wait_for_app(process, condition, description, failure_details=None):
    deadline = time.monotonic() + 50
    while time.monotonic() < deadline and process.poll() is None:
        if condition():
            print(f'Verified {description}', flush=True)
            return
        time.sleep(0.75)
    details = f'; {failure_details()}' if failure_details else ''
    raise RuntimeError(f'{description} was not observed (exit status {process.poll()}{details})')


@contextmanager
def launch(appimage, args, log, env):
    with log.open('w') as output:
        process = subprocess.Popen([appimage, *args], env=env,
                                   stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            yield process
        finally:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()


def verify(appimage, work, framebuffer):
    env = os.environ | {
        'APPIMAGE_EXTRACT_AND_RUN': '1',
        'GDK_BACKEND': 'x11',
        'GSETTINGS_BACKEND': 'memory',
        'LIBGL_ALWAYS_SOFTWARE': '1',
        'HOME': str(work),
    }
    for name in ('CACHE', 'CONFIG', 'DATA', 'RUNTIME'):
        directory = work / name.lower()
        directory.mkdir(mode=0o700)
        env[f'XDG_{name}' + ('_HOME' if name != 'RUNTIME' else '_DIR')] = str(directory)

    files = [work / 'smoke.epub', work / 'smoke.pdf']
    write_epub(files[0])
    write_pdf(files[1])
    hashes = [hashlib.md5(path.read_bytes()).hexdigest() for path in files]
    with launch(appimage, files, work / 'import.log', env) as process:
        wait_for_app(process, lambda: all_imported(work / 'data', set(hashes)),
                     'EPUB and PDF import')
    for path, digest, marker in zip(files, hashes, ('e145cf', '3eb84c')):
        link = 'modu://read?' + urlencode({
            'v': '1', 'md5': digest, 'title': '', 'author': '',
            'created': '2026-01-01T00:00:00Z', 'cfi': 'epubcfi(/6/2)',
        })
        with launch(appimage, [link], work / (path.name + '.log'), env) as process:
            wait_for_app(process, lambda: visible_marker(framebuffer, marker),
                         f'{path.suffix[1:].upper()} page rendering',
                         lambda: framebuffer_details(framebuffer))


if __name__ == '__main__':
    if sys.platform != 'linux' or os.geteuid() == 0:
        raise RuntimeError('Run this smoke test on Linux as a regular user inside an X11 session')
    with tempfile.TemporaryDirectory(prefix='modu-appimage-test-') as tmp:
        work = Path(tmp)
        try:
            verify(Path(sys.argv[1]).resolve(strict=True), work, Path(sys.argv[2]))
        except Exception:
            for log in sorted(work.rglob('*.log')):
                print(f'\n--- {log.name} ---\n{log.read_text(errors="replace")[-12_000:]}',
                      file=sys.stderr)
            raise
