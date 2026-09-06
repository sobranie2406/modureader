"""Inspect actual DEX definitions, not strings or unminified Java artifacts."""
import os
from pathlib import Path
import re
import subprocess
import tempfile


# Signatures used by libonnxruntime4j_jni when wrapping inference outputs.
# R8 can retain OnnxTensor's class name but rewrite/remove its constructor.
CONSTRUCTORS = {
    'Lai/onnxruntime/TensorInfo;': '([J[Ljava/lang/String;I)V',
    'Lai/onnxruntime/OnnxTensor;': '(JJLai/onnxruntime/TensorInfo;)V',
}
REQUIRED_CLASSES = set(CONSTRUCTORS) | {
    'Lai/onnxruntime/OnnxJavaType;',
    'Lai/onnxruntime/TensorInfo$OnnxTensorType;',
    'Lai/onnxruntime/OrtException;',
    'Lai/onnxruntime/OrtSession;',
}


def definitions(dump):
    result = {}
    for block in re.split(r'(?m)^Class #\d+', dump)[1:]:
        match = re.search(r"Class descriptor\s*:\s*'([^']+)'", block)
        if not match:
            raise ValueError('Cannot parse DEX class definition')
        # Only defined methods inside class_data, not external method IDs.
        methods = block.split('Direct methods', 1)
        result[match[1]] = set(re.findall(
            r"name\s*:\s*'([^']+)'\s+type\s*:\s*'([^']+)'",
            methods[1] if len(methods) == 2 else ''))
    return result


def verify_definitions(classes):
    missing = REQUIRED_CLASSES - classes.keys()
    if missing:
        raise ValueError('ONNX JNI classes removed/renamed by R8: ' + ', '.join(sorted(missing)))
    for name, signature in CONSTRUCTORS.items():
        if ('<init>', signature) not in classes[name]:
            raise ValueError(f'ONNX JNI constructor removed/rewritten by R8: {name} {signature}')


def verify_onnx_jni(archive):
    sdk = Path(os.environ['ANDROID_HOME'])
    candidates = sorted((sdk / 'build-tools').glob('*/dexdump'))
    if not candidates:
        raise ValueError('Android SDK dexdump is required for release JNI validation')
    classes = {}
    with tempfile.TemporaryDirectory(prefix='modu-dex-check-') as tmp:
        for name in archive.namelist():
            if not re.fullmatch(r'classes(?:[2-9]|[1-9][0-9]+)?\.dex', name):
                continue
            dex = Path(tmp) / name
            dex.write_bytes(archive.read(name))
            dump = subprocess.check_output([str(candidates[-1]), str(dex)], text=True,
                                           errors='replace', timeout=90)
            current = definitions(dump)
            if classes.keys() & current.keys():
                raise ValueError('Duplicate class definitions in APK')
            classes.update(current)
    verify_definitions(classes)
    print('ONNX JNI: original class names and native result constructors verified in release DEX')
