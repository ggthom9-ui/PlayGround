#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "tools" / "icon-source.png"
RES = ROOT / "res"

DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

BRAND = (116, 71, 127, 255)
WHITE = (255, 255, 255, 255)


def load_art() -> Image.Image:
    image = Image.open(SOURCE).convert("RGBA")
    art = image.crop(image.getbbox())
    return art


def fit(art: Image.Image, box: int) -> Image.Image:
    scale = min(box / art.width, box / art.height)
    size = (max(1, round(art.width * scale)), max(1, round(art.height * scale)))
    return art.resize(size, Image.LANCZOS)


def legacy_icon(art: Image.Image, size: int, circular: bool) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    if circular:
        draw.ellipse((0, 0, size - 1, size - 1), fill=WHITE)
        scale = 0.68
    else:
        draw.rectangle((0, 0, size, size), fill=WHITE)
        scale = 0.78

    piece = fit(art, round(size * scale))
    canvas.alpha_composite(
        piece,
        ((size - piece.width) // 2, (size - piece.height) // 2),
    )
    return canvas


def adaptive_foreground(art: Image.Image, size: int = 432) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    piece = fit(art, round(size * 0.56))
    canvas.alpha_composite(
        piece,
        ((size - piece.width) // 2, (size - piece.height) // 2),
    )
    return canvas


def main() -> None:
    art = load_art()

    for density, size in DENSITIES.items():
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        legacy_icon(art, size, circular=False).save(folder / "ic_launcher.png")
        legacy_icon(art, size, circular=True).save(folder / "ic_launcher_round.png")

    foreground_folder = RES / "mipmap-xxxhdpi"
    foreground_folder.mkdir(parents=True, exist_ok=True)
    adaptive_foreground(art).save(foreground_folder / "ic_launcher_foreground.png")

    splash_folder = RES / "drawable-nodpi"
    splash_folder.mkdir(parents=True, exist_ok=True)
    splash = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    piece = fit(art, 384)
    splash.alpha_composite(piece, ((512 - piece.width) // 2, (512 - piece.height) // 2))
    splash.save(splash_folder / "splash_icon.png")

    print("Icons generated from", SOURCE)


if __name__ == "__main__":
    main()
