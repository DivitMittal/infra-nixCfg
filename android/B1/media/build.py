"""Render the B1 screensaver and build a deterministic Magisk media module."""

from io import BytesIO
from pathlib import Path
import sys
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo

from PIL import Image, ImageDraw, ImageFont

SIZE = (758, 1024)
FRAMES = 12
FPS = 4
MODULE = """id=b1-media
name=B1 Media
version=1.0
versionCode=1
author=infra-nixCfg
description=Monochrome boot animation and standby and shutdown artwork for B1.
"""


def render(font_path, label, progress=None):
    image = Image.new("L", SIZE, 255)
    draw = ImageDraw.Draw(image)
    ink = 16
    draw.line([(181, 389), (232, 367), (288, 365), (336, 378), (379, 401),
               (422, 378), (470, 365), (526, 367), (577, 389),
               (577, 522), (526, 505), (470, 503), (422, 514), (379, 537),
               (336, 514), (288, 503), (232, 505), (181, 522), (181, 389)],
              fill=ink, width=7, joint="curve")
    draw.line([(379, 401), (379, 537)], fill=ink, width=7)
    draw.text((379, 623), "B1", font=ImageFont.truetype(font_path, 84), fill=ink, anchor="mm")
    draw.text((379, 690), label, font=ImageFont.truetype(font_path, 24), fill=ink, anchor="mm")
    if progress is not None:
        draw.line([(279, 794), (479, 794)], fill=212, width=4)
        draw.line([(279, 794), (279 + round(200 * progress), 794)], fill=ink, width=4)
    buffer = BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def add(archive, name, content, compression):
    # The default ZipInfo timestamp and fixed mode keep builds reproducible.
    entry = ZipInfo(name)
    entry.create_system = 3
    entry.external_attr = 0o100644 << 16
    archive.writestr(entry, content, compress_type=compression)


def main(output, font_path):
    output.mkdir(parents=True, exist_ok=True)
    standby = render(font_path, "Standby")
    shutdown = render(font_path, "Powered off")
    (output / "B1-standby.png").write_bytes(standby)

    animation = BytesIO()
    with ZipFile(animation, "w") as archive:
        add(archive, "desc.txt", f"{SIZE[0]} {SIZE[1]} {FPS}\np 1 0 part0\np 0 0 part1\n", ZIP_STORED)
        for frame in range(FRAMES):
            add(archive, f"part0/{frame:04}.png", render(font_path, "Starting", (frame + 1) / FRAMES), ZIP_STORED)
        add(archive, "part1/0000.png", render(font_path, "Starting", 1), ZIP_STORED)
    with ZipFile(output / "b1-media.zip", "w") as archive:
        add(archive, "module.prop", MODULE, ZIP_DEFLATED)
        add(archive, "system/media/standby-1.png", standby, ZIP_DEFLATED)
        add(archive, "system/media/shutdown-default.png", shutdown, ZIP_DEFLATED)
        add(archive, "system/media/bootanimation.zip", animation.getvalue(), ZIP_STORED)


if __name__ == "__main__":
    main(Path(sys.argv[1]), sys.argv[2])
