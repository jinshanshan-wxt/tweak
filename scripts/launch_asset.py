"""Compile the pinned pack's existing bird SVG into a tiny launch bitmap."""
import struct
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


def white_bird_svg(data):
    root = ET.fromstring(data)
    assert root.tag == '{http://www.w3.org/2000/svg}svg'
    assert root.attrib['viewBox'] == '0 0 24 24'
    root.set('fill', '#ffffff')
    for element in root.iter():
        if element.get('fill') not in (None, 'none'):
            element.set('fill', '#ffffff')
    return ET.tostring(root, encoding='utf-8')


def png_size(data):
    assert data[:8] == b'\x89PNG\r\n\x1a\n' and data[12:16] == b'IHDR'
    return struct.unpack('>II', data[16:24])


def build_launch_asset(pack, bundle, resvg):
    with zipfile.ZipFile(pack) as archive:
        svg = white_bird_svg(archive.read('svgs/twitter.svg'))
    result = subprocess.run([str(resvg), '-w', '228', '-h', '228', '-', '-c'],
                            input=svg, capture_output=True, check=True)
    assert png_size(result.stdout) == (228, 228)
    target = Path(bundle) / 'NFBLaunchBird@3x.png'
    target.write_bytes(result.stdout)
    return target
