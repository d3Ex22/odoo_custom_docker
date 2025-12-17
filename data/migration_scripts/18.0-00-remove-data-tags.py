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

    for fileno, file in enumerate(files, start=1):
        content = file.content

        # Check if file has <data> tags
        match = data_pattern.search(content)
        if not match:
            file_manager.print_progress(fileno, len(files), file.path)
            continue

        indent = match.group('indent')
        noupdate = match.group('noupdate')
        inner = match.group('content')

        # Dedent by removing one level of indentation (4 spaces or 1 tab)
        dedented_lines = []
        for line in inner.split('\n'):
            if line.startswith(indent + '    '):
                dedented_lines.append(line[len(indent) + 4:])
            elif line.startswith(indent + '\t'):
                dedented_lines.append(line[len(indent) + 1:])
            elif line.strip() == '':
                dedented_lines.append('')
            else:
                dedented_lines.append(line[len(indent):] if line.startswith(indent) else line)

        dedented = '\n'.join(dedented_lines)

        # Replace matched section using positions
        new_content = content[:match.start()] + dedented + content[match.end():]

        # If noupdate attribute exists, add it to <odoo> tag
        if noupdate:
            new_content = odoo_pattern.sub(f'<odoo {noupdate}>', new_content)

        if new_content != content:
            file.content = new_content

        file_manager.print_progress(fileno, len(files), file.path)
