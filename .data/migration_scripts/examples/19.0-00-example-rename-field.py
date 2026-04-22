# Example: Rename a field across all files
# This script renames 'old_field_name' to 'new_field_name' in Python and XML files
#
# To use: Copy this file, rename it, and modify the patterns below

from __future__ import annotations

import re
import typing

if typing.TYPE_CHECKING:
    from odoo.cli.upgrade_code import FileManager


# Configuration - modify these values
OLD_FIELD = 'old_field_name'
NEW_FIELD = 'new_field_name'


def upgrade(file_manager: FileManager):
    """Rename field 'old_field_name' to 'new_field_name' across all files."""
    
    # Filter Python and XML files
    files = [
        f for f in file_manager
        if f.path.suffix in ('.py', '.xml')
    ]
    
    if not files:
        return
    
    # Compile patterns
    py_pattern = re.compile(rf"\b{OLD_FIELD}\b")
    xml_attr_pattern = re.compile(rf'name=["\']{OLD_FIELD}["\']')
    xml_field_pattern = re.compile(rf'field="{OLD_FIELD}"')
    
    for fileno, file in enumerate(files, start=1):
        content = file.content
        
        if file.path.suffix == '.py':
            content = py_pattern.sub(NEW_FIELD, content)
        
        elif file.path.suffix == '.xml':
            content = xml_attr_pattern.sub(f'name="{NEW_FIELD}"', content)
            content = xml_field_pattern.sub(f'field="{NEW_FIELD}"', content)
        
        file.content = content
        file_manager.print_progress(fileno, len(files), file.path)

