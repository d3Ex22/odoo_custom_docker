"""Remove 'type' field from ir.ui.view records (removed in 18.0)."""
from __future__ import annotations

import re
import typing

if typing.TYPE_CHECKING:
    from odoo.cli.upgrade_code import FileManager


def upgrade(file_manager: FileManager):
    """Remove type field from ir.ui.view XML records.
    
    In Odoo 18, the 'type' field in ir.ui.view records has been removed.
    The view type is now automatically detected from the root element of the arch field.
    
    Examples:
        <field name="type">tree</field>   -> removed (detected from <tree> or <list>)
        <field name="type">form</field>   -> removed (detected from <form>)
        <field name="type">kanban</field> -> removed (detected from <kanban>)
        <field name="type">search</field> -> removed (detected from <search>)
    """
    
    files = [
        f for f in file_manager
        if f.path.suffix == '.xml'
    ]
    
    if not files:
        return
    
    # Pattern to match <field name="type">...</field> with any whitespace
    # Captures the entire line including leading whitespace
    type_field_pattern = re.compile(
        r'^\s*<field\s+name=["\']type["\']>[^<]*</field>\s*\n?',
        re.MULTILINE
    )
    
    # Pattern to detect if file contains ir.ui.view records
    view_pattern = re.compile(r'model=["\']ir\.ui\.view["\']')
    
    for fileno, file in enumerate(files, start=1):
        content = file.content
        
        # Only process files with ir.ui.view records
        if not view_pattern.search(content):
            continue
        
        # Remove type field lines
        new_content = type_field_pattern.sub('', content)
        
        # Clean up any double blank lines that might result
        new_content = re.sub(r'\n\s*\n\s*\n', '\n\n', new_content)
        
        # Only update if content changed (this triggers file listing in dry-run)
        if new_content != content:
            file.content = new_content
        
        file_manager.print_progress(fileno, len(files), file.path)
