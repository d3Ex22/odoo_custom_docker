"""Remove 'doall' and 'numbercall' fields from ir.cron records (removed in 19.0)."""
from __future__ import annotations

import re
import typing

if typing.TYPE_CHECKING:
    from odoo.cli.upgrade_code import FileManager


def upgrade(file_manager: FileManager):
    """Remove numbercall and doall fields from ir.cron XML records."""
    
    files = [
        f for f in file_manager
        if f.path.suffix == '.xml'
    ]
    
    if not files:
        return
    
    # Pattern to match <field> tags with name="doall" or name="numbercall"
    # Handles any attribute order: <field name="doall"...> or <field eval="..." name="doall"...>
    # Matches both self-closing /> and closing </field>
    deprecated_field_pattern = re.compile(
        r'^\s*<field\s+[^>]*name=["\'](?:numbercall|doall)["\'][^>]*/>\s*\n?|'
        r'^\s*<field\s+[^>]*name=["\'](?:numbercall|doall)["\'][^>]*>.*?</field>\s*\n?',
        re.MULTILINE
    )
    
    # Pattern to detect if file contains ir.cron records
    cron_pattern = re.compile(r'model=["\']ir\.cron["\']')
    
    for fileno, file in enumerate(files, start=1):
        content = file.content
        
        # Only process files with ir.cron records
        if not cron_pattern.search(content):
            continue
        
        # Remove deprecated fields
        new_content = deprecated_field_pattern.sub('', content)
        
        # Clean up any double blank lines that might result
        new_content = re.sub(r'\n\s*\n\s*\n', '\n\n', new_content)
        
        # Only update if content changed (this triggers file listing in dry-run)
        if new_content != content:
            file.content = new_content
        
        file_manager.print_progress(fileno, len(files), file.path)
