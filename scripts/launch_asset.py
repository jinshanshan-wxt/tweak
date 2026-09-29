"""Pre-render the pinned classic bird as an alpha mask; no runtime SVG parsing."""
import struct
import subprocess
import xml.etree.ElementTree as ET
import zipfile


def build_launch_asset(pack, bundle, resvg):
    with zipfile.ZipFile(pack) as archive:
        svg = ET.fromstring(archive.read('svgs/twitter.svg'))
    assert svg.tag == '{http://www.w3.org/2000/svg}svg'
    assert svg.attrib['viewBox'] == '0 0 24 24'
    svg.set('fill', '#ffffff')
    for element in svg.iter():
        if element.attrib.get('fill') != 'none':
            element.set('fill', '#ffffff')
    data = subprocess.check_output([str(resvg), '-w', '1024', '-h', '1024', '-', '-c'],
                                   input=ET.tostring(svg, encoding='utf-8'))
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', data[16:24]) == (1024, 1024)
    assert data[25] == 6, 'Mask must preserve RGBA transparency'
    path = bundle / 'NFBLaunchMask.png'
    path.write_bytes(data)
    return path
