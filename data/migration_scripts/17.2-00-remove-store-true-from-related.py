"""Remove store=True from related fields (implicit since v17.2)."""
from __future__ import annotations

import re
import typing

if typing.TYPE_CHECKING:
    from odoo.cli.upgrade_code import FileManager


def upgrade(file_manager: FileManager):
    """Remove store=True from fields with related= attribute."""

    files = [
        f for f in file_manager
        if f.path.suffix == '.py'
    ]

    if not files:
        return

    # Patterns to remove store=True
    # Case 1: ", store=True)" at the end
    store_end = re.compile(r',\s*store\s*=\s*True(\s*\))')
    # Case 2: ", store=True," in the middle  
    store_middle = re.compile(r',\s*store\s*=\s*True\s*,')
    # Case 3: "(store=True, " at the start
    store_start = re.compile(r'(\(\s*)store\s*=\s*True\s*,\s*')

    for fileno, file in enumerate(files, start=1):
        content = file.content

        # Quick check
        if 'related=' not in content or 'store=True' not in content:
            file_manager.print_progress(fileno, len(files), file.path)
            continue

        lines = content.split('\n')
        new_lines = []
        
        for line in lines:
            # Only process lines that have both related= and store=True
            if 'related=' in line and 'store=True' in line:
                line = store_end.sub(r'\1', line)
                line = store_middle.sub(',', line)
                line = store_start.sub(r'\1', line)
            new_lines.append(line)

        new_content = '\n'.join(new_lines)

        if new_content != content:
            file.content = new_content

        file_manager.print_progress(fileno, len(files), file.path)
