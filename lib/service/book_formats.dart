/// Shared by local imports, replacement and remote-library filtering.
const allowBookExtensions = [
  'epub',
  'mobi',
  'azw3',
  'fb2',
  'txt',
  'pdf',
  'md',
  'markdown',
];

bool isMarkdownExtension(String extension) =>
    const ['md', 'markdown'].contains(extension.toLowerCase());
