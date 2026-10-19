"""Remove <data> tags from XML files, moving noupdate attribute to <odoo> tag (v18.0)."""
from __future__ import annotations

import re
import typing

if typing.TYPE_CHECKING:
    from odoo.cli.upgrade_code import FileManager


def upgrade(file_manager: FileManager):
    """Remove <data> tags and transfer noupdate attribute to <odoo> tag."""

    files = [
        f for f in file_manager
        if f.path.suffix == '.xml'
    ]

    if not files:
        return

    # Pattern to match <data> with optional noupdate attribute (handles indentation)
    data_pattern = re.compile(
        r'^(?P<indent>[ \t]*)<data(?:\s+(?P<noupdate>noupdate=["\'][01]["\']))?>\n'
        r'(?P<content>.*?)'
        r'^(?P=indent)</data>\n?',
        re.MULTILINE | re.DOTALL
    )

    # Pattern to match <odoo> tag (to add noupdate if needed)
    odoo_pattern = re.compile(r'<odoo>')

    def dedent(block: str, indent: str) -> str:
        """Remove one indentation level (4 spaces or a tab) below the <data> indent."""
        lines = []
        for line in block.split('\n'):
            if line.startswith(indent + '    '):
                lines.append(line[4:])
            elif line.startswith(indent + '\t'):
                lines.append(line[1:])
            else:
                lines.append(line)
        return '\n'.join(lines)

    for fileno, file in enumerate(files, start=1):
        content = file.content
        noupdate = None

        def replace(match: re.Match) -> str:
            nonlocal noupdate
            noupdate = noupdate or match.group('noupdate')
            return dedent(match.group('content'), match.group('indent'))

        new_content = data_pattern.sub(replace, content)
        if noupdate:
            new_content = odoo_pattern.sub(f'<odoo {noupdate}>', new_content, count=1)

        if new_content != content:
            file.content = new_content

        file_manager.print_progress(fileno, len(files), file.path)
