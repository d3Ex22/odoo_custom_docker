"""Rename message_post_with_view to message_post_with_source and values= to render_values= (v17.0)."""
from __future__ import annotations

import re
import typing

if typing.TYPE_CHECKING:
    from odoo.cli.upgrade_code import FileManager


def upgrade(file_manager: FileManager):
    """Migrate message_post_with_view API to message_post_with_source."""

    files = [
        f for f in file_manager
        if f.path.suffix == '.py'
    ]

    if not files:
        return

    method_pattern = re.compile(r'\.message_post_with_view\(')
    values_pattern = re.compile(r'\bvalues\s*=')

    for fileno, file in enumerate(files, start=1):
        content = file.content

        if 'message_post_with_view' not in content:
            file_manager.print_progress(fileno, len(files), file.path)
            continue

        # Step 1: Rename method
        new_content = method_pattern.sub('.message_post_with_source(', content)

        # Step 2: Replace values= with render_values= only within method calls
        positions = [(m.start(), m.end()) for m in re.finditer(r'\.message_post_with_source\(', new_content)]
        
        result = new_content
        offset = 0

        for start, end in positions:
            adjusted_end = end + offset
            paren_count = 1
            pos = adjusted_end

            while pos < len(result) and paren_count > 0:
                if result[pos] == '(':
                    paren_count += 1
                elif result[pos] == ')':
                    paren_count -= 1
                pos += 1

            call_args = result[adjusted_end:pos]
            new_call_args = values_pattern.sub('render_values=', call_args)

            if new_call_args != call_args:
                result = result[:adjusted_end] + new_call_args + result[pos:]
                offset += len(new_call_args) - len(call_args)

        if result != content:
            file.content = result

        file_manager.print_progress(fileno, len(files), file.path)
