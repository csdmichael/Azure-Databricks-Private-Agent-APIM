"""Generates the colour and outline icons for each agent's Microsoft 365 package.

Run once after changing the catalog; the PNGs are committed to the repo so the
API has no image dependency at runtime.

    python scripts/generate_agent_icons.py
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parents[1]
ASSETS = REPO_ROOT / "api" / "app" / "m365_assets"

# Microsoft 365 requires a 192x192 colour icon and a 32x32 transparent outline icon.
COLOR_SIZE = 192
OUTLINE_SIZE = 32


def _rounded_background(color: str) -> Image.Image:
    image = Image.new("RGBA", (COLOR_SIZE, COLOR_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle([0, 0, COLOR_SIZE - 1, COLOR_SIZE - 1], radius=38, fill=color)
    return image


def draw_sql_color() -> Image.Image:
    """A database cylinder with a rising bar chart: governed SQL to charts."""
    image = _rounded_background("#B3241A")
    draw = ImageDraw.Draw(image)

    # Database cylinder.
    left, right, top, bottom = 34, 100, 40, 128
    draw.ellipse([left, top, right, top + 22], fill="#FFFFFF")
    draw.rectangle([left, top + 11, right, bottom], fill="#FFFFFF")
    draw.ellipse([left, bottom - 11, right, bottom + 11], fill="#FFFFFF")
    for offset in (30, 58):
        draw.ellipse([left, top + offset, right, top + offset + 22], outline="#B3241A", width=5)

    # Bar chart.
    for index, height in enumerate((34, 58, 82)):
        x0 = 112 + index * 22
        draw.rounded_rectangle([x0, 140 - height, x0 + 15, 148], radius=4, fill="#FFC5C0")
    draw.rounded_rectangle([110, 150, 176, 156], radius=3, fill="#FFFFFF")
    return image


def draw_genie_color() -> Image.Image:
    """A speech bubble with a sparkle: natural-language analytics."""
    image = _rounded_background("#0F5BA7")
    draw = ImageDraw.Draw(image)

    draw.rounded_rectangle([30, 42, 162, 128], radius=26, fill="#FFFFFF")
    draw.polygon([(62, 126), (62, 162), (98, 126)], fill="#FFFFFF")

    def sparkle(cx: int, cy: int, radius: int, waist: int, color: str) -> None:
        draw.polygon(
            [
                (cx, cy - radius),
                (cx + waist, cy - waist),
                (cx + radius, cy),
                (cx + waist, cy + waist),
                (cx, cy + radius),
                (cx - waist, cy + waist),
                (cx - radius, cy),
                (cx - waist, cy - waist),
            ],
            fill=color,
        )

    sparkle(88, 84, 34, 9, "#0F5BA7")
    sparkle(132, 60, 16, 4, "#0F5BA7")
    return image


def draw_sql_outline() -> Image.Image:
    """Transparent single-colour glyph: a database cylinder."""
    image = Image.new("RGBA", (OUTLINE_SIZE, OUTLINE_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    white = (255, 255, 255, 255)
    draw.ellipse([7, 5, 25, 11], outline=white, width=2)
    draw.line([(7, 8), (7, 24)], fill=white, width=2)
    draw.line([(25, 8), (25, 24)], fill=white, width=2)
    draw.arc([7, 21, 25, 27], start=0, end=180, fill=white, width=2)
    draw.arc([7, 13, 25, 19], start=0, end=180, fill=white, width=2)
    return image


def draw_genie_outline() -> Image.Image:
    """Transparent single-colour glyph: a speech bubble with a sparkle."""
    image = Image.new("RGBA", (OUTLINE_SIZE, OUTLINE_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    white = (255, 255, 255, 255)
    draw.rounded_rectangle([4, 5, 28, 22], radius=5, outline=white, width=2)
    draw.line([(10, 22), (10, 28)], fill=white, width=2)
    draw.line([(10, 28), (17, 22)], fill=white, width=2)
    draw.line([(16, 8), (16, 19)], fill=white, width=2)
    draw.line([(11, 13), (21, 13)], fill=white, width=2)
    return image


ICONS = {
    "databricks-sql": (draw_sql_color, draw_sql_outline),
    "databricks-genie": (draw_genie_color, draw_genie_outline),
}


def main() -> int:
    for agent_id, (color_fn, outline_fn) in ICONS.items():
        target = ASSETS / agent_id
        target.mkdir(parents=True, exist_ok=True)
        color_fn().save(target / "color.png", "PNG")
        outline_fn().save(target / "outline.png", "PNG")
        print(f"wrote {target / 'color.png'} and {target / 'outline.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
